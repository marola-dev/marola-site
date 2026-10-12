// worker/contact.js against a stub GitHub and a key generated here (#119): the JWT it signs, the
// issue it opens, and every request it must refuse. No network.
import { contact, issue, appJwt } from '../worker/contact.js';

let fails = 0;
function ok(cond, label, detail) {
  console.log((cond ? '  ok   ' : '  FAIL ') + label + (cond || detail === undefined ? '' : ' — ' + detail));
  if (!cond) fails++;
}

const { privateKey, publicKey } = await crypto.subtle.generateKey(
  { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
const pkcs8 = Buffer.from(await crypto.subtle.exportKey('pkcs8', privateKey)).toString('base64');
const PEM = '-----BEGIN PRIVATE KEY-----\n' + pkcs8.match(/.{1,64}/g).join('\n') + '\n-----END PRIVATE KEY-----\n';
const ENV = { GITHUB_APP_ID: '123456', GITHUB_APP_INSTALLATION_ID: '987', GITHUB_APP_PRIVATE_KEY: PEM };
const ORIGIN = 'https://marola.dev';
const fromB64url = s => Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/'), 'base64');

const jwt = await appJwt('123456', PEM, 1_800_000_000);
const [h, p, s] = jwt.split('.');
ok(await crypto.subtle.verify('RSASSA-PKCS1-v1_5', publicKey, fromB64url(s), new TextEncoder().encode(h + '.' + p)),
  'the app JWT verifies against the public key');
const claims = JSON.parse(fromB64url(p));
ok(JSON.parse(fromB64url(h)).alg === 'RS256' && claims.iss === '123456' && claims.iat === 1_800_000_000 - 60 && claims.exp - claims.iat <= 600,
  'the JWT is RS256, issued by the App id, back-dated a minute and under GitHub\'s ten-minute cap', JSON.stringify(claims));

function stubGitHub(opts = {}) {
  const calls = [];
  const http = async (url, init) => {
    calls.push({ url, init, body: init.body ? JSON.parse(init.body) : null });
    if (/access_tokens$/.test(url)) return new Response(JSON.stringify({ token: 'ghs_test' }), { status: opts.tokenStatus || 201 });
    return new Response('{}', { status: opts.issueStatus || 201 });
  };
  return { http, calls };
}
function post(body, headers = {}) {
  return new Request(ORIGIN + '/contact', { method: 'POST', body: typeof body === 'string' ? body : JSON.stringify(body),
    headers: { origin: ORIGIN, 'content-type': 'application/json', ...headers } });
}
const GOOD = { name: 'Ana @someone', email: 'ana@example.org', topic: 'data', lang: 'pt-BR',
  message: 'a nota do Santinho parece alta. cc @h0ffmann #1\n~~~\nfim' };

const gh = stubGitHub();
const sent = await contact(post(GOOD), ENV, gh.http);
ok(sent.status === 201 && (await sent.json()).success === true, 'a good message is accepted');
ok(gh.calls.length === 2 && gh.calls[0].url === 'https://api.github.com/app/installations/987/access_tokens' &&
  /^Bearer /.test(gh.calls[0].init.headers.authorization),
  'it trades the app JWT for an installation token first');
const made = gh.calls[1] || {};
ok(made.url === 'https://api.github.com/repos/marola-dev/contato/issues' && made.init.headers.authorization === 'token ghs_test',
  'then opens the issue in marola-dev/contato with that token');
const outside = (made.body.body || '').replace(/^(~{3,})text\n[\s\S]*?\n\1$/gm, '');
ok(made.body.title === '[data] Ana  someone' && !/@/.test(made.body.title), 'the title names the topic and the sender, with no @', made.body.title);
ok(made.body.body.includes('a nota do Santinho parece alta. cc @h0ffmann #1\n~~~\nfim') && !/@|#1/.test(outside),
  "the visitor's text is kept whole, and every @ or # sits inside a fence that outlasts the text's own ~~~");
ok(made.body.body.includes('ana@example.org') && made.body.body.includes('**language:** pt-BR'), 'the issue carries the email and the language');

const refusals = [
  ['GET', new Request(ORIGIN + '/contact'), 405],
  ['another origin', post(GOOD, { origin: 'https://evil.example' }), 403],
  ['no origin', new Request(ORIGIN + '/contact', { method: 'POST', body: JSON.stringify(GOOD), headers: { 'content-type': 'application/json' } }), 403],
  ['a form-encoded body', post('a=1', { 'content-type': 'application/x-www-form-urlencoded' }), 415],
  ['an oversized body', post({ ...GOOD, message: 'x'.repeat(20000) }), 413],
  ['broken JSON', post('{'), 400],
  ['no message', post({ ...GOOD, message: '  ' }), 422],
  ['a bad email', post({ ...GOOD, email: 'not-an-email' }), 422],
  ['a message over 5000 characters', post({ ...GOOD, message: 'x'.repeat(5001) }), 422]
];
for (const [what, req, status] of refusals) {
  const g = stubGitHub();
  const r = await contact(req, ENV, g.http);
  ok(r.status === status && g.calls.length === 0, 'refuses ' + what + ' with ' + status + ', calling no one', r.status);
}
const bot = stubGitHub();
const botReply = await contact(post({ ...GOOD, botcheck: true }), ENV, bot.http);
ok(botReply.status === 200 && bot.calls.length === 0, 'a filled honeypot looks accepted and opens nothing');
const bare = stubGitHub();
ok((await contact(post(GOOD), {}, bare.http)).status === 503 && bare.calls.length === 0, 'without the App secrets it says 503 and calls no one');
ok((await contact(post(GOOD), ENV, stubGitHub({ tokenStatus: 401 }).http)).status === 502, 'a refused app token is a 502');
ok((await contact(post(GOOD), ENV, stubGitHub({ issueStatus: 404 }).http)).status === 502, 'a refused issue (app not installed on the repo) is a 502');
ok(issue({ name: '', email: 'x@y.z', topic: 'other', lang: 'en', message: 'hi' }).title === '[other] x y.z', 'no name: the title falls back to the email, its @ dropped');

if (fails) { console.error('worker_check: ' + fails + ' failure(s)'); process.exit(1); }
console.log('worker_check: ok');
