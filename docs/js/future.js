(function () {
  const CONFIG = {
    owner: 'delelimed',
    repo: 'CatechHub',
    branch: 'main',
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

  function fetchFromGitHub() {
    const url = [
      'https://raw.githubusercontent.com',
      CONFIG.owner,
      CONFIG.repo,
      CONFIG.branch,
      CONFIG.filename,
    ].join('/');

    fetch(url)
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
            CONFIG.branch +
            '/' +
            CONFIG.filename +
            '">FUTURE.md su GitHub</a>.</p>';
        }
      });
  }

  fetchFromGitHub();
})();
