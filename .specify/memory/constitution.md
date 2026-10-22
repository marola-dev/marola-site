# marola-site constitution

The rules every spec under `specs/` is checked against in its plan's "Constitution Check". Each
one restates a rule that already exists, and the pointed-to rule wins on any difference. A spec
here is design input; it does not replace a MIP where one is required (MIP-0063 §4.7).

## I. Org invariants (AGENTS.md, MIP-0070 §5.1)

1. **Cost and deployment safety.** Nothing provisions or deploys a paid resource without a
   person's explicit confirmation. `site.yml` deploys to GitHub Pages on its own schedule; an
   agent never triggers a deploy by hand.
2. **No secrets in code.** Keys reach CI as secrets or variables, never in the page.
3. **The agent-ready gate.** Implementation starts only on an issue labelled `agent-ready`. A
   spec, plan or task list is design, not implementation.
4. **Commit trailers.** `Tested:`, `Cost:`, `Co-Authored-By: Claude <noreply@anthropic.com>`, and
   `MIP:` on any commit touching `site/static/**`.
5. **Phase discipline.** `docs/PHASES.md` in the umbrella.

## II. The page (AGENTS.md "Code style", `docs/1-design.md`)

- Static, plain JavaScript, no framework, no build step. `script-src 'self'`.
- The visitor's browser talks only to marola.dev, Mapbox (base map) and NASA GIBS (on demand).
  Any other data is fetched at build time or by a scheduled workflow, never by the page.
- Portuguese first (MIP-0054); page chrome goes through `site/i18n/`, never `i18n.js` by hand.
- A visible change goes through the `site-frontend` skill, `node scripts/site_check.js` and
  before/after screenshots at 390 px and 1280 px.

## III. Repository boundaries (MIP-0070 §5.4)

- No repo reads another's tree. Data crosses repos as an image, a release asset, a branch
  (`site-data`) or a bucket.
- A failed external fetch never fails a deploy: the page shows the last good data and when it
  was fetched (marola-dev/marola-site#13).

## IV. Data honesty (MIP-0001, the `citizen-science-site` skill)

- An issuer's words are shown as the issuer wrote them, with a link to its own page.
- Anything marola computes about an issuer's data is labelled as marola's, next to the issuer's.
- Sources, freshness and limits are visible on the page.
