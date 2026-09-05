(function () {
  const CONFIG = {
    owner: 'delelimed',
    repo: 'CatechHub',
    fallbackBranch: 'main',
    filename: 'FUTURE.md',
  };

  const el = (sel) => document.querySelector(sel);

  function renderMarkdown(md) {
    const target = el('#future-content');
    if (!target) return;
    if (typeof marked !== 'undefined') {
      target.innerHTML = marked.parse(md);
    } else {
      target.textContent = md;
    }
  }

  async function fetchAllBranches() {
    const api = 'https://api.github.com/repos/' + CONFIG.owner + '/' + CONFIG.repo + '/branches';
    let branches = [];
    let page = 1;
    while (true) {
      const res = await fetch(api + '?per_page=100&page=' + page);
      if (!res.ok) {
        if (branches.length) break;
        throw new Error('HTTP ' + res.status);
      }
      const batch = await res.json();
      if (!Array.isArray(batch) || batch.length === 0) break;
      branches = branches.concat(batch);
      if (batch.length < 100) break;
      page += 1;
    }
    return branches;
  }

  function pickBranch(branches) {
    const features = branches
      .filter((b) => b.name.startsWith('feature/'))
      .sort((a, b) => new Date(b.commit.commit.committer.date) - new Date(a.commit.commit.committer.date));
    return features[0] ? features[0].name : CONFIG.fallbackBranch;
  }

  function fetchFromGitHub(branch) {
    const url = [
      'https://raw.githubusercontent.com',
      CONFIG.owner,
      CONFIG.repo,
      branch,
      CONFIG.filename,
    ].join('/');

    return fetch(url)
      .then((r) => (r.ok ? r.text() : Promise.reject('HTTP ' + r.status)))
      .then((md) => renderMarkdown(md))
      .catch(() => {
        const target = el('#future-content');
        if (target) {
          target.innerHTML =
            '<p class="alert alert-warning">Impossibile caricare le implementazioni future. Consulta il file <a href="https://github.com/' +
            CONFIG.owner +
            '/' +
            CONFIG.repo +
            '/blob/' +
            branch +
            '/' +
            CONFIG.filename +
            '">FUTURE.md su GitHub</a>.</p>';
        }
      });
  }

  fetchAllBranches()
    .then(pickBranch)
    .catch(() => CONFIG.fallbackBranch)
    .then(fetchFromGitHub);
})();