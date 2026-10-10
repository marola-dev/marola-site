/** contact.html: posts the form to Web3Forms, which emails it on and keeps no copy (#119). */
(function () {
  'use strict';

  var ENDPOINT = 'https://api.web3forms.com/submit';
  var form = document.getElementById('contact-form');
  if (!form) return;
  var i18n = window.marolaI18n;
  var t = i18n ? i18n.t : function (k) { return k; };
  var key = (window.MAROLA_CONTACT || {}).accessKey;
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
    if (!key || send.disabled) return;
    // The hidden checkbox only a bot fills: drop the message and look like it went.
    if (form.elements.namedItem('botcheck').checked) { form.reset(); show('sent'); return; }
    var topic = field('topic');
    send.disabled = true;
    show('sending');
    fetch(ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({
        access_key: key,
        subject: 'marola.dev: ' + topic.options[topic.selectedIndex].text,
        from_name: 'marola.dev',
        name: field('name').value.trim(),
        email: field('email').value.trim(),
        topic: topic.value,
        message: field('message').value,
        lang: i18n ? i18n.lang() : ''
      })
    })
      .then(function (r) { return r.json().then(function (j) { if (!r.ok || !j.success) throw new Error(j.message || r.status); }); })
      .then(function () { form.reset(); show('sent'); }, function () { show('error'); })
      .then(function () { send.disabled = false; });
  });

  if (!key) {
    send.disabled = true;
    document.getElementById('contact-off').hidden = false;
  }
})();
