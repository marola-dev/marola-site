# Members

The people who build marola. This file is the source of truth for the list: the members page on
[marola.dev](https://marola.dev/members.html) is generated from it. Every creator of the
[Zenodo record](https://doi.org/10.5281/zenodo.23224155) is listed here; a member who is not on
the record has no ORCID here.

The list is in the order of each member's first commit in a marola-dev repository; members with
no commit yet follow, in the Zenodo record's order.

| Name | Affiliation | ORCID | GitHub | First commit | marola role | GitHub role |
|---|---|---|---|---|---|---|
| Hoffmann, Matheus | Universidade Federal do Rio de Janeiro | [0009-0009-1056-7661](https://orcid.org/0009-0009-1056-7661) | [h0ffmann](https://github.com/h0ffmann) | [2026-09-05](https://github.com/marola-dev/marola/commit/45f5628bc51e392a292d4f186347bf51f679ecdd) | contributor | owner |
| Macedo, William Barbosa | Universidade Federal do Rio de Janeiro | | [wbm99](https://github.com/wbm99) | [2026-09-12](https://github.com/marola-dev/marola-devkit/commit/6ae3f572363d5e213bf50ed4834f35c2400937f1) | contributor | contributor |
| Valério, Bruno | | [0009-0002-9778-953X](https://orcid.org/0009-0002-9778-953X) | [brunogbv](https://github.com/brunogbv) | [2026-09-27](https://github.com/marola-dev/marola/commit/26b4c398bd25a78562e7e99eff746107d797c450) | contributor | owner |
| Ribeiro, Pablo | | [0009-0005-3553-8323](https://orcid.org/0009-0005-3553-8323) | [Bleenho](https://github.com/Bleenho) | [2026-09-29](https://github.com/marola-dev/marola/commit/0f10a2f9a6fcb38fdc721ece86c62df65fc4a251) | contributor | |
| Soares da Silva Junior, Rob Kler | | [0009-0003-3102-4996](https://orcid.org/0009-0003-3102-4996) | [robkler](https://github.com/robkler) | [2026-09-29](https://github.com/marola-dev/marola/commit/23bc93cc6ea3aff98fc2bd547310dbddea17228c) | contributor | owner |
| Oliveira, Elisa | | [0009-0002-9844-7865](https://orcid.org/0009-0002-9844-7865) | [elisaoliver5](https://github.com/elisaoliver5) | | ui / mkt | |
| Almeida, Leonardo Ramos | Universidade Federal do Rio de Janeiro | [0009-0004-8570-4601](https://orcid.org/0009-0004-8570-4601) | [aracyla](https://github.com/aracyla) | | contributor | owner |
| Kuniyoshi, Tiago Shin-Iti | | [0009-0004-3742-2861](https://orcid.org/0009-0004-3742-2861) | | | contributor | contributor |

## Adding or changing a member

**Hard rule** (Hoffmann, 2026-10-25): this list reflects the organization's
[people page](https://github.com/orgs/marola-dev/people). Whoever is added to, removed from or
given another role in the organization gets the same change here.

One row per person, in a pull request to this repo, placed by first commit. `Name` is
`Family, Given`, as Zenodo writes it; `ORCID` and `GitHub` are links, or empty; `First commit` is
the commit's UTC date linking to it, or empty. `marola role` is the person's role in marola,
never empty (`contributor` unless the owner gives another); `GitHub role` is the role in the
`marola-dev` organization on GitHub (`owner` or `member`), `contributor` for a person who
contributes without a role in the organization, or empty. Adding a creator of the
Zenodo record goes with the same change to `.zenodo.json` in [marola-dev/marola](https://github.com/marola-dev/marola), so
the next release credits them. marola-site's `members.yml` opens a PR with the updated page the
next day.
