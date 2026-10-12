# FORM.md: what the contact form is for

The decisions behind `contact.html` (#119, #120). Each one says what the page does today and the
options; a maintainer picks, and the page follows this file. Facts about a third-party service
carry `(v)` when they were checked against its docs on 2026-10-12, and `⚠` when they were not.

## 1. Who writes, and why

**Today:** anyone who wants to reach marola without a GitHub account: a beachgoer, a lifeguard, a
researcher, an agency, a journalist. Public GitHub issues stay the open route, linked from the page.

**Decide:** is the form only for contact, or also a citizen-science channel (a sighting, a score
that looks wrong at a given beach and hour)? A channel for data needs more fields (section 3) and a
way to move a report from the private repo to a public issue once it is checked.

## 2. Where the button lives

**Today:** "contato" in the nav on every page (it replaced "contato (em breve)", so the item count
for #114 is unchanged), and a "fale com a gente" button at the end of about.html's "como ajudar".

**Options:** also in the footer, next to the socials (#117); also on the map, in a beach's card ("is
this score wrong?"), which pre-fills the beach and the hour.

## 3. Fields

**Today:**

| Field | Required | Why |
|---|---|---|
| name | no | to greet the person |
| email | yes | the only way to answer |
| topic | yes (a picker) | the issue title's prefix |
| message | yes, up to 5000 characters | the point |
| the page's language | sent, not shown | to answer in pt-BR or English |

**Options:** a beach and an hour (for data reports); a city; a "may we quote you publicly?"
checkbox; a photo (an issue can hold one, but the Worker would have to upload it). Every field
added is data someone has to look after (section 8), so the default is to add none.

## 4. Topics

**Today:** dúvida / a question, dado errado ou praia faltando / wrong data or a missing beach,
parceria / partnership, imprensa / press, outro / something else. The Worker accepts only these
five ids (`question`, `data`, `partnership`, `press`, `other`).

**Options:** add "voluntariado / volunteering" (a Brazilian proxy node, #4, or the beach lists),
"um avistamento / a sighting" (jellyfish, the corpus), or "ser membro / joining" (members.html).
A new topic is a string in `site/i18n/`, an `<option>` and an id in `worker/contact.js`.

## 5. Where the messages go

**Today:** each message is an issue in the private repo
[marola-dev/contato](https://github.com/marola-dev/contato), titled `[topic] name`, with the name,
email, language and message in the body. The visitor's text sits in code fences, so an `@mention`
or a `#123` in it pings or links nothing. The repo is private because every issue carries an email.

**Decide:**

- Who watches `marola-dev/contato` (GitHub emails a watcher on each new issue) and who answers.
- Whether the page promises a time ("respondemos em até uma semana").
- Labels per topic: the App can only set labels that already exist in the repo ⚠, so create them
  there first if wanted, and the Worker adds them.

## 6. How it is sent

**Today:** the page posts to `/contact` on marola.dev. The Cloudflare Worker that serves the site
runs `worker/contact.js` for that one path (`wrangler.jsonc`'s `run_worker_first`); every other
path is still a static file. The script signs in as a GitHub App on marola-dev, which has only
Issues read and write and is installed only on `marola-dev/contato`, and opens the issue. Its three
secrets (`GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID`, `GITHUB_APP_PRIVATE_KEY` in PKCS#8) live
in the Worker's settings in Cloudflare, never in the repo.

No third-party origin is added to the page, and nothing is fetched until the visitor presses send.
The script only runs on a send, well inside the Workers free plan ⚠ (check the daily request
quota in the Cloudflare dashboard). Without the secrets, and on the GitHub Pages fallback (which
has no Worker), the form says it could not send and points to a GitHub issue.

**Alternatives:**

| Option | Trade-off |
|---|---|
| Web3Forms (the first version of #120) | no code to own, mail instead of issues; a third-party origin, free-plan limits not published ⚠ |
| Formspree | a dashboard that keeps submissions; a third party and a small free tier ⚠ |
| Google Forms | free and familiar, but a link or iframe to Google, which tracks; breaks "no tracking" |

## 7. Spam

**Today:** three gates in the Worker and one in the page. The Worker refuses a post from another
origin, a body over 16 KB, a missing or malformed email, an empty message or one over 5000
characters. The page has a hidden checkbox (honeypot) that only a bot ticks; a ticked one is
dropped and looks sent. A bot that posts straight to `/contact` with the right `Origin` header
still gets through.

**Options:**

- Keep it as is and see how much spam arrives. This is the default.
- Cloudflare Turnstile: free, a challenge most people never see ⚠. It loads a script from
  `challenges.cloudflare.com`, so the page's `script-src 'self'` would need an exception, and the
  Worker would check the token with the secret.
- A per-address rate limit on the Worker (Cloudflare's Rate Limiting binding ⚠).

## 8. Privacy line

**Today, under the form:** "a mensagem vira uma issue num repositório privado do marola no GitHub,
que só a equipe lê. seu e-mail serve só para a resposta." (and the English twin).

**Decide:** how long issues stay in `marola-dev/contato` and who can read them (everyone with
access to the private repo), whether the line says so, and that a person can ask for their message
to be deleted (LGPD): deleting an issue takes a repo admin. The about page's privacy section
should mention the form once it is live.

## 9. After sending

**Today:** the page says the message was sent and clears the form; on an error it keeps the text
and suggests a GitHub issue. The answer is an email a person writes; nothing is sent to the
visitor automatically.

**Options:** a link to the docs or the news page after sending; an automatic confirmation email,
which would need a mail service the Worker can call (Cloudflare Email Routing only forwards
mail to addresses verified in the account ⚠).
