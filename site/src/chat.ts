/** The chat widget (MIP-0033 §5.2): hidden unless chatbot-config.js names an endpoint that answers /health. */
const HEALTH_TIMEOUT_MS = 4000;
const ASK_TIMEOUT_MS = 30000;

function start(endpoint: string): void {
  const $ = (id: string): HTMLElement | null => document.getElementById(id);
  const toggle = $('chat-toggle');
  const panel = $('chat-panel');
  const closeBtn = $('chat-close');
  const log = $('chat-log');
  const offline = $('chat-offline');
  const form = $('chat-form');
  const input = $('chat-input') as HTMLInputElement | null;
  if (!toggle || !panel || !closeBtn || !log || !offline || !form || !input) return;

  const say = (cls: string, text: string): HTMLElement => {
    const p = document.createElement('p');
    p.className = `chat-msg ${cls}`;
    p.textContent = text;
    log.appendChild(p);
    log.scrollTop = log.scrollHeight;
    return p;
  };

  const ask = async (question: string): Promise<void> => {
    say('user', question);
    offline.hidden = true;
    const pending = say('assistant pending', '…');
    try {
      const res = await fetch(`${endpoint}/ask`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ question }),
        signal: AbortSignal.timeout(ASK_TIMEOUT_MS),
      });
      const body = (await res.json()) as { answer?: unknown };
      pending.remove();
      if (res.ok && typeof body.answer === 'string') say('assistant', body.answer);
      else offline.hidden = false;
    } catch {
      pending.remove();
      offline.hidden = false;
    }
  };

  const setOpen = (open: boolean): void => {
    panel.hidden = !open;
    toggle.setAttribute('aria-expanded', String(open));
    if (open) input.focus();
  };
  toggle.addEventListener('click', () => { setOpen(panel.hidden !== false); });
  closeBtn.addEventListener('click', () => { setOpen(false); });
  form.addEventListener('submit', (ev) => {
    ev.preventDefault();
    const q = input.value.trim();
    if (!q) return;
    input.value = '';
    void ask(q);
  });

  // Offline, the toggle stays hidden: no button that only leads to a dead end.
  fetch(`${endpoint}/health`, { signal: AbortSignal.timeout(HEALTH_TIMEOUT_MS) })
    .then((res) => {
      if (res.ok) toggle.hidden = false;
    })
    .catch(() => undefined);
}

const endpoint = (window.MAROLA_CHAT_ENDPOINT ?? '').replace(/\/$/, '');
if (endpoint) start(endpoint);
