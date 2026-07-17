(function () {
  const path = window.location.pathname;
  const docsIdx = path.indexOf('/docs/');
  const rel = docsIdx >= 0 ? path.slice(docsIdx + 6) : path.split('/').pop() || 'index.html';

  const depth = (rel.match(/\//g) || []).length;
  const root = depth === 0 ? './' : '../'.repeat(depth);

  function a(href, label) {
    const active = rel === href ? ' active' : '';
    return `<a href="${root}${href}" class="${active}">${label}</a>`;
  }

  function li(href, label) {
    const active = rel === href;
    return `<li${active ? ' class="active-link"' : ''}>${a(href, label)}</li>`;
  }

  const nav = `<ul>
    <li>${a('index.html', 'Home')}</li>
    <li class="dropdown">
      <a href="#">Funzionalit\u00e0 \u25be</a>
      <ul class="dropdown-menu">
        ${li('features/students.html', 'Anagrafica ragazzi')}
        ${li('features/attendance.html', 'Presenze e appello')}
        ${li('features/planning.html', 'Programmazione')}
        ${li('features/documents.html', 'Documenti')}
        ${li('features/contact-notes.html', 'Note contatto')}
        ${li('features/catechesi.html', 'Biblioteca catechetica')}
        ${li('features/data-share.html', 'Condivisione QR')}
        ${li('features/backup.html', 'Backup')}
        ${li('features/sync.html', 'Sync P2P')}
        ${li('features/allergies-exits.html', 'Allergie/Uscite')}
        ${li('features/pdf-printing.html', 'PDF/Stampa')}
      </ul>
    </li>
    <li class="dropdown">
      <a href="#">Roadmap \u25be</a>
      <ul class="dropdown-menu">
        ${li('future.html', 'Future implementazioni')}
        ${li('changelog.html', 'Cronologia versioni')}
      </ul>
    </li>
    <li class="dropdown">
      <a href="#">Documentazione \u25be</a>
      <ul class="dropdown-menu">
        ${li('technical.html', 'Tecnica')}
        ${li('developer.html', 'Sviluppatore')}
      </ul>
    </li>
    <li class="dropdown">
      <a href="#">Privacy &amp; Legal \u25be</a>
      <ul class="dropdown-menu">
        ${li('privacy.html', 'Privacy Policy')}
        ${li('terms.html', 'Termini e condizioni')}
        ${li('infos/index.html', 'GDPR')}
      </ul>
    </li>
  </ul>`;

  const target = document.getElementById('nav-container');
  if (target) target.innerHTML = nav;
})();
