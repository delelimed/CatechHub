// CatechHub — Version loader from GitHub Releases
// Auto-updates version tags and download counts across the site
(function() {
  const CONFIG = {
    owner: 'delelimed',
    repo: 'CatechHub',
    fallbackVersion: 'v1.0.3',
    fallbackDownloads: 1,
  };

  const els = (sel) => document.querySelectorAll(sel);

  function updateUI(version, downloads, releaseUrl, date) {
    // Update all version badges
    els('.version-tag').forEach(el => {
      el.textContent = version;
    });
    // Update all download count badges
    els('.download-count').forEach(el => {
      el.textContent = downloads + (downloads === 1 ? ' download' : ' downloads');
    });
    // Update release URL links
    els('.release-url').forEach(el => {
      if (releaseUrl) {
        el.setAttribute('href', releaseUrl);
      }
    });
    // Update download buttons
    els('.download-btn').forEach(el => {
      if (releaseUrl) {
        el.setAttribute('href', releaseUrl);
      }
    });
    // Update version in structured data
    els('.app-version').forEach(el => {
      el.textContent = version.replace(/^v/, '');
    });
  }

  // Try fetching from GitHub API
  fetch('https://api.github.com/repos/' + CONFIG.owner + '/' + CONFIG.repo + '/releases/latest', {
    headers: { 'Accept': 'application/vnd.github.v3+json' }
  })
  .then(r => r.ok ? r.json() : Promise.reject('HTTP ' + r.status))
  .then(data => {
    const version = data.tag_name || CONFIG.fallbackVersion;
    const totalDownloads = data.assets
      ? data.assets.reduce((sum, a) => sum + (a.download_count || 0), 0)
      : CONFIG.fallbackDownloads;
    updateUI(version, totalDownloads, data.html_url, data.published_at);
  })
  .catch(() => {
    // Fallback: use embedded data
    updateUI(CONFIG.fallbackVersion, CONFIG.fallbackDownloads, null, null);
  });
})();
