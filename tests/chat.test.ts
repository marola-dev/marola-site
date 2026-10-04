import assert from 'node:assert/strict';
import { test } from 'node:test';
import { setImmediate as tick } from 'node:timers/promises';
import vm from 'node:vm';
import { bundle, El } from './harness.ts';

class ChatEl extends El {
  focused = false;
  removed = false;
  scrollTop = 0;
  scrollHeight = 0;
  focus(): void {
    this.focused = true;
  }
  remove(): void {
    this.removed = true;
  }
}

type Reply = { ok: boolean; answer?: unknown } | 'down';

async function runChat(endpoint: string, health: Reply, ask: Reply = { ok: true, answer: 'nade perto do salva-vidas' }) {
  const ids = ['chat-toggle', 'chat-panel', 'chat-close', 'chat-log', 'chat-offline', 'chat-form', 'chat-input'];
  const els = Object.fromEntries(ids.map((id) => [id, new ChatEl(id)]));
  const el = (id: string): ChatEl => els[id] ?? new ChatEl(id);
  el('chat-toggle').hidden = true;
  el('chat-panel').hidden = true;
  el('chat-offline').hidden = true;
  const posted: unknown[] = [];
  const answer = (r: Reply) => (r === 'down' ? Promise.reject(new Error('down')) : Promise.resolve({ ok: r.ok, json: () => Promise.resolve({ answer: r.answer }) }));
  const sandbox: Record<string, unknown> = {
    document: { getElementById: (id: string) => els[id] ?? null, createElement: () => new ChatEl('p') },
    fetch: (url: string, init?: { body?: string }) => {
      if (url.endsWith('/ask')) posted.push([url, JSON.parse(init?.body ?? '{}')]);
      return answer(url.endsWith('/health') ? health : ask);
    },
    AbortSignal: { timeout: () => undefined },
    MAROLA_CHAT_ENDPOINT: endpoint,
  };
  sandbox.window = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(bundle('chat'), sandbox);
  for (let i = 0; i < 5; i++) await tick();
  return { el, posted, said: () => el('chat-log').children.filter((c) => !(c as ChatEl).removed).map((c) => [c.className, c.textContent]) };
}

test('no endpoint, or one that fails /health, keeps the chat out of sight', async () => {
  assert.equal((await runChat('', { ok: true })).el('chat-toggle').hidden, true);
  assert.equal((await runChat('https://chat.test', { ok: false })).el('chat-toggle').hidden, true);
  assert.equal((await runChat('https://chat.test', 'down')).el('chat-toggle').hidden, true);
});

test('the toggle opens and closes the panel, and opening focuses the question', async () => {
  const c = await runChat('https://chat.test/', { ok: true });
  assert.equal(c.el('chat-toggle').hidden, false);
  c.el('chat-toggle').click();
  assert.equal(c.el('chat-panel').hidden, false);
  assert.equal(c.el('chat-toggle').getAttribute('aria-expanded'), 'true');
  assert.ok(c.el('chat-input').focused);
  c.el('chat-toggle').click();
  assert.equal(c.el('chat-panel').hidden, true);
  c.el('chat-toggle').click();
  c.el('chat-close').click();
  assert.equal(c.el('chat-panel').hidden, true);
  assert.equal(c.el('chat-toggle').getAttribute('aria-expanded'), 'false');
});

test('a question is posted once, trimmed, and its answer shown as text', async () => {
  const c = await runChat('https://chat.test/', { ok: true });
  c.el('chat-input').value = '   ';
  c.el('chat-form').fire('submit');
  c.el('chat-input').value = '  o que é corrente de retorno? ';
  c.el('chat-form').fire('submit');
  for (let i = 0; i < 5; i++) await tick();
  assert.deepEqual(JSON.parse(JSON.stringify(c.posted)), [['https://chat.test/ask', { question: 'o que é corrente de retorno?' }]]);
  assert.deepEqual(c.said(), [
    ['chat-msg user', 'o que é corrente de retorno?'],
    ['chat-msg assistant', 'nade perto do salva-vidas'],
  ]);
  assert.equal(c.el('chat-input').value, '');
});

test('a failed or malformed answer shows the offline note, not a pending dot', async () => {
  for (const ask of ['down', { ok: false, answer: 'x' }, { ok: true, answer: 42 }] as const) {
    const c = await runChat('https://chat.test', { ok: true }, ask);
    c.el('chat-input').value = 'oi';
    c.el('chat-form').fire('submit');
    for (let i = 0; i < 5; i++) await tick();
    assert.equal(c.el('chat-offline').hidden, false, JSON.stringify(ask));
    assert.deepEqual(c.said(), [['chat-msg user', 'oi']]);
  }
});
