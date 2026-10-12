# FORM.md: what the contact form is for

The decisions behind `contact.html` (#119, #120). Each one says what the page does today and the
options; a maintainer picks, and the page follows this file. Provider facts carry `(v)` when they
were checked against Web3Forms' docs on 2026-10-12, and `⚠` when they were not.

## 1. Who writes, and why

**Today:** anyone who wants to reach marola without a GitHub account: a beachgoer, a lifeguard, a
researcher, an agency, a journalist. GitHub issues stay the public route, linked from the page.

**Decide:** is the form only for contact, or also a citizen-science channel (a sighting, a score
that looks wrong at a given beach and hour)? A channel for data needs more fields (section 3) and a
place where those reports end up besides an inbox.

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
| email | yes | the only way to answer; Web3Forms uses it as the reply-to |
| topic | yes (a picker) | becomes the email's subject |
| message | yes, up to 5000 characters | the point |
| the page's language | sent, not shown | to answer in pt-BR or English |

**Options:** a beach and an hour (for data reports); a city; a "may we quote you publicly?"
checkbox; a photo (Web3Forms' file attachments are a Pro feature (v)). Every field added is data
someone has to look after (section 7), so the default is to add none.

## 4. Topics

**Today:** dúvida / a question, dado errado ou praia faltando / wrong data or a missing beach,
parceria / partnership, imprensa / press, outro / something else.

**Options:** add "voluntariado / volunteering" (a Brazilian proxy node, #4, or the beach lists),
"um avistamento / a sighting" (jellyfish, the corpus), or "ser membro / joining" (members.html).

## 5. Where the messages go

**Today:** the inbox that owns the Web3Forms access key. Nobody has created that key yet, so the
form says "not connected" and points to a GitHub issue.

**Decide:**

- Which address receives them: a personal inbox, or a project one such as `contato@marola.dev`
  (Cloudflare Email Routing can forward an address on marola.dev for free ⚠; setting it up is a
  person's act, in the Cloudflare account).
- Who answers, and whether the page promises a time ("respondemos em até uma semana").
- Whether a message also lands somewhere shared (a GitHub issue, a Telegram chat). Web3Forms'
  webhooks are a Pro feature (v).

## 6. Provider

**Today:** [Web3Forms](https://web3forms.com). It forwards each message by email and keeps no copy
of it (v, FAQ); its access key is public by design (v, FAQ), so it lives in the repo variable
`WEB3FORMS_ACCESS_KEY` only for tidiness. The page talks to `api.web3forms.com` with `fetch`; no
provider script or iframe loads.

**Free plan:** the monthly message limit is not in the docs read on 2026-10-12, and the pricing
page could not be fetched ⚠; check it when signing up. Pro-only (v): reCaptcha and Turnstile, CC,
autoresponder, file attachments, webhooks, restricting the key to marola.dev.

**Alternatives, if Web3Forms stops fitting:**

| Provider | Trade-off |
|---|---|
| Formspree | a dashboard that keeps submissions; a smaller free tier ⚠ |
| Google Forms | free and familiar, but an iframe or a link to Google, which tracks; breaks "no tracking" |
| A Cloudflare Worker sending email | no third party at all, the Worker already serves marola.dev; needs a script in `wrangler.jsonc` and a mail route, more code to own |

Changing provider is a change to `contact.js`, `contact_config.sh`, the page's CSP and this file.

## 7. Spam

**Today:** a hidden checkbox (honeypot) that only a bot ticks; a ticked one is dropped in the page
and never sent. Web3Forms calls its own honeypot deprecated and recommends a captcha (v).

**Options:**

- Keep the honeypot and see how much spam arrives once the key is live. This is the default.
- hCaptcha, listed in Web3Forms' free spam protection (v): it loads a script from hCaptcha's
  servers, so the page's `script-src 'self'` would need an exception, and a third party sees each
  visitor of `contact.html`.
- Restrict the key to marola.dev: Pro (v).

## 8. Privacy line

**Today, under the form:** "o envio passa pelo Web3Forms, que repassa a mensagem por e-mail e não
guarda uma cópia. seu e-mail serve só para a resposta." (and the English twin).

**Decide:** how long messages stay in the inbox and who can read them, and whether the line says
so; and that a person can ask for their message to be deleted (LGPD). The about page's privacy
section should mention the form once it is live.

## 9. After sending

**Today:** the page says the message was sent and clears the form; on an error it keeps the text
and suggests a GitHub issue.

**Options:** an automatic reply email to the sender (Pro (v)); a link to the docs or the news page
after sending.
