(function () {
  const CONFIG = {
    owner: 'delelimed',
    repo: 'CatechHub',
  };

  const el = (sel) => document.querySelector(sel);
  const escapeHtml = (str) =>
    str
      ? str
          .replace(/&/g, '&amp;')
          .replace(/</g, '&lt;')
          .replace(/>/g, '&gt;')
          .replace(/"/g, '&quot;')
      : '';

  function formatDate(iso) {
    if (!iso) return '';
    const d = new Date(iso);
    return d.toLocaleDateString('it-IT', {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
    });
  }

  function renderReleases(releases) {
    const target = el('#changelog-list');
    if (!target || !releases.length) return;

    target.innerHTML = releases
      .map((r) => {
        const bodyHtml = r.body
          ? r.body
              .split('\n')
              .map((line) => {
                if (line.startsWith('#')) {
                  const level = line.match(/^#+/)[0].length;
                  const text = line.replace(/^#+\s*/, '');
                  return `<h${Math.min(level + 2, 6)}>${escapeHtml(text)}</h${Math.min(level + 2, 6)}>`;
                }
                if (line.startsWith('- '))
                  return `<li>${escapeHtml(line.slice(2))}</li>`;
                if (line.trim() === '') return '';
                return `<p>${escapeHtml(line)}</p>`;
              })
              .join('')
          : '';

        const assetLinks = (r.assets || [])
          .map((a) => {
            const size =
              a.size > 1024 * 1024
                ? (a.size / (1024 * 1024)).toFixed(1) + ' MB'
                : (a.size / 1024).toFixed(0) + ' KB';
            return `<a href="${escapeHtml(a.browser_download_url)}" class="btn btn-outline" style="margin:0.25rem;font-size:0.8rem;" download>📦 ${escapeHtml(a.name)} (${size})</a>`;
          })
          .join('');

        return `
          <div class="release-card">
            <div class="release-header">
              <h2><a href="${escapeHtml(r.html_url)}">${escapeHtml(r.tag_name)}</a></h2>
              <span class="release-date">${formatDate(r.published_at)}</span>
              ${r.prerelease ? '<span class="tag tag-orange">Pre-release</span>' : ''}
            </div>
            <div class="release-body">${bodyHtml || '<p>Nessuna nota di rilascio.</p>'}
            </div>
            ${assetLinks ? '<div class="release-assets">' + assetLinks + '</div>' : ''}
          </div>
        `;
      })
      .join('');
  }

  function fetchReleases() {
    const target = el('#changelog-list');
    if (!target) return;
    target.innerHTML = '<p style="text-align:center;padding:2rem;color:#888;">Caricamento versioni...</p>';

    fetch(
      'https://api.github.com/repos/' +
        CONFIG.owner +
        '/' +
        CONFIG.repo +
        '/releases?per_page=50',
      { headers: { Accept: 'application/vnd.github.v3+json' } }
    )
      .then((r) => (r.ok ? r.json() : Promise.reject('HTTP ' + r.status)))
      .then((data) => {
        if (data.length === 0) {
          target.innerHTML = '<p>Nessuna release trovata.</p>';
          return;
        }
        renderReleases(data);
      })
      .catch(() => {
        target.innerHTML =
          '<p class="alert alert-warning">Impossibile caricare le versioni. Vedi direttamente su <a href="https://github.com/' +
          CONFIG.owner +
          '/' +
          CONFIG.repo +
          '/releases">GitHub Releases</a>.</p>';
      });
  }

  fetchReleases();
})();
