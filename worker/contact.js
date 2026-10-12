// marola.dev's one Worker route (#119): the contact form's POST /contact becomes an issue in the
// private repo marola-dev/contato, opened as the marola-dev GitHub App. Everything else is the
// static site (wrangler.jsonc's run_worker_first sends only /contact here).
const REPO = 'marola-dev/contato';
const TOPICS = ['question', 'data', 'partnership', 'press', 'other'];
const MAX_BODY = 16 * 1024;
const LIMITS = { name: 120, email: 200, message: 5000 };

export default {
  async fetch(request, env) {
    if (new URL(request.url).pathname !== '/contact') return env.ASSETS.fetch(request);
    return contact(request, env, fetch);
  }
};

function reply(status, error) {
  return new Response(JSON.stringify(error ? { success: false, error } : { success: true }), {
    status, headers: { 'content-type': 'application/json', 'cache-control': 'no-store' }
  });
}

export async function contact(request, env, http) {
  if (request.method !== 'POST') return reply(405, 'method');
  // The page posts same-origin; anything else is someone else's form or a script.
  if (request.headers.get('origin') !== new URL(request.url).origin) return reply(403, 'origin');
  if (!/^application\/json\b/.test(request.headers.get('content-type') || '')) return reply(415, 'type');
  const raw = await request.text();
  if (raw.length > MAX_BODY) return reply(413, 'size');
  let msg;
  try { msg = JSON.parse(raw); } catch { return reply(400, 'json'); }
  if (!msg || typeof msg !== 'object') return reply(400, 'json');
  if (msg.botcheck) return reply(200);
  const field = k => (typeof msg[k] === 'string' ? msg[k].trim() : '');
  const name = field('name'), email = field('email'), message = field('message');
  const topic = TOPICS.includes(msg.topic) ? msg.topic : 'other';
  const lang = msg.lang === 'en' ? 'en' : 'pt-BR';
  if (!message || message.length > LIMITS.message || name.length > LIMITS.name ||
      email.length > LIMITS.email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return reply(422, 'invalid');
  if (!env.GITHUB_APP_ID || !env.GITHUB_APP_INSTALLATION_ID || !env.GITHUB_APP_PRIVATE_KEY) return reply(503, 'unconfigured');

  try {
    const token = await installationToken(env, http);
    const r = await http(`https://api.github.com/repos/${REPO}/issues`, {
      method: 'POST',
      headers: gh(`token ${token}`),
      body: JSON.stringify(issue({ name, email, topic, lang, message }))
    });
    if (!r.ok) return reply(502, 'github');
  } catch {
    return reply(502, 'github');
  }
  return reply(201);
}

function gh(auth) {
  return { authorization: auth, accept: 'application/vnd.github+json', 'user-agent': 'marola.dev-contact',
    'x-github-api-version': '2022-11-28', 'content-type': 'application/json' };
}

// The visitor's text sits in fences, where an @mention or a #123 links nothing and pings no one.
function fence(text) {
  const longest = Math.max(2, ...(text.match(/~+/g) || []).map(t => t.length));
  const f = '~'.repeat(longest + 1);
  return `${f}text\n${text}\n${f}`;
}

export function issue({ name, email, topic, lang, message }) {
  const who = (name || email).replace(/[\r\n@#]/g, ' ').slice(0, 60);
  return {
    title: `[${topic}] ${who}`,
    body: [`**topic:** ${topic} · **language:** ${lang}`, '', '**name:**', fence(name || '-'), '**email:**', fence(email),
      '**message:**', fence(message), '', '_sent from marola.dev/contact.html; answer by email, not here._'].join('\n')
  };
}

function b64url(bytes) {
  let s = '';
  for (const b of new Uint8Array(bytes)) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

// A GitHub App signs a 10-minute RS256 JWT with its private key (PKCS#8 PEM, which WebCrypto reads)
// and trades it for an installation token scoped to the repos it is installed on.
export async function appJwt(appId, pem, now = Math.floor(Date.now() / 1000)) {
  const der = Uint8Array.from(atob(pem.replace(/-----[^-]+-----|\s/g, '')), c => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const enc = o => b64url(new TextEncoder().encode(JSON.stringify(o)));
  const unsigned = enc({ alg: 'RS256', typ: 'JWT' }) + '.' + enc({ iat: now - 60, exp: now + 540, iss: String(appId) });
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(unsigned));
  return unsigned + '.' + b64url(sig);
}

async function installationToken(env, http) {
  const jwt = await appJwt(env.GITHUB_APP_ID, env.GITHUB_APP_PRIVATE_KEY);
  const r = await http(`https://api.github.com/app/installations/${env.GITHUB_APP_INSTALLATION_ID}/access_tokens`, {
    method: 'POST', headers: gh(`Bearer ${jwt}`)
  });
  if (!r.ok) throw new Error('installation token: ' + r.status);
  return (await r.json()).token;
}
