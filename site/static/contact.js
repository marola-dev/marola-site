/** contact.html: posts the form to the Worker's /contact, which opens an issue in marola-dev/contato (#119). */
(function () {
  'use strict';

  var ENDPOINT = '/contact';
  var form = document.getElementById('contact-form');
  if (!form) return;
  var i18n = window.marolaI18n;
  var t = i18n ? i18n.t : function (k) { return k; };
  var send = form.querySelector('button[type="submit"]');
  var status = document.getElementById('contact-status');
  var shown = null;

  function show(state) {
    shown = state;
    status.textContent = state ? t('contact.' + state) : '';
    status.classList.toggle('err', state === 'error');
  }
  if (i18n) i18n.onLang(function () { if (shown) show(shown); });

  function field(id) { return document.getElementById('contact-' + id); }

  form.addEventListener('submit', function (e) {
    e.preventDefault();
    if (send.disabled) return;
    // The hidden checkbox only a bot fills: drop the message and look like it went.
    if (form.elements.namedItem('botcheck').checked) { form.reset(); show('sent'); return; }
    send.disabled = true;
    show('sending');
    fetch(ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({
        name: field('name').value.trim(),
        email: field('email').value.trim(),
        topic: field('topic').value,
        message: field('message').value,
        lang: i18n ? i18n.lang() : ''
      })
    })
      .then(function (r) { return r.json().then(function (j) { if (!r.ok || !j.success) throw new Error(j.error || r.status); }); })
      .then(function () { form.reset(); show('sent'); }, function () { show('error'); })
      .then(function () { send.disabled = false; });
  });
})();
