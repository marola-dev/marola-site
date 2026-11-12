title: privacy
description: What marola stores about authors and visitors, what it does not store, why, for how long, who can see it and what you can do.

## Privacy

This page says what marola stores when you use the study pages, the contact form and the map. It describes what the project does today. It is not legal advice. The board has not yet approved a final legal text for it.

## What marola stores

- **Your GitHub account.** When you log in to publish a study, marola stores your GitHub numeric id, your login and the date you made the GitHub account. It reads only your public profile.
- **Your studies.** The text you typed (title, authors, abstract, area, topic, links, licence, the statement about AI), the PDF file, its SHA-256 hash and the dates. The study is public at once, with your GitHub login.
- **API keys.** Only a hash of each key, and the dates. The key itself is shown once and is not kept.
- **Sessions.** Only a hash of the session, for 12 hours. A cookie holds the session while you are logged in. A second short cookie lives for 10 minutes during the login. There is no tracking cookie.
- **Reports.** When someone reports a study: the study, the time and the reason they wrote. No name, no address and no account.
- **The contact form.** The name, the email address and the message you type there.

## What marola does not store

- Your email address from GitHub. marola does not ask for it and never sees it.
- Your IP address. The server log holds no address.
- Your GitHub token. It is used once, on the server, and dropped.
- A browser fingerprint, or any profile of what you read.

## Why

To show who published a study, to keep a public record of what was published and when, to stop spam (the age of the GitHub account and the limits count what is in the database) and to let the board hide a study that does harm.

## For how long

- Account data: until you delete the account.
- Sessions: 12 hours. Keys: until you revoke them or delete the account.
- A published study: until you withdraw it or the board hides it. After that the row stays as a tombstone, with its hash, its date and the reason. It is the public record of what was published.
- Contact messages: until the board has answered and deletes them.
- Reports: they stay with the study row until the board closes them. The board decides when to delete old ones.

## Who can see it

Everyone sees a public study with your GitHub login and the dates. Everyone sees a tombstone (id, hash, date, reason). The people of the board see the rest on the server: the reports and the contact messages. GitHub knows that you logged in to marola. The base map on the map page is OpenFreeMap's.

## What you can do

- **Delete your account** at [your account page](/account). It deletes your keys, your sessions and your account. Your studies go offline at once and stay as tombstones with the hash and the reason "account deleted by the author". The rows and the files stay on the server and are not served. To have the files deleted as well, ask the board. That is the board's decision. The tombstone stays in any case.
- **Withdraw a study** at the same page.
- **Ask for removal** of a study or of your name from a study: see [takedown](/takedown.html).
- **Ask what marola holds about you**, or ask for a correction, with the [contact form](/contact.html).
