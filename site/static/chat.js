/** marola chat widget — MIP-0033 §5.2. */
(function () {
  'use strict';

  var endpoint = (window.MAROLA_CHAT_ENDPOINT || '').replace(/\/$/, '');
  if (!endpoint) return;

  var toggle = document.getElementById('chat-toggle');
  var panel = document.getElementById('chat-panel');
  var closeBtn = document.getElementById('chat-close');
  var log = document.getElementById('chat-log');
  var offline = document.getElementById('chat-offline');
  var form = document.getElementById('chat-form');
  var input = document.getElementById('chat-input');
  if (!toggle || !panel || !form || !input) return;

  function addMessage(role, text) {
    var p = document.createElement('p');
    p.className = 'chat-msg ' + role;
    p.textContent = text;
    log.appendChild(p);
    log.scrollTop = log.scrollHeight;
    return p;
  }

  function ask(question) {
    addMessage('user', question);
    offline.hidden = true;
    var pending = addMessage('assistant pending', '…');
    fetch(endpoint + '/ask', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ question: question }),
      signal: AbortSignal.timeout(30000)
    })
      .then(function (res) {
        return res.json().then(function (body) {
          if (!res.ok || !body || typeof body.answer !== 'string') throw new Error('no answer');
          return body.answer;
        });
      })
      .finally(function () { pending.remove(); })
      .then(function (answer) { addMessage('assistant', answer); }, function () { offline.hidden = false; });
  }

  toggle.addEventListener('click', function () {
    var opening = panel.hidden;
    panel.hidden = !opening;
    toggle.setAttribute('aria-expanded', String(opening));
    if (opening) input.focus();
  });
  closeBtn.addEventListener('click', function () {
    panel.hidden = true;
    toggle.setAttribute('aria-expanded', 'false');
  });
  form.addEventListener('submit', function (ev) {
    ev.preventDefault();
    var q = input.value.trim();
    if (!q) return;
    input.value = '';
    ask(q);
  });

  // Offline: the toggle stays hidden, no button that only leads to a dead end.
  fetch(endpoint + '/health', { signal: AbortSignal.timeout(4000) })
    .then(function (res) { if (res.ok) toggle.hidden = false; })
    .catch(function () {});
})();
