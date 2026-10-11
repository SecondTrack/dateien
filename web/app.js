// PodPort — Browser-Oberfläche für den iPod-Dateiserver (App „Dateien“).
// Regel: Dateinamen und Servertexte landen IMMER per textContent im DOM, nie als HTML.
'use strict';
(function () {
  var BRAND = 'PodPort';
  var de = /^de\b/i.test(navigator.language || '');
  var S = de ? {
    sub: 'Dateien von deinem iPod', pinLabel: 'Zahl vom iPod eingeben', login: 'Verbinden',
    help: 'Auf dem iPod: App „Dateien“ öffnen und „Freigabe starten“ tippen.',
    wrongPin: 'Die Zahl stimmt nicht – schau noch mal auf den iPod.', locked: function (s) { return 'Zu viele Versuche – bitte ' + s + ' s warten.'; },
    stopped: 'Die Freigabe auf dem iPod ist beendet.', offline: 'iPod nicht erreichbar.', expired: 'Verbindung beendet – bitte neu verbinden.',
    fav: 'Favoriten', device: 'Gerät', photos: 'Fotos', music: 'Musik', downloads: 'Downloads', all: 'Alle Dateien', system: 'Systemordner',
    shell: 'Kommandozeile', logout: 'Trennen', search: 'Suchen', upload: 'Hochladen', newFolder: 'Neuer Ordner', more: 'Mehr',
    back: 'Zurück', fwd: 'Vorwärts', vIcons: 'Symbole', vList: 'Liste', vGallery: 'Galerie', sidebar: 'Seitenleiste',
    freeOf: function (f, t) { return f + ' frei von ' + t; }, avail: function (f) { return f + ' verfügbar'; },
    count: function (n) { return n === 1 ? '1 Objekt' : n + ' Objekte'; }, selected: function (n) { return n + ' ausgewählt'; },
    name: 'Name', date: 'Änderungsdatum', size: 'Größe', kind: 'Art',
    kinds: { folder: 'Ordner', image: 'Bild', video: 'Video', audio: 'Audio', archive: 'Archiv', text: 'Text', pdf: 'PDF-Dokument',
             code: 'Code', app: 'Programm', book: 'Buch', other: 'Dokument' },
    empty: 'Dieser Ordner ist leer.', emptyPhotos: 'Noch keine Fotos in der Kamerarolle.', emptyMusic: 'Keine Musikdateien gefunden.',
    noMatch: 'Nichts gefunden.', searching: 'Suche läuft …', searchIn: function (q, w) { return 'Suche nach „' + q + '“ in ' + w; },
    moreResults: 'Es gibt noch mehr Treffer – genauer suchen.', dropHint: 'Dateien hierher ziehen oder',
    open: 'Öffnen', download: 'Herunterladen', toRoll: 'Zur Kamerarolle hinzufügen', rename: 'Umbenennen', del: 'Löschen',
    showHidden: 'Versteckte Dateien zeigen', rollOpt: 'Bilder & Videos auch in der Kamerarolle sichern', selectAll: 'Alle auswählen',
    view: 'Darstellung', cancel: 'Abbrechen', ok: 'OK', create: 'Erstellen', replace: 'Ersetzen', skip: 'Überspringen',
    renameTitle: 'Umbenennen', newFolderTitle: 'Neuer Ordner', untitled: 'Neuer Ordner',
    delTitle: function (n) { return n === 1 ? 'Wirklich löschen?' : n + ' Objekte löschen?'; },
    delText: function (names, dir) { return (dir ? 'Ordner werden mit ihrem gesamten Inhalt gelöscht. ' : '') + names + ' – das lässt sich nicht rückgängig machen.'; },
    exists: function (n) { return '„' + n + '“ gibt es hier schon.'; }, existsText: 'Soll die vorhandene Datei ersetzt werden?',
    uploads: function (a, b) { return a < b ? 'Lade hoch … ' + a + ' von ' + b : (b === 1 ? '1 Datei hochgeladen' : b + ' Dateien hochgeladen'); },
    waiting: 'wartet', done: 'fertig', skipped: 'übersprungen', inRoll: 'in der Kamerarolle ✓', plusRoll: ' + Kamerarolle ✓',
    rollFail: function (e) { return ' · Kamerarolle: ' + e; }, importing: 'wird in die Kamerarolle eingetragen …',
    dropTo: function (w) { return 'Loslassen, um nach „' + w + '“ hochzuladen'; }, dropRoll: 'Loslassen, um in die Kamerarolle zu laden',
    skippedDirs: 'Ordner können nicht hochgeladen werden – nur Dateien.',
    deleted: function (n) { return n === 1 ? 'Gelöscht.' : n + ' Objekte gelöscht.'; }, renamed: 'Umbenannt.', created: 'Ordner erstellt.',
    added: 'In die Kamerarolle eingetragen – jetzt in der Fotos-App.', of: function (a, b) { return a + ' von ' + b; },
    notePhotos: 'Das ist die Kamerarolle des iPods. Hochgeladene Bilder und Videos landen direkt in der Fotos-App.',
    noteMusic: 'Alle Musik- und Audiodateien auf dem iPod. Zum Hochladen einen Ordner wählen, z. B. Downloads.',
    shellPassTitle: 'Kommandozeile', shellPassText: 'Gib das Passwort ein, das auf dem iPod unter „Extras“ steht.',
    shellClose: 'Schließen', shellClear: 'Leeren', shellEnded: '[Sitzung beendet]', shellGone: '[Verbindung zur Kommandozeile beendet]',
    shellOpened: '[angemeldet als mobile – ^C bricht ab, „exit“ beendet]',
    apps: 'Apps', install: 'Installieren', uninstall: 'Deinstallieren', info: 'Informationen', mine: 'Installierte Apps', sysApps: 'System-Apps',
    src: { deb: 'Paket', ipa: 'IPA', own: 'Eigene', system: 'System' }, version: 'Version', size2: 'Größe', bundle: 'Kennung', pkg: 'Paket',
    noteApps: 'Ziehe .deb- oder .ipa-Dateien hierher, um Apps zu installieren. Jede Installation bestätigst du am iPod.',
    emptyApps: 'Keine Apps gefunden.', confirmOnIpod: 'Bitte am iPod bestätigen …', installed: 'installiert ✓',
    installedT: function (n) { return n + ' ist installiert – jetzt auf dem Home-Bildschirm.'; }, removed: function (n) { return n + ' wurde entfernt.'; },
    dropInstall: 'Loslassen, um zu installieren', converting: 'wird in JPG umgewandelt …',
    savedDl: 'in Downloads gespeichert – dieses Format kann der iPod nicht in Fotos zeigen', showLog: 'Protokoll', sysNote: 'System-App – kann nicht entfernt werden.',
    err: {
      declined: 'Am iPod abgelehnt (oder nicht innerhalb von 2 Minuten bestätigt).', pkgtype: 'Nur .deb- oder .ipa-Dateien lassen sich installieren.',
      pkgbusy: 'Es läuft schon eine Installation.', notdeb: 'Das ist kein gültiges .deb-Paket.', notipa: 'Das ist keine gültige .ipa-Datei.',
      pkg_dpkg: 'Installation fehlgeschlagen – siehe Protokoll (oft fehlende Abhängigkeiten).', pkg_arch: 'Paket ist nicht für den iPod (Architektur).',
      pkg_exists: 'Eine andere App mit diesem Namen ist schon installiert.', pkg_space: 'Nicht genug Platz auf dem Systemlaufwerk.',
      pkg_changed: 'Die Datei hat sich nach der Bestätigung geändert – abgebrochen.', pkg_notipa: 'Das ist keine gültige .ipa-Datei.',
      pkg_notdeb: 'Das ist kein gültiges .deb-Paket.', pkg_protected: 'Diese App ist geschützt.', pkg_notfound: 'Nicht gefunden.',
      pkg_io: 'Schreibfehler auf dem iPod.', pkg_caller: 'Der Installations-Helfer hat den Aufruf abgelehnt.', pkg_helper: 'Installations-Helfer fehlt.',
      pkg_root: 'Keine root-Rechte für den Installations-Helfer.',
      badname: 'Dieser Name geht nicht.', exists: 'Es gibt schon etwas mit diesem Namen.', isdir: 'Dort liegt ein Ordner mit diesem Namen.',
      space: 'Nicht genug Speicher auf dem iPod.', denied: 'Keine Berechtigung.', notfound: 'Nicht gefunden.',
      protected: 'Systemordner – geschützt.', aborted: 'Übertragung abgebrochen.', io: 'Schreibfehler auf dem iPod.',
      busy: 'Der iPod ist gerade ausgelastet.', network: 'Verbindung unterbrochen.', noimage: 'Keine Vorschau möglich.',
      format: 'Dieses Format kann der iPod nicht in die Kamerarolle übernehmen (JPG, PNG, GIF, H.264-Video).',
      photosdenied: 'Zugriff auf Fotos verweigert – am iPod unter Einstellungen › Datenschutz › Fotos erlauben.',
      photosfail: 'Eintragen in die Kamerarolle fehlgeschlagen.', shelloff: 'Die Kommandozeile ist aus. Am iPod unter „Extras“ einschalten.',
      shellpass: 'Falsches Passwort.', shelllocked: 'Zu viele falsche Passwörter – die Kommandozeile wurde am iPod ausgeschaltet.',
      shellfail: 'Kommandozeile konnte nicht starten.', shellgone: 'Die Sitzung ist abgelaufen.'
    }
  } : {
    sub: 'Files from your iPod', pinLabel: 'Enter the number shown on the iPod', login: 'Connect',
    help: 'On the iPod: open the “Files” app and tap “Start sharing”.',
    wrongPin: 'That number is wrong – check the iPod again.', locked: function (s) { return 'Too many attempts – please wait ' + s + ' s.'; },
    stopped: 'Sharing on the iPod has ended.', offline: 'Cannot reach the iPod.', expired: 'Disconnected – please connect again.',
    fav: 'Favourites', device: 'Device', photos: 'Photos', music: 'Music', downloads: 'Downloads', all: 'All Files', system: 'System folders',
    shell: 'Command line', logout: 'Disconnect', search: 'Search', upload: 'Upload', newFolder: 'New Folder', more: 'More',
    back: 'Back', fwd: 'Forward', vIcons: 'Icons', vList: 'List', vGallery: 'Gallery', sidebar: 'Sidebar',
    freeOf: function (f, t) { return f + ' free of ' + t; }, avail: function (f) { return f + ' available'; },
    count: function (n) { return n === 1 ? '1 item' : n + ' items'; }, selected: function (n) { return n + ' selected'; },
    name: 'Name', date: 'Date Modified', size: 'Size', kind: 'Kind',
    kinds: { folder: 'Folder', image: 'Image', video: 'Video', audio: 'Audio', archive: 'Archive', text: 'Text', pdf: 'PDF document',
             code: 'Code', app: 'Application', book: 'Book', other: 'Document' },
    empty: 'This folder is empty.', emptyPhotos: 'No photos in the Camera Roll yet.', emptyMusic: 'No music files found.',
    noMatch: 'Nothing found.', searching: 'Searching …', searchIn: function (q, w) { return 'Searching for “' + q + '” in ' + w; },
    moreResults: 'There are more matches – search more precisely.', dropHint: 'Drag files here or',
    open: 'Open', download: 'Download', toRoll: 'Add to Camera Roll', rename: 'Rename', del: 'Delete',
    showHidden: 'Show hidden files', rollOpt: 'Also save photos & videos to the Camera Roll', selectAll: 'Select all',
    view: 'View', cancel: 'Cancel', ok: 'OK', create: 'Create', replace: 'Replace', skip: 'Skip',
    renameTitle: 'Rename', newFolderTitle: 'New Folder', untitled: 'New Folder',
    delTitle: function (n) { return n === 1 ? 'Really delete?' : 'Delete ' + n + ' items?'; },
    delText: function (names, dir) { return (dir ? 'Folders are deleted with everything inside. ' : '') + names + ' – this cannot be undone.'; },
    exists: function (n) { return '“' + n + '” already exists here.'; }, existsText: 'Replace the existing file?',
    uploads: function (a, b) { return a < b ? 'Uploading … ' + a + ' of ' + b : (b === 1 ? '1 file uploaded' : b + ' files uploaded'); },
    waiting: 'waiting', done: 'done', skipped: 'skipped', inRoll: 'in Camera Roll ✓', plusRoll: ' + Camera Roll ✓',
    rollFail: function (e) { return ' · Camera Roll: ' + e; }, importing: 'adding to Camera Roll …',
    dropTo: function (w) { return 'Drop to upload to “' + w + '”'; }, dropRoll: 'Drop to add to the Camera Roll',
    skippedDirs: 'Folders cannot be uploaded – files only.',
    deleted: function (n) { return n === 1 ? 'Deleted.' : n + ' items deleted.'; }, renamed: 'Renamed.', created: 'Folder created.',
    added: 'Added to the Camera Roll – now in the Photos app.', of: function (a, b) { return a + ' of ' + b; },
    notePhotos: 'This is the iPod’s Camera Roll. Photos and videos you upload go straight into the Photos app.',
    noteMusic: 'All music and audio files on the iPod. To upload, pick a folder such as Downloads.',
    shellPassTitle: 'Command line', shellPassText: 'Enter the password shown on the iPod under “Extras”.',
    shellClose: 'Close', shellClear: 'Clear', shellEnded: '[session ended]', shellGone: '[connection to the command line ended]',
    shellOpened: '[signed in as mobile – ^C interrupts, “exit” ends]',
    apps: 'Apps', install: 'Install', uninstall: 'Uninstall', info: 'Info', mine: 'Installed apps', sysApps: 'System apps',
    src: { deb: 'Package', ipa: 'IPA', own: 'Manual', system: 'System' }, version: 'Version', size2: 'Size', bundle: 'Identifier', pkg: 'Package',
    noteApps: 'Drop .deb or .ipa files here to install apps. You confirm every installation on the iPod.',
    emptyApps: 'No apps found.', confirmOnIpod: 'Please confirm on the iPod …', installed: 'installed ✓',
    installedT: function (n) { return n + ' is installed – now on the home screen.'; }, removed: function (n) { return n + ' was removed.'; },
    dropInstall: 'Drop to install', converting: 'converting to JPG …',
    savedDl: 'saved to Downloads – the iPod cannot show this format in Photos', showLog: 'Log', sysNote: 'System app – cannot be removed.',
    err: {
      declined: 'Declined on the iPod (or not confirmed within 2 minutes).', pkgtype: 'Only .deb or .ipa files can be installed.',
      pkgbusy: 'An installation is already running.', notdeb: 'This is not a valid .deb package.', notipa: 'This is not a valid .ipa file.',
      pkg_dpkg: 'Installation failed – see the log (often missing dependencies).', pkg_arch: 'This package is not for the iPod (architecture).',
      pkg_exists: 'Another app with this name is already installed.', pkg_space: 'Not enough space on the system drive.',
      pkg_changed: 'The file changed after confirming – aborted.', pkg_notipa: 'This is not a valid .ipa file.',
      pkg_notdeb: 'This is not a valid .deb package.', pkg_protected: 'This app is protected.', pkg_notfound: 'Not found.',
      pkg_io: 'Write error on the iPod.', pkg_caller: 'The install helper refused the call.', pkg_helper: 'Install helper is missing.',
      pkg_root: 'The install helper has no root rights.',
      badname: 'That name does not work.', exists: 'Something with this name already exists.', isdir: 'A folder with this name is in the way.',
      space: 'Not enough space on the iPod.', denied: 'Permission denied.', notfound: 'Not found.',
      protected: 'System folder – protected.', aborted: 'Transfer aborted.', io: 'Write error on the iPod.',
      busy: 'The iPod is busy right now.', network: 'Connection lost.', noimage: 'No preview available.',
      format: 'The iPod cannot add this format to the Camera Roll (JPG, PNG, GIF, H.264 video).',
      photosdenied: 'Photo access denied – allow it on the iPod under Settings › Privacy › Photos.',
      photosfail: 'Adding to the Camera Roll failed.', shelloff: 'The command line is off. Switch it on on the iPod under “Extras”.',
      shellpass: 'Wrong password.', shelllocked: 'Too many wrong passwords – the command line was switched off on the iPod.',
      shellfail: 'The command line could not start.', shellgone: 'The session has expired.'
    }
  };
  document.documentElement.lang = de ? 'de' : 'en';

  var MEDIA_DIR = 'var/mobile/Media', DL_DIR = 'var/mobile/Media/Downloads';
  var NS = 'http://www.w3.org/2000/svg';
  var $ = function (id) { return document.getElementById(id); };
  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }
  function svg(id, cls) {
    var s = document.createElementNS(NS, 'svg'); s.setAttribute('class', cls || 'i');
    var u = document.createElementNS(NS, 'use'); u.setAttribute('href', '#' + id);
    s.appendChild(u); return s;
  }
  function store(kind, key, val) {               // Speicher kann im Privatmodus fehlen
    try { if (val === undefined) return window[kind].getItem(key); if (val === null) window[kind].removeItem(key); else window[kind].setItem(key, val); }
    catch (e) { return null; }
  }
  function qs(o) { return Object.keys(o).map(function (k) { return encodeURIComponent(k) + '=' + encodeURIComponent(o[k]); }).join('&'); }
  function fmtSize(n) {
    if (n < 1000) return n + ' B';
    var u = ['KB', 'MB', 'GB', 'TB'], i = -1;
    do { n /= 1000; i++; } while (n >= 1000 && i < u.length - 1);   // wie der Finder: 1000er-Schritte
    return n.toLocaleString(undefined, { maximumFractionDigits: n < 10 ? 1 : 0 }) + ' ' + u[i];
  }
  function fmtDate(sec) {
    var d = new Date(sec * 1000), now = new Date();
    var t = d.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' });
    if (d.toDateString() === now.toDateString()) return (de ? 'Heute, ' : 'Today, ') + t;
    var y = new Date(now); y.setDate(now.getDate() - 1);
    if (d.toDateString() === y.toDateString()) return (de ? 'Gestern, ' : 'Yesterday, ') + t;
    return d.toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' }) + ', ' + t;
  }
  function join(a, b) { return a ? a + '/' + b : b; }
  function parentOf(p) { var i = p.lastIndexOf('/'); return i < 0 ? '' : p.slice(0, i); }
  function baseName(p) { return p.slice(p.lastIndexOf('/') + 1); }
  function inDCIM(p) { return /^(private\/)?var\/mobile\/Media\/DCIM(\/|$)/.test(p || ''); }
  function norm(p) { return (p || '').replace(/^private\//, ''); }
  function validName(n) { return !!n && n !== '.' && n !== '..' && !/[\/:\u0000-\u001f\u007f]/.test(n) && new Blob([n]).size <= 255; }
  function ext(n) { var i = n.lastIndexOf('.'); return i > 0 ? n.slice(i + 1).toLowerCase() : ''; }
  var KIND = {
    image: /^(jpe?g|png|gif|heic|bmp|tiff?|webp)$/, video: /^(mp4|m4v|mov|avi|mkv|3gp)$/, audio: /^(mp3|m4a|m4b|m4p|m4r|aac|wav|aiff?|caf|flac|ogg|opus)$/,
    archive: /^(zip|gz|tgz|bz2|xz|7z|rar|tar)$/, text: /^(txt|md|log|csv|rtf|strings)$/, pdf: /^pdf$/,
    code: /^(plist|json|xml|sh|js|html?|css|c|h|m|py|conf|ini|cfg|db|sqlite|sqlitedb)$/, app: /^(deb|ipa|app|dylib)$/, book: /^(epub|ibooks|mobi)$/
  };
  function kindOf(it) {
    if (it.a) return 'app';
    if (it.d) return 'folder';
    var e = ext(it.n);
    for (var k in KIND) if (KIND[k].test(e)) return k;
    return 'other';
  }
  var THUMB = /\.(jpe?g|png|gif|bmp|tiff?|mov|mp4|m4v|3gp)$/i;
  var VIEWABLE = /\.(jpe?g|png|gif|bmp|tiff?|mov|mp4|m4v)$/i;
  var ROLLABLE = /\.(jpe?g|png|gif|bmp|tiff?|mov|mp4|m4v)$/i;
  var CONVERTIBLE = /\.(heic|heif|webp|avif)$/i;
  var KCOLOR = { image: '#34c759', video: '#af52de', audio: '#ff2d55', archive: '#a2845e', text: '#8e8e93', pdf: '#ff3b30',
                 code: '#5856d6', app: '#30b0c7', book: '#ff9500', other: '#8e8e93' };

  // ---------- Zustand ----------
  var token = store('sessionStorage', 'fm.t') || '';
  var info = null, loc = null, items = [], loadSeq = 0, loadDim = null;
  var sel = new Set(), anchor = null, query = '', found = null, findMore = false, findSeq = 0, findTimer = null;
  var showHidden = store('localStorage', 'fm.h') === '1';
  var rollOpt = store('localStorage', 'fm.r') === '1';
  var views = { dir: store('localStorage', 'fm.v.dir') || 'icons', photos: store('localStorage', 'fm.v.photos') || 'gallery',
                music: store('localStorage', 'fm.v.music') || 'list', apps: store('localStorage', 'fm.v.apps') || 'icons' };
  var sorts = { dir: { k: 'name', d: 1 }, photos: { k: 'date', d: -1 }, music: { k: 'name', d: 1 }, apps: { k: 'name', d: 1 } };
  var navDepth = 0, fwdDepth = 0, lastPointer = 'mouse';
  var coarse = window.matchMedia && matchMedia('(pointer: coarse)').matches;

  // QR-Code bringt die PIN mit (#pin=1234) – sofort aus der Adresse entfernen
  var qrPin = (location.hash.match(/^#pin=(\d{4})$/) || [])[1];
  if (qrPin) history.replaceState(null, '', location.pathname);

  // ---------- statische Texte ----------
  document.title = BRAND;
  document.querySelectorAll('.bn').forEach(function (e) { e.textContent = BRAND; });
  $('lSub').textContent = S.sub; $('lPin').textContent = S.pinLabel; $('loginBtn').textContent = S.login; $('lHelp').textContent = S.help;
  $('secFav').textContent = S.fav; $('secDev').textContent = S.device;
  $('logout').querySelector('span').textContent = S.logout;
  $('q').placeholder = S.search;
  $('btnUp').querySelector('span').textContent = S.upload;
  [['menuBtn', S.sidebar], ['back', S.back], ['fwd', S.fwd], ['btnNew', S.newFolder], ['btnMore', S.more], ['btnUp', S.upload]]
    .forEach(function (x) { $(x[0]).title = x[1]; $(x[0]).setAttribute('aria-label', x[1]); });
  document.querySelectorAll('#views button').forEach(function (b) {
    var t = { icons: S.vIcons, list: S.vList, gallery: S.vGallery }[b.dataset.v];
    b.title = t; b.setAttribute('aria-label', t);
  });
  $('upRoll').checked = rollOpt; $('uploads').querySelector('.opt span').textContent = S.rollOpt;
  $('shClose').textContent = S.shellClose; $('shClear').textContent = S.shellClear;
  $('vDown').title = S.download; $('vRoll').title = S.toRoll;

  // ---------- Toast ----------
  var toastTimer;
  function toast(msg, ms) {
    var t = $('toast');
    t.textContent = msg; t.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { t.hidden = true; }, ms || 4200);
  }
  function errText(code, status) { return S.err[code] || ('HTTP ' + status); }

  // ---------- API (Token nur im Header) ----------
  function api(method, path, params, opt) {
    opt = opt || {};
    var headers = Object.assign({ 'X-FM-Token': token }, opt.headers || {});
    return fetch(path + (params ? '?' + qs(params) : ''), { method: method, headers: headers, body: opt.body, cache: 'no-store' })
      .catch(function () { var e = new Error(S.offline); e.net = true; throw e; })
      .then(function (r) {
        if (r.ok && opt.raw) return r;
        if (r.ok && opt.blob) return r.blob();
        return r.json().catch(function () { return {}; }).then(function (j) {
          if (r.status === 401) { signOut(S.expired); var e = new Error(S.expired); e.auth = true; throw e; }
          if (!r.ok) { var x = new Error(errText(j.error, r.status)); x.code = j.error; x.status = r.status; throw x; }
          return j;
        });
      });
  }
  function fail(e) { if (!e.auth) toast(e.message); }

  // ---------- Anmeldung ----------
  function showLogin(msg) {
    ['app', 'viewer', 'shell'].forEach(function (id) { $(id).hidden = true; });
    closeMenu(); $('login').hidden = false;
    $('loginErr').textContent = msg || '';
    $('pin').value = '';
    if (!coarse) $('pin').focus();
  }
  function signOut(msg) {
    token = ''; store('sessionStorage', 'fm.t', null);
    clearThumbs(); stopPlayer(); shellReset();
    clearInterval(infoTimer);
    showLogin(msg);
  }
  var loggingIn = false;
  function login(pin) {
    if (!/^\d{4}$/.test(pin) || loggingIn) return;
    loggingIn = true; $('loginBtn').disabled = true; $('loginErr').textContent = '';
    fetch('/api/login', { method: 'POST', headers: { 'X-FM-Pin': pin }, cache: 'no-store' })
      .then(function (r) { return r.json().catch(function () { return {}; }).then(function (j) { return { r: r, j: j }; }); })
      .then(function (x) {
        if (x.r.ok && x.j.token) {
          token = x.j.token; store('sessionStorage', 'fm.t', token);
          $('login').hidden = true; $('app').hidden = false;
          start();
        } else showLogin(x.r.status === 429 ? S.locked(x.j.wait || 30) : x.r.status === 503 ? S.stopped : S.wrongPin);
      })
      .catch(function () { showLogin(S.offline); })
      .then(function () { loggingIn = false; $('loginBtn').disabled = false; });
  }
  $('loginForm').addEventListener('submit', function (ev) { ev.preventDefault(); login($('pin').value.trim()); });
  $('pin').addEventListener('input', function () {
    this.value = this.value.replace(/\D/g, '').slice(0, 4);
    if (this.value.length === 4) login(this.value);
  });
  $('logout').addEventListener('click', function () { api('POST', '/api/logout').catch(function () {}); signOut(''); });

  // ---------- Geräteinfo (Seitenleiste) ----------
  var infoTimer;
  function loadInfo() {
    return api('GET', '/api/info').then(function (j) {
      info = j;
      $('devName').textContent = j.name;
      var used = j.total ? (j.total - j.free) / j.total : 0;
      $('devMeter').firstChild.style.width = (used * 100).toFixed(1) + '%';
      $('devMeter').classList.toggle('low', j.total && j.free / j.total < 0.08);
      $('devFree').textContent = S.freeOf(fmtSize(j.free), fmtSize(j.total));
      renderSide(); renderStatus();
    }, function () {});
  }

  // ---------- Orte ----------
  var FAVS = [
    { id: 'photos', icon: 'i-photos', label: function () { return S.photos; }, loc: { k: 'photos' } },
    { id: 'music', icon: 'i-music', label: function () { return S.music; }, loc: { k: 'music' } },
    { id: 'downloads', icon: 'i-down', label: function () { return S.downloads; }, loc: { k: 'dir', p: DL_DIR } },
    { id: 'all', icon: 'i-all', label: function () { return S.all; }, loc: { k: 'dir', p: MEDIA_DIR } }
  ];
  function locHash(l) { return l.k === 'dir' ? '#/' + l.p.split('/').filter(Boolean).map(encodeURIComponent).join('/') : '#' + l.k; }
  function locFromHash() {
    var h = location.hash;
    if (h === '#photos' || h === '#music' || h === '#apps') return { k: h.slice(1) };
    if (!/^#\//.test(h)) return null;
    try { return { k: 'dir', p: h.slice(2).split('/').filter(Boolean).map(decodeURIComponent).join('/') }; }
    catch (e) { return { k: 'dir', p: MEDIA_DIR }; }
  }
  function sameLoc(a, b) { return a && b && a.k === b.k && (a.k !== 'dir' || a.p === b.p); }
  function activeFav() {
    if (!loc) return null;
    if (loc.k !== 'dir') return loc.k;
    var p = norm(loc.p);
    if (p === DL_DIR || p.indexOf(DL_DIR + '/') === 0) return 'downloads';
    if (p === MEDIA_DIR || p.indexOf(MEDIA_DIR + '/') === 0) return 'all';
    return 'system';
  }
  function renderSide() {
    var on = activeFav(), f = document.createDocumentFragment();
    FAVS.forEach(function (fv) { f.appendChild(sideItem(fv.icon, fv.label(), on === fv.id, function () { go(fv.loc); })); });
    $('favs').replaceChildren(f);
    var d = document.createDocumentFragment();
    d.appendChild(sideItem('i-apps', S.apps, on === 'apps', function () { go({ k: 'apps' }); }));
    d.appendChild(sideItem('i-gear', S.system, on === 'system', function () { go({ k: 'dir', p: '' }); }));
    if (info && info.shell) { var s = sideItem('i-term', S.shell, !$('shell').hidden, openShell); s.classList.add('shell'); d.appendChild(s); }
    $('devNav').replaceChildren(d);
  }
  function sideItem(icon, label, on, fn) {
    var b = el('button', 'si' + (on ? ' on' : ''));
    b.appendChild(svg(icon)); b.appendChild(el('span', null, label));
    b.onclick = function () { closeDrawer(); fn(); };
    return b;
  }
  $('menuBtn').onclick = function () { $('app').classList.toggle('drawer'); };
  $('scrim').onclick = closeDrawer;
  function closeDrawer() { $('app').classList.remove('drawer'); }

  // ---------- Navigation ----------
  function go(l) {
    if (sameLoc(l, loc)) { load(l, true); return; }
    navDepth++; fwdDepth = 0;
    location.hash = locHash(l);
  }
  window.addEventListener('hashchange', function () {
    var l = locFromHash();
    if (token && l && !sameLoc(l, loc)) load(l);
  });
  $('back').onclick = function () { if (navDepth > 0) { navDepth--; fwdDepth++; history.back(); } };
  $('fwd').onclick = function () { if (fwdDepth > 0) { fwdDepth--; navDepth++; history.forward(); } };

  function load(l, keep) {
    var seq = ++loadSeq;
    // nur dimmen, wenn das Laden spürbar dauert – sonst blitzt jeder Ordnerwechsel kurz auf
    clearTimeout(loadDim);
    loadDim = setTimeout(function () { if (seq === loadSeq) $('content').classList.add('loading'); }, 300);
    var req = l.k === 'dir' ? api('GET', '/api/ls', { p: l.p }) : l.k === 'apps' ? api('GET', '/api/apps') : api('GET', '/api/collect', { k: l.k });
    return req.then(function (j) {
      if (seq !== loadSeq) return;
      var changed = !sameLoc(l, loc);
      loc = l;
      items = (j.items || []).map(function (it) {
        if (it.a) { it.p = 'app:' + it.a; it.d = false; } else if (!it.p) it.p = join(l.p, it.n);
        return it;
      });
      if (changed) { sel.clear(); anchor = null; query = ''; $('q').value = ''; found = null; }
      else if (query && found && loc.k === 'dir') runFind();
      clearTimeout(loadDim); $('content').classList.remove('loading');
      if (changed && !keep) $('content').scrollTop = 0;
      render();
    }, function (e) {
      if (seq !== loadSeq) return;
      clearTimeout(loadDim); $('content').classList.remove('loading');
      if (e.auth) return;
      toast(e.message);
      if (!loc) go({ k: 'dir', p: MEDIA_DIR });
      else if (!sameLoc(l, loc)) history.replaceState(null, '', locHash(loc));
    });
  }
  function reload() { if (loc) load(loc, true); }

  // ---------- Sortieren, Filtern ----------
  function kindKey() { return loc ? loc.k : 'dir'; }
  function curView() { return views[kindKey()]; }
  function shown() {
    var src = found || items, q = query.toLowerCase();
    var list = src.filter(function (it) {
      if (!showHidden && it.n.charAt(0) === '.') return false;
      return !q || found || it.n.toLowerCase().indexOf(q) >= 0;
    });
    var s = sorts[kindKey()], cmpName = function (a, b) { return a.n.localeCompare(b.n, undefined, { numeric: true, sensitivity: 'base' }); };
    list.sort(function (a, b) {
      var r = 0;
      if (s.k === 'name') return (b.d - a.d) || cmpName(a, b) * s.d;
      if (s.k === 'date') r = a.m - b.m;
      else if (s.k === 'size') r = (a.d ? -1 : a.s) - (b.d ? -1 : b.s);
      else if (s.k === 'kind') r = S.kinds[kindOf(a)].localeCompare(S.kinds[kindOf(b)]);
      return r * s.d || cmpName(a, b);
    });
    return list;
  }
  function writable(it) { return loc && loc.k === 'dir' && !inDCIM(it.p); }

  // ---------- Darstellung ----------
  function render() {
    renderSide(); renderBar(); renderNote();
    resetThumbs();
    var list = shown(), v = curView(), box = $('content'), f;
    if (!list.length) f = emptyView();
    else if (loc.k === 'apps') f = v === 'list' ? listView(list) : appsView(list);
    else if (v === 'list') f = listView(list);
    else if (v === 'gallery') f = galleryView(list);
    else f = iconView(list);
    box.replaceChildren(f);
    renderStatus();
  }

  function locTitle() {
    if (!loc) return '';
    if (loc.k === 'photos') return S.photos;
    if (loc.k === 'music') return S.music;
    if (loc.k === 'apps') return S.apps;
    var p = norm(loc.p);
    if (p === MEDIA_DIR) return S.all;
    if (p === DL_DIR) return S.downloads;
    if (!p) return info ? info.name : 'iPod';
    return baseName(p);
  }
  function crumbs() {
    if (loc.k !== 'dir') return [{ label: locTitle(), loc: loc }];
    var p = norm(loc.p), base, rest;
    if (p === DL_DIR || p.indexOf(DL_DIR + '/') === 0) { base = { label: S.downloads, p: DL_DIR }; rest = p.slice(DL_DIR.length); }
    else if (p === MEDIA_DIR || p.indexOf(MEDIA_DIR + '/') === 0) { base = { label: S.all, p: MEDIA_DIR }; rest = p.slice(MEDIA_DIR.length); }
    else { base = { label: info ? info.name : 'iPod', p: '' }; rest = '/' + loc.p; }
    var out = [{ label: base.label, loc: { k: 'dir', p: base.p } }], acc = base.p;
    rest.split('/').filter(Boolean).forEach(function (n) { acc = join(acc, n); out.push({ label: n, loc: { k: 'dir', p: acc } }); });
    return out;
  }
  function renderBar() {
    var c = document.createDocumentFragment(), cr = crumbs();
    cr.forEach(function (x, i) {
      if (i) c.appendChild(svg('i-chev', 'i sep'));
      if (i === cr.length - 1) { var s = el('span', 'cur', x.label); s.title = x.label; c.appendChild(s); }
      else { var b = el('button', null, x.label); b.title = x.label; b.onclick = function () { go(x.loc); }; c.appendChild(b); }
    });
    $('crumbs').replaceChildren(c);
    var v = curView();
    document.querySelectorAll('#views button').forEach(function (b) { b.classList.toggle('on', b.dataset.v === v); });
    $('back').disabled = navDepth <= 0; $('fwd').disabled = fwdDepth <= 0;
    $('btnUp').disabled = loc.k === 'music';
    $('btnUp').querySelector('span').textContent = loc.k === 'apps' ? S.install : S.upload;
    $('fab').querySelector('span').textContent = loc.k === 'apps' ? S.install : S.upload;
    $('fab').hidden = loc.k === 'music' || !$('uploads').hidden;
    $('views').querySelector('[data-v=gallery]').hidden = loc.k === 'apps';
    $('btnNew').hidden = loc.k !== 'dir' || inDCIM(loc.p);
  }
  function renderNote(extra) {
    var t = extra || (loc.k === 'photos' ? S.notePhotos : loc.k === 'music' ? S.noteMusic : loc.k === 'apps' ? S.noteApps : '');
    $('note').hidden = !t;
    $('note').querySelector('span').textContent = t;
  }
  function renderStatus() {
    if (!loc) return;
    var n = shown().length, parts = [S.count(n)];
    if (sel.size) parts.push(S.selected(sel.size));
    if (info) parts.push(S.avail(fmtSize(info.free)));
    $('status').textContent = parts.join(' · ');
  }
  function emptyView() {
    var d = el('div', 'empty');
    if (found || query) { d.appendChild(svg('i-search')); d.appendChild(el('div', null, findBusy ? S.searching : S.noMatch)); return d; }
    var fi = document.createElementNS(NS, 'svg'); fi.setAttribute('viewBox', '0 0 64 64');
    var u = document.createElementNS(NS, 'use'); u.setAttribute('href', loc.k === 'photos' ? '#k-image' : loc.k === 'music' ? '#k-audio' : '#f-folder');
    fi.appendChild(u); d.appendChild(fi);
    d.appendChild(el('div', null, loc.k === 'photos' ? S.emptyPhotos : loc.k === 'music' ? S.emptyMusic : loc.k === 'apps' ? S.emptyApps : S.empty));
    if (loc.k !== 'music') {
      d.appendChild(el('div', null, S.dropHint));
      var b = el('button', 'btn primary'); b.appendChild(svg('i-up')); b.appendChild(el('span', null, S.upload));
      b.onclick = pickFiles; d.appendChild(b);
    }
    return d;
  }

  // Datei-Symbol (farbig), bei Bildern/Videos echtes Vorschaubild
  function iconFor(it, thumbSize) {
    var box = el('div', 'icon'), k = kindOf(it);
    if (it.a) {                                             // App: echtes Icon vom iPod
      box.appendChild(el('div', 'appic'));
      wantThumb(box, it, 0);
      return box;
    }
    var s = document.createElementNS(NS, 'svg'); s.setAttribute('class', 'fi'); s.setAttribute('viewBox', '0 0 64 64');
    var add = function (id) { var u = document.createElementNS(NS, 'use'); u.setAttribute('href', '#' + id); s.appendChild(u); };
    if (k === 'folder') add('f-folder');
    else {
      add('f-doc'); add('k-' + k);
      var e = ext(it.n).slice(0, 4).toUpperCase();
      if (e && k !== 'pdf') {
        var t = document.createElementNS(NS, 'text');
        t.setAttribute('x', '32'); t.setAttribute('y', '54'); t.setAttribute('text-anchor', 'middle'); t.setAttribute('font-size', '7.5');
        t.setAttribute('font-weight', '700'); t.setAttribute('font-family', '-apple-system,Helvetica,Arial'); t.setAttribute('fill', KCOLOR[k]);
        t.textContent = e; s.appendChild(t);
      }
    }
    box.appendChild(s);
    if (thumbSize && !it.d && THUMB.test(it.n)) wantThumb(box, it, thumbSize);
    return box;
  }
  function itemTitle(it) { return it.n + (found ? ' — ' + parentOf(it.p) : ''); }

  function iconView(list) {
    var g = el('div', 'v-icons');
    list.forEach(function (it) {
      var d = el('div', 'it' + (sel.has(it.p) ? ' sel' : ''));
      d._it = it; d.title = itemTitle(it);
      d.appendChild(iconFor(it, 160));
      d.appendChild(el('div', 'nm', it.n));
      if (found) d.appendChild(el('div', 'mt', baseName(parentOf(it.p)) || '/'));
      g.appendChild(d);
    });
    return g;
  }
  function appsView(list) {
    var g = el('div', 'v-apps');
    var groups = [[S.mine, list.filter(function (i) { return i.src !== 'system'; })], [S.sysApps, list.filter(function (i) { return i.src === 'system'; })]];
    groups.forEach(function (gr) {
      if (!gr[1].length) return;
      g.appendChild(el('div', 'day', gr[0]));
      gr[1].forEach(function (it) {
        var d = el('div', 'app' + (sel.has(it.p) ? ' sel' : ''));
        d._it = it; d.title = it.n + (it.v ? ' ' + it.v : '');
        d.appendChild(iconFor(it));
        d.appendChild(el('div', 'nm', it.n));
        d.appendChild(el('div', 'mt', it.v ? it.v : ''));
        g.appendChild(d);
      });
    });
    return g;
  }
  function listView(list) {
    var wrap = el('div', 'v-list'), s = sorts[kindKey()];
    var h = el('div', 'lh');
    [['name', S.name], ['date', S.date], ['size', S.size, 'r'], ['kind', S.kind]].forEach(function (c) {
      var b = el('button', (s.k === c[0] ? 'on ' : '') + (c[2] || ''), c[1] + (s.k === c[0] ? (s.d > 0 ? ' ▴' : ' ▾') : ''));
      b.onclick = function () {
        if (s.k === c[0]) s.d = -s.d; else { s.k = c[0]; s.d = c[0] === 'date' || c[0] === 'size' ? -1 : 1; }
        render();
      };
      h.appendChild(b);
    });
    wrap.appendChild(h);
    list.forEach(function (it) {
      var r = el('div', 'lr' + (sel.has(it.p) ? ' sel' : ''));
      r._it = it; r.title = itemTitle(it);
      var c1 = el('div', 'c1');
      c1.appendChild(iconFor(it, coarse ? 96 : 64));
      var txt = el('div', 'txt');
      var nm = el('span', 'nm', it.n);
      txt.appendChild(nm);
      if (found) txt.appendChild(el('span', 'where', parentOf(it.p) || '/'));
      txt.appendChild(el('span', 'sub', it.a ? (it.v ? it.v + ' · ' : '') + fmtSize(it.s) + ' · ' + S.src[it.src]
        : (found ? (parentOf(it.p) || '/') + ' · ' : '') + fmtDate(it.m) + (it.d ? '' : ' · ' + fmtSize(it.s))));
      c1.appendChild(txt);
      r.appendChild(c1);
      r.appendChild(el('span', 'c2', fmtDate(it.m)));
      r.appendChild(el('span', 'c2 r', it.d ? '—' : fmtSize(it.s)));
      r.appendChild(el('span', 'c2', it.a ? S.src[it.src] + (it.v ? ' · ' + it.v : '') : S.kinds[kindOf(it)]));
      var more = el('button', 'tb more'); more.appendChild(svg(it.d ? 'i-chev' : 'i-dots'));
      more.setAttribute('aria-label', S.more);
      more.onclick = function (ev) { ev.stopPropagation(); if (it.d) openItem(it); else { selectOnly(it); itemMenu(ev, it, true); } };
      r.appendChild(more);
      wrap.appendChild(r);
    });
    return wrap;
  }
  // Galerie: alles als quadratische Kachel – Bilder/Videos mit Vorschau, Ordner und andere Dateien mit großem Symbol + Name
  function galleryView(list) {
    var g = el('div', 'v-gallery');
    var dirs = list.filter(function (i) { return i.d; });
    var media = list.filter(function (i) { return !i.d && THUMB.test(i.n); });
    var others = list.filter(function (i) { return !i.d && !THUMB.test(i.n); });
    var tile = function (it, thumb) {
      var t = el('div', 'gt' + (thumb ? '' : ' file') + (sel.has(it.p) ? ' sel' : ''));
      t._it = it; t.title = itemTitle(it);
      t.appendChild(iconFor(it, thumb ? (coarse ? 240 : 320) : 0));
      if (!thumb) t.appendChild(el('div', 'gn', it.n));
      return t;
    };
    dirs.forEach(function (it) { g.appendChild(tile(it, false)); });
    var byMonth = sorts[kindKey()].k === 'date' && media.length, lastM = '';
    media.forEach(function (it) {
      if (byMonth) {
        var m = new Date(it.m * 1000).toLocaleDateString(undefined, { month: 'long', year: 'numeric' });
        if (m !== lastM) { g.appendChild(el('div', 'day', m)); lastM = m; }
      }
      g.appendChild(tile(it, true));
    });
    others.forEach(function (it) { g.appendChild(tile(it, false)); });
    return g;
  }

  document.querySelectorAll('#views button').forEach(function (b) { b.onclick = function () { setView(b.dataset.v); }; });
  function setView(v) { views[kindKey()] = v; store('localStorage', 'fm.v.' + kindKey(), v); render(); }

  // ---------- Vorschaubilder: per fetch mit Token-Header, nur Sichtbares, max. 3 gleichzeitig ----------
  var thumbCache = new Map(), thumbQueue = [], thumbBusy = 0, observer = null;
  function clearThumbs() { thumbCache.forEach(function (u) { URL.revokeObjectURL(u); }); thumbCache.clear(); thumbQueue = []; }
  function resetThumbs() {
    thumbQueue = [];
    if (observer) observer.disconnect();
    observer = 'IntersectionObserver' in window ? new IntersectionObserver(function (ents) {
      ents.forEach(function (e) {
        if (!e.isIntersecting) return;
        observer.unobserve(e.target);
        thumbQueue.push(e.target); pumpThumbs();
      });
    }, { root: $('content'), rootMargin: '400px' }) : null;
  }
  function wantThumb(box, it, size) {
    var key = it.p + '|' + it.m + '|' + size;
    box._thumb = it.a ? { key: key, path: '/api/appicon', params: { a: it.a }, app: true }
                      : { key: key, path: '/api/thumb', params: { p: it.p, s: size }, video: kindOf(it) === 'video' };
    if (thumbCache.has(key)) { setThumb(box, thumbCache.get(key)); return; }
    if (observer) observer.observe(box); else { thumbQueue.push(box); pumpThumbs(); }
  }
  function setThumb(box, url) {
    if (box._thumb.app) { var ai = el('img'); ai.alt = ''; ai.src = url; ai.draggable = false; box.firstChild.replaceChildren(ai); return; }
    var img = el('img', 'thumb'); img.alt = ''; img.src = url; img.draggable = false;
    var old = box.querySelector('svg.fi'); if (old) old.remove();
    box.insertBefore(img, box.firstChild);
    if (box._thumb.video && !box.querySelector('.play')) box.appendChild(el('span', 'play'));
  }
  function pumpThumbs() {
    while (thumbBusy < 3 && thumbQueue.length) {
      var box = thumbQueue.shift(), t = box._thumb;
      if (!box.isConnected || !t) continue;
      if (thumbCache.has(t.key)) { setThumb(box, thumbCache.get(t.key)); continue; }
      thumbBusy++;
      (function (box, t) {
        api('GET', t.path, t.params, { blob: true }).then(function (b) {
          var u = URL.createObjectURL(b); thumbCache.set(t.key, u);
          if (box.isConnected) setThumb(box, u);
        }, function () {}).then(function () { thumbBusy--; pumpThumbs(); });
      })(box, t);
    }
  }

  // ---------- Auswahl & Klicks (Finder: Klick wählt, Doppelklick öffnet; Touch: Tippen öffnet) ----------
  function itemAt(t) { while (t && t !== document.body) { if (t._it) return t; t = t.parentNode; } return null; }
  function selectOnly(it) { sel.clear(); sel.add(it.p); anchor = it.p; paintSel(); }
  function paintSel() {
    $('content').querySelectorAll('.it, .lr, .gt, .app').forEach(function (e) { e.classList.toggle('sel', sel.has(e._it.p)); });
    renderStatus();
  }
  var content = $('content'), suppressClick = false;
  content.addEventListener('pointerdown', function (e) { lastPointer = e.pointerType || 'mouse'; }, true);
  content.addEventListener('click', function (e) {
    if (suppressClick) { suppressClick = false; return; }
    var n = itemAt(e.target);
    if (!n) { if (e.target === content || e.target.classList.contains('v-icons') || e.target.classList.contains('v-list') || e.target.classList.contains('v-gallery')) { sel.clear(); paintSel(); } return; }
    var it = n._it, touch = lastPointer === 'touch' || lastPointer === 'pen';
    if (!touch && (e.metaKey || e.ctrlKey)) { if (sel.has(it.p)) sel.delete(it.p); else sel.add(it.p); anchor = it.p; paintSel(); return; }
    if (!touch && e.shiftKey && anchor) {
      var l = shown(), a = l.findIndex(function (x) { return x.p === anchor; }), b = l.indexOf(it);
      if (a >= 0 && b >= 0) { sel.clear(); l.slice(Math.min(a, b), Math.max(a, b) + 1).forEach(function (x) { sel.add(x.p); }); paintSel(); return; }
    }
    if (touch || (n.classList.contains('gt') && !n.classList.contains('file'))) { openItem(it); return; }
    selectOnly(it);
  });
  content.addEventListener('dblclick', function (e) { var n = itemAt(e.target); if (n && !(n.classList.contains('gt') && !n.classList.contains('file'))) openItem(n._it); });
  content.addEventListener('contextmenu', function (e) {
    e.preventDefault();
    var n = itemAt(e.target);
    if (n) { if (!sel.has(n._it.p)) selectOnly(n._it); itemMenu(e, n._it); }
    else { sel.clear(); paintSel(); bgMenu(e); }
  });
  // Langdruck (iOS Safari kennt kein contextmenu bei Touch)
  var lp = null;
  content.addEventListener('touchstart', function (e) {
    if (e.touches.length !== 1) { lp && clearTimeout(lp.t); lp = null; return; }
    var t = e.touches[0], n = itemAt(e.target);
    lp = { x: t.clientX, y: t.clientY, t: setTimeout(function () {
      lp = null; suppressClick = true;
      if (navigator.vibrate) navigator.vibrate(10);
      var ev = { clientX: t.clientX, clientY: t.clientY };
      if (n) { selectOnly(n._it); itemMenu(ev, n._it, true); } else bgMenu(ev, true);
    }, 480) };
  }, { passive: true });
  content.addEventListener('touchmove', function (e) {
    if (!lp) return;
    var t = e.touches[0];
    if (Math.abs(t.clientX - lp.x) > 8 || Math.abs(t.clientY - lp.y) > 8) { clearTimeout(lp.t); lp = null; }
  }, { passive: true });
  content.addEventListener('touchend', function () { if (lp) { clearTimeout(lp.t); lp = null; } });

  function selectedItems() { var l = shown().filter(function (i) { return sel.has(i.p); }); return l; }

  // ---------- Kontextmenü ----------
  function showMenu(ev, entries, title, sheet) {
    var m = $('menu'); m.replaceChildren();
    sheet = sheet || coarse || lastPointer === 'touch';
    m.className = sheet ? 'sheet' : '';
    if (title) m.appendChild(el('div', 'mh', title));
    entries.forEach(function (x) {
      if (x === '-') { m.appendChild(el('hr')); return; }
      var b = el('button', x.danger ? 'danger' : null);
      b.appendChild(svg(x.icon || 'i-chev')); b.appendChild(el('span', null, x.label));
      if (x.check) b.appendChild(el('span', 'ck', '✓'));
      b.onclick = function () { closeMenu(); x.fn(); };
      m.appendChild(b);
    });
    m.hidden = false; $('veil').hidden = false; $('veil').className = sheet ? 'dim' : '';
    if (!sheet) {
      var w = m.offsetWidth, h = m.offsetHeight;
      var x = Math.min(ev.clientX, innerWidth - w - 8), y = ev.clientY;
      if (y + h > innerHeight - 8) y = Math.max(8, y - h);
      m.style.left = Math.max(8, x) + 'px'; m.style.top = y + 'px';
    }
    var first = m.querySelector('button'); if (first && !sheet) first.focus({ preventScroll: true });
  }
  function closeMenu() { $('menu').hidden = true; $('veil').hidden = true; }
  $('veil').addEventListener('pointerdown', function (e) { e.preventDefault(); closeMenu(); });
  $('veil').addEventListener('contextmenu', function (e) { e.preventDefault(); closeMenu(); });

  function itemMenu(ev, it, sheet) {
    if (it.a) {
      var ea = [{ icon: 'i-info', label: S.info, fn: function () { appInfo(it); } }];
      if (it.rm) ea.push('-', { icon: 'i-trash', label: S.uninstall, danger: true, fn: function () { removeApp(it); } });
      showMenu(ev, ea, it.n, sheet);
      return;
    }
    var many = sel.size > 1 && sel.has(it.p), list = many ? selectedItems() : [it];
    var files = list.filter(function (i) { return !i.d; });
    var e = [];
    if (!many) e.push({ icon: 'i-open', label: S.open, fn: function () { openItem(it); } });
    if (files.length) e.push({ icon: 'i-dl', label: S.download, fn: function () { downloadMany(files); } });
    var rollable = files.filter(function (i) { return ROLLABLE.test(i.n) && !inDCIM(i.p); });
    if (rollable.length) e.push({ icon: 'i-roll', label: S.toRoll, fn: function () { toRoll(rollable); } });
    if (!many && /\.(deb|ipa)$/i.test(it.n)) e.push({ icon: 'i-apps', label: S.install, fn: function () { installFile(it); } });
    if (!many && writable(it)) { e.push('-'); e.push({ icon: 'i-edit', label: S.rename, fn: function () { renameItem(it); } }); }
    if (list.every(writable)) { if (many) e.push('-'); e.push({ icon: 'i-trash', label: S.del, danger: true, fn: function () { deleteItems(list); } }); }
    showMenu(ev, e, many ? S.selected(list.length) : it.n, sheet);
  }
  function bgMenu(ev, sheet) {
    var e = [];
    if (loc.k === 'dir' && !inDCIM(loc.p)) e.push({ icon: 'i-newdir', label: S.newFolder, fn: newFolder });
    if (loc.k !== 'music') e.push({ icon: 'i-up', label: loc.k === 'apps' ? S.install : S.upload, fn: pickFiles });
    if (e.length) e.push('-');
    var v = curView();
    e.push({ icon: 'i-icons', label: S.vIcons, check: v === 'icons', fn: function () { setView('icons'); } });
    e.push({ icon: 'i-list', label: S.vList, check: v === 'list', fn: function () { setView('list'); } });
    e.push({ icon: 'i-gallery', label: S.vGallery, check: v === 'gallery', fn: function () { setView('gallery'); } });
    e.push('-');
    e.push({ icon: 'i-sel', label: S.selectAll, fn: selectAll });
    e.push({ icon: 'i-eye', label: S.showHidden, check: showHidden, fn: toggleHidden });
    if (loc.k === 'dir') e.push({ icon: 'i-roll', label: S.rollOpt, check: rollOpt, fn: function () { setRollOpt(!rollOpt); } });
    showMenu(ev, e, locTitle(), sheet);
  }
  $('btnMore').onclick = function (ev) {
    var r = this.getBoundingClientRect();
    bgMenu({ clientX: r.right - 230, clientY: r.bottom + 4 });
  };
  function toggleHidden() { showHidden = !showHidden; store('localStorage', 'fm.h', showHidden ? '1' : '0'); render(); }
  function setRollOpt(v) { rollOpt = v; $('upRoll').checked = v; store('localStorage', 'fm.r', v ? '1' : '0'); }
  $('upRoll').onchange = function () { setRollOpt(this.checked); };
  function selectAll() { shown().forEach(function (i) { sel.add(i.p); }); paintSel(); }

  // ---------- Dialog ----------
  var dlgDone = null;
  function ask(o) {
    return new Promise(function (resolve) {
      var d = $('dlg'), box = d.firstChild;
      box.querySelector('h3').textContent = o.title;
      var p = box.querySelector('p'); p.textContent = o.text || ''; p.hidden = !o.text; p.style.whiteSpace = 'pre-line';
      var inp = box.querySelector('input'), err = box.querySelector('.err');
      inp.hidden = o.input == null; inp.value = o.input || ''; inp.type = o.type || 'text';
      inp.style.fontFamily = o.mono ? 'ui-monospace, Menlo, monospace' : '';
      err.textContent = ''; err.hidden = true;
      var row = box.querySelector('.row'); row.replaceChildren();
      var cancel = el('button', 'btn', o.cancel || S.cancel), ok = el('button', 'btn ' + (o.danger ? 'danger' : 'primary'), o.ok || S.ok);
      if (!o.noCancel) row.appendChild(cancel);
      row.appendChild(ok);
      d.hidden = false;
      dlgDone = function (v) { d.hidden = true; dlgDone = null; resolve(v); };
      cancel.onclick = function () { dlgDone(null); };
      ok.onclick = function () {
        if (o.input == null) return dlgDone(true);
        var v = inp.value.trim();
        var problem = o.check && o.check(v);
        if (problem) { err.textContent = problem; err.hidden = false; inp.focus(); return; }
        dlgDone(v);
      };
      inp.onkeydown = function (e) { if (e.key === 'Enter') { e.preventDefault(); ok.click(); } };
      if (o.input != null) {
        inp.focus();
        var dot = o.input.lastIndexOf('.');
        inp.setSelectionRange(0, o.selectBase && dot > 0 ? dot : o.input.length);
      } else ok.focus();
    });
  }

  // ---------- Öffnen, Herunterladen ----------
  function openItem(it) {
    if (it.a) { appInfo(it); return; }
    if (it.d) { go({ k: 'dir', p: it.p }); return; }
    if (VIEWABLE.test(it.n)) { openViewer(it); return; }
    if (kindOf(it) === 'audio') { play(it); return; }
    download(it);
  }
  function ticket(it) { return api('POST', '/api/ticket', { p: it.p }).then(function (j) { return '/dl?k=' + encodeURIComponent(j.k); }); }
  function download(it) {
    return ticket(it).then(function (url) {
      var a = document.createElement('a'); a.href = url; a.rel = 'noreferrer';
      document.body.appendChild(a); a.click(); a.remove();
    }, fail);
  }
  function downloadMany(list) {
    var i = 0;
    (function next() { if (i < list.length) download(list[i++]).then(function () { setTimeout(next, 600); }); })();
  }

  // ---------- Apps ----------
  function appInfo(it) {
    var lines = [S.version + ': ' + (it.v || '—'), S.size2 + ': ' + fmtSize(it.s), S.bundle + ': ' + (it.id || '—')];
    if (it.pkg) lines.push(S.pkg + ': ' + it.pkg);
    if (!it.rm) lines.push('', S.sysNote);
    ask({ title: it.n, text: lines.join('\n'), ok: it.rm ? S.uninstall : S.ok, danger: it.rm, noCancel: !it.rm }).then(function (y) {
      if (y && it.rm) removeApp(it);
    });
  }
  function removeApp(it) {
    toast(S.confirmOnIpod, 125000);
    api('POST', '/api/appdel', { a: it.a }).then(function () { toast(S.removed(it.n)); sel.clear(); reload(); }, fail);
  }
  function installFile(it) {
    toast(S.confirmOnIpod, 125000);
    api('POST', '/api/pkgfile', { p: it.p }).then(function (j) { toast(S.installedT(j.name || it.n)); }, fail);
  }

  // ---------- Musik ----------
  function play(it) {
    ticket(it).then(function (url) {
      var p = $('player'), a = p.querySelector('audio');
      p.querySelector('.pn').textContent = it.n;
      a.src = url + '&inline=1'; p.hidden = false;
      a.play().catch(function () {});
    }, fail);
  }
  function stopPlayer() { var a = $('player').querySelector('audio'); a.pause(); a.removeAttribute('src'); $('player').hidden = true; }
  $('pClose').onclick = stopPlayer;

  // ---------- Aktionen ----------
  function nameCheck(cur) {
    return function (v) {
      if (!validName(v)) return S.err.badname;
      if (v !== cur && items.some(function (i) { return i.n === v; })) return S.err.exists;
      return null;
    };
  }
  function renameItem(it) {
    ask({ title: S.renameTitle, input: it.n, selectBase: !it.d, ok: S.rename, check: nameCheck(it.n) }).then(function (n) {
      if (!n || n === it.n) return;
      api('POST', '/api/mv', { p: it.p, n: n }).then(function () { toast(S.renamed); sel.clear(); reload(); }, fail);
    });
  }
  function newFolder() {
    var base = S.untitled, n = base, i = 2;
    while (items.some(function (x) { return x.n === n; })) n = base + ' ' + i++;
    ask({ title: S.newFolderTitle, input: n, ok: S.create, check: nameCheck(null) }).then(function (v) {
      if (!v) return;
      api('POST', '/api/mkdir', { p: loc.p, n: v }).then(function () {
        toast(S.created); sel.clear(); sel.add(join(loc.p, v)); reload();
      }, fail);
    });
  }
  $('btnNew').onclick = newFolder;
  function deleteItems(list) {
    var names = list.length === 1 ? '„' + list[0].n + '“' : list.slice(0, 3).map(function (i) { return i.n; }).join(', ') + (list.length > 3 ? ' …' : '');
    if (!de && list.length === 1) names = '“' + list[0].n + '”';
    ask({ title: S.delTitle(list.length), text: S.delText(names, list.some(function (i) { return i.d; })), ok: S.del, danger: true }).then(function (y) {
      if (!y) return;
      var n = 0;
      list.reduce(function (pr, it) {
        return pr.then(function () { return api('POST', '/api/rm', { p: it.p }).then(function () { n++; }); });
      }, Promise.resolve()).then(function () { toast(S.deleted(n)); }, fail).then(function () { sel.clear(); reload(); });
    });
  }
  function toRoll(list) {
    toast(S.importing);
    list.reduce(function (pr, it) { return pr.then(function () { return api('POST', '/api/import', { p: it.p }); }); }, Promise.resolve())
      .then(function () { toast(S.added); reload(); }, fail);
  }

  // ---------- Suche ----------
  var findBusy = false;
  $('q').addEventListener('input', function () {
    query = this.value.trim();
    clearTimeout(findTimer);
    found = null; findBusy = false; findSeq++;
    if (query.length >= 2 && loc.k === 'dir') findTimer = setTimeout(runFind, 400);
    render();
  });
  $('q').addEventListener('keydown', function (e) { if (e.key === 'Escape') { this.value = ''; this.dispatchEvent(new Event('input')); this.blur(); } });
  function runFind() {
    var seq = ++findSeq, q = query;
    findBusy = true;
    api('GET', '/api/find', { p: loc.p, q: q, h: showHidden ? '1' : '0' }).then(function (j) {
      if (seq !== findSeq) return;
      findBusy = false;
      found = j.items || []; findMore = !!j.more;
      render();
      renderNote(S.searchIn(q, locTitle()) + (findMore ? ' – ' + S.moreResults : ''));
    }, function (e) { if (seq === findSeq) { findBusy = false; fail(e); } });
  }

  // ---------- Betrachter: Vollbild, wischen, Pfeiltasten ----------
  var vList = [], vIdx = 0, slides = new Map(), vBusy = false;
  function openViewer(it) {
    vList = shown().filter(function (i) { return !i.d && VIEWABLE.test(i.n); });
    vIdx = Math.max(0, vList.indexOf(it));
    $('viewer').hidden = false; $('viewer').classList.remove('bare');
    layoutSlides(false);
  }
  function closeViewer() {
    $('viewer').hidden = true;
    slides.forEach(function (s) { if (s._url) URL.revokeObjectURL(s._url); });
    slides.clear(); $('track').replaceChildren();
  }
  function slideFor(it) {
    if (slides.has(it.p)) return slides.get(it.p);
    var s = el('div', 'slide'); s.appendChild(el('span', 'spin'));
    slides.set(it.p, s);
    api('GET', '/api/thumb', { p: it.p, s: 1280 }, { blob: true }).then(function (b) {
      s._url = URL.createObjectURL(b);
      var img = el('img'); img.src = s._url; img.alt = ''; img.draggable = false;
      s.replaceChildren(img);
      if (kindOf(it) === 'video') {
        var pb = el('button', 'bigplay'); pb.setAttribute('aria-label', S.open);
        pb.onclick = function (e) { e.stopPropagation(); playVideo(s, it); };
        s.appendChild(pb);
      }
    }, function (e) {
      if (kindOf(it) === 'video') { s.replaceChildren(); playVideo(s, it); }
      else s.replaceChildren(el('div', 'msg', e.message));
    });
    return s;
  }
  function playVideo(s, it) {
    ticket(it).then(function (url) {
      var v = el('video'); v.controls = true; v.autoplay = true; v.playsInline = true; v.src = url + '&inline=1';
      s.replaceChildren(v);
    }, fail);
  }
  function layoutSlides() {
    var tr = $('track'), keep = new Set();
    var f = document.createDocumentFragment();
    [-1, 0, 1].forEach(function (d) {
      var it = vList[vIdx + d];
      var s = it ? slideFor(it) : el('div', 'slide');
      if (it) keep.add(it.p);
      f.appendChild(s);
    });
    tr.querySelectorAll('video').forEach(function (v) { v.pause(); });
    slides.forEach(function (s, p) {                       // weit entfernte Bilder freigeben
      if (keep.has(p)) return;
      var i = vList.findIndex(function (x) { return x.p === p; });
      if (i < 0 || Math.abs(i - vIdx) > 3) { if (s._url) URL.revokeObjectURL(s._url); slides.delete(p); }
    });
    tr.style.transition = 'none'; tr.style.transform = 'translateX(-100%)';
    tr.replaceChildren(f);
    var it = vList[vIdx];
    $('vName').textContent = it.n;
    $('vPos').textContent = vList.length > 1 ? S.of(vIdx + 1, vList.length) : '';
    $('vPrev').hidden = vIdx <= 0; $('vNext').hidden = vIdx >= vList.length - 1;
    $('vRoll').hidden = !ROLLABLE.test(it.n) || inDCIM(it.p);
    if (vList[vIdx + 2]) slideFor(vList[vIdx + 2]);       // eins weiter vorladen
  }
  function step(d) {
    if (vBusy || !vList[vIdx + d]) return;
    vBusy = true;
    var tr = $('track');
    tr.style.transition = 'transform .28s cubic-bezier(.2,.8,.2,1)';
    tr.style.transform = 'translateX(' + (-100 - d * 100) + '%)';
    setTimeout(function () { vIdx += d; vBusy = false; layoutSlides(); }, 290);
  }
  function snapBack() { var tr = $('track'); tr.style.transition = 'transform .22s ease-out'; tr.style.transform = 'translateX(-100%)'; }
  var drag = null;
  $('stage').addEventListener('pointerdown', function (e) {
    if (e.target.tagName === 'VIDEO' || e.target.closest('.bigplay') || vBusy || !e.isPrimary) return;
    drag = { x: e.clientX, y: e.clientY, dx: 0, id: e.pointerId, t: Date.now() };
    this.setPointerCapture(e.pointerId);
  });
  $('stage').addEventListener('pointermove', function (e) {
    if (!drag || e.pointerId !== drag.id) return;
    drag.dx = e.clientX - drag.x;
    var edge = (drag.dx > 0 && vIdx === 0) || (drag.dx < 0 && vIdx === vList.length - 1);
    var tr = $('track'); tr.style.transition = 'none';
    tr.style.transform = 'translateX(calc(-100% + ' + (edge ? drag.dx / 3 : drag.dx) + 'px))';
  });
  function endDrag(e) {
    if (!drag || e.pointerId !== drag.id) return;
    var d = drag; drag = null;
    var w = $('stage').clientWidth, fast = Math.abs(d.dx) > 30 && Date.now() - d.t < 250;
    if (Math.abs(d.dx) < 6 && e.type === 'pointerup') { snapBack(); $('viewer').classList.toggle('bare'); return; }
    if ((d.dx < -w / 5 || (fast && d.dx < 0)) && vIdx < vList.length - 1) step(1);
    else if ((d.dx > w / 5 || (fast && d.dx > 0)) && vIdx > 0) step(-1);
    else snapBack();
  }
  $('stage').addEventListener('pointerup', endDrag);
  $('stage').addEventListener('pointercancel', endDrag);
  $('vClose').onclick = closeViewer;
  $('vPrev').onclick = function () { step(-1); };
  $('vNext').onclick = function () { step(1); };
  $('vDown').onclick = function () { download(vList[vIdx]); };
  $('vRoll').onclick = function () { toRoll([vList[vIdx]]); };

  // ---------- Tastatur ----------
  document.addEventListener('keydown', function (e) {
    if (!$('dlg').hidden) { if (e.key === 'Escape') dlgDone && dlgDone(null); return; }
    if (!$('menu').hidden) {
      if (e.key === 'Escape') closeMenu();
      else if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        var bs = Array.prototype.slice.call($('menu').querySelectorAll('button')), i = bs.indexOf(document.activeElement);
        bs[(i + (e.key === 'ArrowDown' ? 1 : bs.length - 1)) % bs.length].focus(); e.preventDefault();
      }
      return;
    }
    if (!$('viewer').hidden) {
      if (e.key === 'Escape') closeViewer();
      else if (e.key === 'ArrowLeft') step(-1);
      else if (e.key === 'ArrowRight' || e.key === ' ') { e.preventDefault(); step(1); }
      return;
    }
    if (!$('shell').hidden || !token || $('app').hidden) return;
    var typing = /^(INPUT|TEXTAREA)$/.test(document.activeElement.tagName);
    if (typing) return;
    var cmd = e.metaKey || e.ctrlKey;
    if (cmd && e.key === 'a') { e.preventDefault(); selectAll(); }
    else if (cmd && e.key === 'f') { e.preventDefault(); $('q').focus(); }
    else if (e.key === 'Escape') { sel.clear(); paintSel(); }
    else if (e.key === 'Enter' && sel.size === 1) openItem(selectedItems()[0]);
    else if ((e.key === 'Delete' || (cmd && e.key === 'Backspace')) && sel.size) {
      var l = selectedItems(); if (l.every(writable)) deleteItems(l);
    } else if (cmd && e.key === 'ArrowUp' && loc.k === 'dir' && loc.p) go({ k: 'dir', p: parentOf(loc.p) });
  });

  // ---------- Hochladen: Knopf + Drag & Drop, mit Fortschritt ----------
  var queue = [], upBusy = false, upDone = 0, upTotal = 0, bytesDone = 0, bytesAll = 0;
  function pickFiles() {
    if (!loc || loc.k === 'music') return;
    // Fotos: „image/*,video/*“ lässt iOS beim Auswählen selbst in JPG/H.264 umwandeln (iOS 6 kennt kein HEIC/HEVC)
    $('file').accept = loc.k === 'apps' ? '.deb,.ipa' : loc.k === 'photos' || inDCIM(loc.p) ? 'image/*,video/*' : '';
    $('file').click();
  }
  $('btnUp').onclick = pickFiles;
  $('fab').onclick = pickFiles;
  $('file').addEventListener('change', function () { enqueue(Array.prototype.slice.call(this.files)); this.value = ''; });
  $('upClose').onclick = function () {
    if (upBusy || queue.length) return;
    $('uploads').hidden = true; $('upList').replaceChildren(); upDone = upTotal = bytesDone = bytesAll = 0;
    $('fab').hidden = !loc || loc.k === 'music';
  };
  $('upMin').onclick = function () { $('uploads').classList.toggle('small'); };

  function enqueue(files) {
    if (!files.length || !token || !loc || loc.k === 'music') return;
    $('uploads').hidden = false;
    $('fab').hidden = true;
    var photos = loc.k === 'photos' || inDCIM(loc.p);
    files.forEach(function (f) {
      var u = { file: f, dir: loc.k === 'dir' ? loc.p : null, loc: loc, photos: photos && ROLLABLE.test(f.name), row: el('div', 'up'), sent: 0 };
      u.row.appendChild(iconFor({ n: f.name, d: false }));
      var b = el('div', 'ub');
      b.appendChild(el('div', 'un', f.name));
      u.stat = el('div', 'us', S.waiting); b.appendChild(u.stat);
      var bar = el('div', 'bar'); u.fill = el('i'); bar.appendChild(u.fill); b.appendChild(bar);
      u.row.appendChild(b);
      $('upList').appendChild(u.row);
      // Kamerarolle nimmt nur, was iOS 6 kennt: HEIC/WebP vorher in JPG umwandeln, alles andere nach Downloads
      if (photos && !u.photos) { if (CONVERTIBLE.test(f.name)) u.convert = true; else u.fallback = true; }
      if (loc.k === 'apps') { u.pkg = true; if (!/\.(deb|ipa)$/i.test(f.name)) u.bad = S.err.pkgtype; }
      queue.push(u); upTotal++; bytesAll += f.size;
    });
    upHeader(); pump();
  }
  function upHeader() {
    $('uploads').querySelector('.uh b').textContent = S.uploads(upDone, upTotal);
    $('uploads').querySelector('.tot i').style.width = (bytesAll ? (bytesDone / bytesAll * 100) : 100).toFixed(1) + '%';
    $('uploads').querySelector('.opt').hidden = !loc || loc.k !== 'dir' || inDCIM(loc.p);
  }
  function pump() {
    if (upBusy) return;
    var u = queue.shift();
    if (!u) return;
    upBusy = true;
    send(u, '0').then(function () {
      upBusy = false; upDone++; bytesDone += u.file.size - u.sent; upHeader();
      if (sameLoc(u.loc, loc)) reload();
      pump();
    });
  }
  function finish(u, cls, text) { u.row.classList.add(cls); u.stat.textContent = text; }

  // Bild im Browser dekodieren (Safari kann HEIC) und als JPG neu kodieren; null wenn der Browser es nicht lesen kann
  function toJpeg(file) {
    var MAX = 3264;
    var load = window.createImageBitmap ? createImageBitmap(file) : new Promise(function (ok, no) {
      var img = new Image(), url = URL.createObjectURL(file);
      img.onload = function () { URL.revokeObjectURL(url); ok(img); };
      img.onerror = function () { URL.revokeObjectURL(url); no(); };
      img.src = url;
    });
    return load.then(function (img) {
      var w = img.width, h = img.height, k = Math.min(1, MAX / Math.max(w, h));
      var c = document.createElement('canvas');
      c.width = Math.round(w * k); c.height = Math.round(h * k);
      c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
      if (img.close) img.close();
      return new Promise(function (ok) { c.toBlob(ok, 'image/jpeg', 0.9); });
    }).then(function (b) {
      if (!b || !b.size) return null;
      return new File([b], file.name.replace(/\.[^.]+$/, '') + '.jpg', { type: 'image/jpeg', lastModified: file.lastModified });
    }, function () { return null; });
  }
  function toDownloads(u) { u.photos = false; u.dir = DL_DIR; u.loc = { k: 'dir', p: DL_DIR }; u.note = S.savedDl; }

  function send(u, overwrite) {
    if (u.convert) {
      u.convert = false;
      u.stat.textContent = S.converting;
      return toJpeg(u.file).then(function (jpg) {
        if (jpg) { bytesAll += jpg.size - u.file.size; u.file = jpg; u.photos = true; u.row.querySelector('.un').textContent = jpg.name; }
        else toDownloads(u);
        return send(u, overwrite);
      });
    }
    if (u.fallback) { u.fallback = false; toDownloads(u); }
    var f = u.file;
    if (u.bad) { finish(u, 'err', u.bad); return Promise.resolve(); }
    if (!validName(f.name)) { finish(u, 'err', S.err.badname); return Promise.resolve(); }
    if (info && f.size > info.free) { finish(u, 'err', S.err.space); return Promise.resolve(); }
    var pre = Promise.resolve(overwrite);
    if (!u.photos && !u.pkg && u.dir != null && sameLoc(u.loc, loc) && overwrite === '0') {     // Vorprüfung mit der aktuellen Liste
      var ex = items.filter(function (i) { return i.n === f.name; })[0];
      if (ex && ex.d) { finish(u, 'err', S.err.isdir); return Promise.resolve(); }
      if (ex) pre = askReplace(f.name);
    }
    return pre.then(function (o) {
      if (o == null) { finish(u, 'err', S.skipped); return; }
      return xhrUpload(u, o);
    });
  }
  function askReplace(name) {
    return ask({ title: S.exists(name), text: S.existsText, ok: S.replace, cancel: S.skip, danger: true }).then(function (y) { return y ? '1' : null; });
  }
  function xhrUpload(u, overwrite) {
    return new Promise(function (resolve) {
      var f = u.file, x = new XMLHttpRequest(), t0 = Date.now();
      var roll = !u.photos && rollOpt && ROLLABLE.test(f.name);
      var params = u.photos ? { photos: '1', n: f.name } : { p: u.dir, n: f.name, o: overwrite, cr: roll ? '1' : '0' };
      x.open('PUT', u.pkg ? '/api/pkg?' + qs({ n: f.name }) : '/api/up?' + qs(params));
      x.setRequestHeader('X-FM-Token', token);
      x.upload.onprogress = function (e) {
        if (!e.lengthComputable) return;
        bytesDone += e.loaded - u.sent; u.sent = e.loaded; upHeader();
        u.fill.style.width = (e.loaded / e.total * 100).toFixed(1) + '%';
        var sec = (Date.now() - t0) / 1000;
        if (u.pkg && e.loaded >= e.total) { u.row.classList.add('wait'); u.stat.textContent = S.confirmOnIpod; return; }
        u.stat.textContent = e.loaded >= e.total && (u.photos || roll) ? S.importing
          : fmtSize(e.loaded) + ' / ' + fmtSize(e.total) + (sec > 1 ? ' · ' + fmtSize(e.loaded / sec) + '/s' : '');
      };
      x.onload = function () {
        var j = {}; try { j = JSON.parse(x.responseText); } catch (e) {}
        u.row.classList.remove('wait');
        if (x.status === 200 && u.pkg) { finish(u, 'ok', S.installed + (j.name ? ' · ' + j.name : '')); return resolve(); }
        if (x.status === 200) {
          var t = u.photos ? S.inRoll : u.note || S.done + ' · ' + fmtSize(f.size);
          if (j.cr) t += j.cr === 'ok' ? S.plusRoll : S.rollFail(errText(j.cr, 0));
          finish(u, j.cr && j.cr !== 'ok' ? 'err' : 'ok', t); return resolve();
        }
        if (x.status === 401) { finish(u, 'err', S.expired); signOut(S.expired); return resolve(); }
        if (x.status === 409 && j.error === 'exists' && overwrite === '0') {
          return askReplace(f.name).then(function (o) {
            if (!o) { finish(u, 'err', S.skipped); return resolve(); }
            u.fill.style.width = '0'; bytesDone -= u.sent; u.sent = 0;
            xhrUpload(u, o).then(resolve);
          });
        }
        finish(u, 'err', errText(j.error, x.status));
        if (j.log) {                                        // Protokoll der Installation per Klick
          u.row.classList.add('log'); u.row.title = S.showLog;
          u.row.onclick = function () { ask({ title: f.name, text: j.log.slice(-1200), noCancel: true }); };
        }
        resolve();
      };
      x.onerror = x.onabort = function () { finish(u, 'err', S.err.network); resolve(); };
      x.send(f);
    });
  }

  var dragDepth = 0;
  function hasFiles(e) { var t = e.dataTransfer && e.dataTransfer.types; return !!t && Array.prototype.indexOf.call(t, 'Files') >= 0; }
  function canDrop() { return token && loc && loc.k !== 'music' && $('viewer').hidden && $('shell').hidden; }
  window.addEventListener('dragenter', function (e) {
    if (!hasFiles(e)) return;
    e.preventDefault();
    if (!canDrop()) return;
    dragDepth++;
    $('drop').querySelector('span').textContent = loc.k === 'apps' ? S.dropInstall : loc.k === 'photos' || inDCIM(loc.p) ? S.dropRoll : S.dropTo(locTitle());
    $('drop').hidden = false;
  });
  window.addEventListener('dragover', function (e) { if (!hasFiles(e)) return; e.preventDefault(); e.dataTransfer.dropEffect = canDrop() ? 'copy' : 'none'; });
  window.addEventListener('dragleave', function () { if (--dragDepth <= 0) { dragDepth = 0; $('drop').hidden = true; } });
  window.addEventListener('drop', function (e) {
    if (!hasFiles(e)) return;
    e.preventDefault();
    dragDepth = 0; $('drop').hidden = true;
    if (!canDrop()) return;
    var files = [], dirs = 0, dt = e.dataTransfer;
    if (dt.items && dt.items.length) {
      Array.prototype.forEach.call(dt.items, function (it) {
        if (it.kind !== 'file') return;
        var entry = it.webkitGetAsEntry && it.webkitGetAsEntry();
        if (entry && entry.isDirectory) { dirs++; return; }
        var f = it.getAsFile(); if (f) files.push(f);
      });
    } else files = Array.prototype.slice.call(dt.files);
    if (dirs) toast(S.skippedDirs);
    enqueue(files);
  });

  // ---------- Kommandozeile (nur wenn am iPod erlaubt; eigenes Passwort) ----------
  var shTok = '', shCur = 0, shRun = 0, shDec = null, hist = [], histPos = 0;
  function shellReset() { shTok = ''; shRun++; $('shell').hidden = true; }
  function openShell() {
    if (shTok) { $('shell').hidden = false; $('shIn').focus(); renderSide(); return; }
    ask({ title: S.shellPassTitle, text: S.shellPassText, input: '', mono: true, ok: S.login }).then(function (pw) {
      if (!pw) return;
      api('POST', '/api/sh/open', null, { headers: { 'X-FM-ShellPass': pw } }).then(function (j) {
        shTok = j.st; shCur = 0; shDec = new TextDecoder('utf-8');
        $('shOut').replaceChildren(el('span', 'sys', S.shellOpened + '\n'));
        $('shTitle').textContent = 'mobile@' + (info ? info.name : 'iPod');
        $('shell').hidden = false; $('shIn').focus();
        renderSide(); pollShell(++shRun);
      }, function (e) { fail(e); if (e.code === 'shelllocked' || e.code === 'shelloff') loadInfo(); });
    });
  }
  function shHeaders() { return { 'X-FM-Shell': shTok }; }
  function pollShell(run) {
    if (run !== shRun || !shTok) return;
    api('GET', '/api/sh/out', { c: shCur }, { raw: true, headers: shHeaders() }).then(function (r) {
      var cur = r.headers.get('X-FM-Cursor'), end = r.headers.get('X-FM-End') === '1';
      return r.arrayBuffer().then(function (buf) {
        if (run !== shRun) return;
        if (cur) shCur = Number(cur);
        if (buf.byteLength) shAppend(shDec.decode(new Uint8Array(buf), { stream: true }));
        if (end) { shAppend('\n' + S.shellEnded + '\n', 'sys'); shTok = ''; renderSide(); return; }
        pollShell(run);
      });
    }, function (e) {
      if (run !== shRun) return;
      if (e.status === 403 || e.auth) { shAppend('\n' + S.shellGone + (e.code && S.err[e.code] ? ' ' + S.err[e.code] : '') + '\n', 'sys'); shTok = ''; loadInfo(); return; }
      setTimeout(function () { pollShell(run); }, 1500);
    });
  }
  // Steuerzeichen/ANSI-Farben entfernen, \r und Backspace grob nachbilden
  function shClean(t) {
    t = t.replace(/\x1b\[[0-9;?]*[ -\/]*[@-~]/g, '').replace(/\x1b\][^\x07\x1b]*(\x07|\x1b\\)/g, '').replace(/\x1b[()][0-9A-B]|\x1b[=>78DEHM]/g, '');
    t = t.replace(/\r+\n/g, '\n').replace(/[\x00-\x07\x0b\x0c\x0e-\x1f\x7f]/g, function (c) { return c === '\x08' ? c : ''; });
    return t;
  }
  function shAppend(t, cls) {
    var out = $('shOut'), atEnd = out.scrollHeight - out.scrollTop - out.clientHeight < 40;
    t = cls ? t : shClean(t);
    if (!cls && /[\r\x08]/.test(t)) {                        // \r = Zeilenanfang, \b = ein Zeichen zurück
      var all = out.lastChild && out.lastChild.nodeType === 3 ? out.lastChild.data : '';
      if (all) out.lastChild.remove();
      var s = all;
      for (var i = 0; i < t.length; i++) {
        var c = t[i];
        if (c === '\x08') s = s.slice(0, -1);
        else if (c === '\r') s = s.slice(0, s.lastIndexOf('\n') + 1);
        else s += c;
      }
      out.appendChild(document.createTextNode(s));
    } else out.appendChild(cls ? el('span', cls, t) : document.createTextNode(t));
    while (out.childNodes.length > 4000) out.removeChild(out.firstChild);
    if (atEnd) out.scrollTop = out.scrollHeight;
  }
  function shSend(data) {
    if (!shTok) return Promise.resolve();
    return api('POST', '/api/sh/in', null, { headers: shHeaders(), body: data }).catch(function (e) { fail(e); });
  }
  $('shForm').addEventListener('submit', function (e) {
    e.preventDefault();
    var v = $('shIn').value;
    if (!shTok) return;
    shAppend('$ ' + v + '\n', 'in');
    if (v.trim()) { hist.push(v); if (hist.length > 100) hist.shift(); }
    histPos = hist.length;
    $('shIn').value = '';
    shSend(v + '\n');
  });
  $('shIn').addEventListener('keydown', function (e) {
    if (e.key === 'ArrowUp' && histPos > 0) { e.preventDefault(); this.value = hist[--histPos]; }
    else if (e.key === 'ArrowDown') { e.preventDefault(); histPos = Math.min(hist.length, histPos + 1); this.value = hist[histPos] || ''; }
    else if (e.ctrlKey && e.key === 'c') { e.preventDefault(); shSend('\x03'); shAppend('^C\n', 'in'); }
    else if (e.ctrlKey && e.key === 'd') { e.preventDefault(); shSend('\x04'); }
    else if (e.key === 'Escape') { $('shell').hidden = true; renderSide(); }
  });
  $('shInt').onclick = function () { shSend('\x03'); shAppend('^C\n', 'in'); $('shIn').focus(); };
  $('shClear').onclick = function () { $('shOut').replaceChildren(); $('shIn').focus(); };
  $('shClose').onclick = function () {
    if (shTok) api('POST', '/api/sh/close', null, { headers: shHeaders() }).catch(function () {});
    shellReset(); renderSide();
  };

  // ---------- Start ----------
  function start() {
    navDepth = 0; fwdDepth = 0;
    loadInfo();
    clearInterval(infoTimer);
    infoTimer = setInterval(function () { if (token && !document.hidden) loadInfo(); }, 15000);
    var l = locFromHash();
    if (l) load(l);
    else { history.replaceState(null, '', locHash({ k: 'photos' })); load({ k: 'photos' }); }
  }
  if (qrPin) { token = ''; store('sessionStorage', 'fm.t', null); showLogin(''); $('pin').value = qrPin; login(qrPin); }
  else if (token) { $('app').hidden = false; start(); }
  else showLogin('');
})();
