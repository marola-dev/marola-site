# Sic Mundus Creatus Est

2026-10-09

marola is live, open-source and non-profit. It is a map of the beaches of Florianópolis, Rio de Janeiro and Salvador, with a score for today and tomorrow built from public data only. The latest version, 0.2.1, came out on October 8.

::: release v0.2.1 2026-10-08
- three new authors in marola's citation: Elisa Oliveira, Leonardo Ramos Almeida and Pablo Ribeiro ([#712](https://github.com/marola-dev/marola/pull/712), [#714](https://github.com/marola-dev/marola/pull/714))
- AI agent skills now have fixed versions, updated every week ([MIP-0080](https://github.com/marola-dev/marola/pull/701))
- a proposal to evaluate external language models without tying marola to one vendor ([MIP-0081](https://github.com/marola-dev/marola/pull/704))
[release notes](https://github.com/marola-dev/marola/releases/tag/v0.2.1) · [changes since 0.2.0](https://github.com/marola-dev/marola/compare/v0.2.0...v0.2.1)

## Official links

- The map: [marola.dev](https://marola.dev/)
- The documentation: [docs.marola.dev](https://docs.marola.dev/)
- The code, MIT-licensed: [github.com/marola-dev](https://github.com/marola-dev)
- To cite it: [10.5281/zenodo.23224155](https://doi.org/10.5281/zenodo.23224155), on Zenodo. This DOI always resolves to the latest version, today [0.2.1](https://github.com/marola-dev/marola/releases/tag/v0.2.1). The [README](https://github.com/marola-dev/marola#how-to-cite) has the ABNT, APA and BibTeX entries.
- marola's language model, marola-sea: trained in [marola-ml](https://github.com/marola-dev/marola-ml), so far only as a small test version
- Open conversations: [GitHub Discussions](https://github.com/marola-dev/marola/discussions)

## What marola is and what it is not

The score combines sea state, wind, waves, tide and the official bathing-water verdict from the state environmental agencies of Santa Catarina (IMA), Rio de Janeiro (INEA) and Bahia (INEMA). Anything that could put someone at risk is decided by simple rules anyone can read. The AI only writes the summary and never changes a score. There are no cookies, no tracking of our own and no accounts.

marola is not a lifeguard, not an official forecast and not an alerting service. In an emergency, the map's emergency button lists Brazil's free emergency numbers, such as 193 for the fire brigade and lifeguards.

## How the site runs

The map is static: no server of ours and no AI runs when you open the page. Every 3 hours, a GitHub workflow runs marola-app, scores every beach and publishes the files. marola.dev is served by a [Cloudflare Worker](https://github.com/marola-dev/marola-site/blob/main/docs/3-development.md), a small program on Cloudflare's network, on the [free plan](https://github.com/marola-dev/marola-site/blob/main/AGENTS.md#cost--deployment-safety-hard-rule), with GitHub Pages as a fallback. INEA and INEMA only answer Brazilian addresses, so the workflow goes through a proxy: a computer in Brazil, run by volunteers, that relays the requests.

The data should move to Cloudflare R2, a file-storage service, in a data lake that is still being built (more on that below).

## The repositories

Each part of marola is its own repository in the [marola-dev](https://github.com/marola-dev) organization, with its own tests and releases. No part uses another's code directly: it always uses a published release of it.

### [marola](https://github.com/marola-dev/marola)

The main repository, which ties the others together. It holds the plan for each change (the MIPs, marola's change proposals), the phase list, the ways of working and the documentation site. The citable release comes from here.

### [marola-app](https://github.com/marola-dev/marola-app)

The main program, in Scala 3 with [Kyo](https://getkyo.io/). It fetches beaches from OpenStreetMap, sea and weather from Open-Meteo, and the bathing-water bulletins, computes the score, applies the safety veto, and ships a command-line tool and an MCP server that lets AI assistants query marola. The Docker image it publishes is what builds the map.

### [marola-site](https://github.com/marola-dev/marola-site)

The map at marola.dev, on a Mapbox base map. Plain JavaScript with no framework, in Portuguese and English.

### [marola-oods](https://github.com/marola-dev/marola-oods)

The Open Ocean Data Store: it will hold the structure of the open data lake of beaches and bathing-water samples. It holds no data yet.

### [marola-ml](https://github.com/marola-dev/marola-ml)

The Python code that never runs on the map: it compiles the prompts with DSPy, keeps the quality gate a model must pass before it is used, and trains marola-sea.

### [marola-corpus](https://github.com/marola-dev/marola-corpus)

The notes about the sea that marola answers from, each with its source.

### [marola-devkit](https://github.com/marola-dev/marola-devkit)

The toolbox every repository uses: scripts, git hooks, skills for AI agents and the shared continuous integration.

### [agent-skills](https://github.com/marola-dev/agent-skills)

The catalog of the AI agent skills used across marola: where each one lives, where it came from and what has been tested.

The organization also keeps [awesome-ocean-science](https://github.com/marola-dev/awesome-ocean-science), a list of open ocean software, data and tools.

## What we're building now: the data lake

Today every map update fetches beaches and water quality from scratch, and the history is lost. [MIP-0075](https://github.com/marola-dev/marola/blob/main/docs/MIPs/MIP-0075-water-quality-store-r2.md) proposes keeping it all in an open data lake: a [DuckLake](https://ducklake.select/), Parquet files plus a DuckDB catalog. The MIP was written for Backblaze B2, and [marola#692](https://github.com/marola-dev/marola/pull/692) proposes moving it to Cloudflare R2. Weekly jobs in marola-app will write to the lake, and marola-oods defines its structure. Beaches will come first, then Santa Catarina's water quality, then Rio's and Bahia's.

The structure ([marola-oods#22](https://github.com/marola-dev/marola-oods/pull/22)) and the move to R2 are in review. The lake has not received any data yet.

The next post explains why marola needs a lake.

## A partnership with Leave No Trace

[Leave No Trace](https://lnt.org/), the non-profit that teaches people to enjoy the outdoors without leaving a trace, has accepted marola into its Community Partnership Program.

The program opens Leave No Trace's educational resources to partners and lets certified instructors issue course certificates. A later post will cover what this changes for marola ([#96](https://github.com/marola-dev/marola-site/issues/96)).

marola stays open to non-financial partnerships with environmental institutions and with anyone who can share data or computing time ([about](about.html)).

## How to follow or help

Use the map and tell us when it is wrong. Open an [issue](https://github.com/marola-dev/marola/issues), in Portuguese or English, or pick one labeled [good first issue](https://github.com/search?q=org%3Amarola-dev+is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22&type=issues). You can also [support the project](support.html).
