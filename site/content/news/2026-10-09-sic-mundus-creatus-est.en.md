# Sic Mundus Creatus Est

2026-10-09

marola is live, open and non-profit. It is a map of the beaches of Florianópolis, Rio de Janeiro and Salvador, with a score for today and tomorrow built from public data only. Version 0.2.0 came out on October 7, and it has a DOI.

## Official links

- The map: [marola.dev](https://marola.dev/)
- The documentation: [docs.marola.dev](https://docs.marola.dev/)
- The code, MIT-licensed: [github.com/marola-dev](https://github.com/marola-dev)
- To cite it: [10.5281/zenodo.23224155](https://doi.org/10.5281/zenodo.23224155), on Zenodo. This DOI always resolves to the latest version, today [0.2.0](https://github.com/marola-dev/marola/releases/tag/v0.2.0). The [README](https://github.com/marola-dev/marola#how-to-cite) has the APA, ABNT and BibTeX entries.
- marola's language model, marola-sea: published on Hugging Face from [marola-ml](https://github.com/marola-dev/marola-ml)
- Open conversations: [GitHub Discussions](https://github.com/marola-dev/marola/discussions)

## What it is, and what it is not

The score combines sea state, wind, waves, tide and the official bathing-water verdict from IMA/SC, INEA (RJ) and INEMA (BA). Anything that could put someone at risk is decided by simple rules anyone can read. The AI only writes the summary and never changes a score. There are no cookies, no tracking of our own and no accounts.

marola is not a lifeguard, not an official forecast and not an alerting service. In an emergency, the map's emergency button lists Brazil's free numbers, such as 193 for the fire brigade and lifeguards.

## How the site runs

The map is static: no server of ours and no AI runs when you open the page. Every 3 hours, a GitHub workflow runs the marola-app image, scores every beach and publishes the files. marola.dev is served by a [Cloudflare Worker](https://github.com/marola-dev/marola-site/blob/main/docs/3-development.md) on the free plan, with GitHub Pages as a fallback. INEA and INEMA only answer Brazilian addresses, so the workflow goes through a proxy in Brazil run by volunteers.

The data will live on Cloudflare R2, in a data lake that is still being built (more on that below).

## The repositories

Each part of marola is its own repository in the [marola-dev](https://github.com/marola-dev) organisation, with its own tests and releases. No part uses another's code directly: it pins a published version.

### [marola](https://github.com/marola-dev/marola)

The umbrella. It holds the plan for each change (the MIPs), the phase list, the ways of working and the documentation site. The citable Zenodo release comes from here.

### [marola-app](https://github.com/marola-dev/marola-app)

The product, in Scala 3 with [Kyo](https://getkyo.io/). It fetches beaches from OpenStreetMap, sea and weather from Open-Meteo, and the bathing-water bulletins, computes the score and its safety veto, and ships a command-line tool and an MCP server. The Docker image it publishes is what builds the map.

### [marola-site](https://github.com/marola-dev/marola-site)

The map at marola.dev, on Mapbox. Plain JavaScript with no framework, in Portuguese and English.

### [marola-oods](https://github.com/marola-dev/marola-oods)

The Open Ocean Data Store: the schema of the open data lake of beaches and bathing-water samples. It holds no data yet.

### [marola-ml](https://github.com/marola-dev/marola-ml)

The Python that runs away from the map: it compiles the prompts with DSPy, keeps the quality gate a model must pass before it is used, and trains marola-sea.

### [marola-corpus](https://github.com/marola-dev/marola-corpus)

The notes about the sea that marola answers from, each with its source.

### [marola-devkit](https://github.com/marola-dev/marola-devkit)

The toolbox every repository uses: scripts, git hooks, skills for AI agents and the shared continuous integration.

### [agent-skills](https://github.com/marola-dev/agent-skills)

The catalogue of the AI agent skills used across marola: where each one lives, where it came from and what has been tested.

The organisation also keeps [awesome-ocean-science](https://github.com/marola-dev/awesome-ocean-science), a list of open ocean software, data and tools.

## The big effort now: the data lake

Today every map update fetches beaches and water quality from scratch, and the history is lost. [MIP-0075](https://github.com/marola-dev/marola/blob/main/docs/MIPs/MIP-0075-water-quality-store-r2.md) keeps it all in an open data lake: a [DuckLake](https://ducklake.select/), Parquet files plus a DuckDB catalog, in a Cloudflare R2 bucket. Weekly jobs in marola-app write to it, and marola-oods owns the schema. Beaches come first, then Santa Catarina's water quality, then Rio's and Bahia's.

The schema ([marola-oods#22](https://github.com/marola-dev/marola-oods/pull/22)) and the move to R2 ([marola#692](https://github.com/marola-dev/marola/pull/692)) are in review. The lake has not received any data yet.

The next post explains why marola needs a lake.

## A partnership with Leave No Trace

[Leave No Trace](https://lnt.org/), the non-profit that teaches people to enjoy the outdoors without leaving a trace, has accepted marola into its Community Partnership Program. Their team saw in marola open coastal-safety and bathing-water data for the people who go to the beaches of Florianópolis, Rio de Janeiro and Salvador, and found Leave No Trace's message a natural fit for it.

The program opens Leave No Trace's educational resources to partners and lets certified instructors issue course certificates. What this will change on marola comes in a later post ([#96](https://github.com/marola-dev/marola-site/issues/96)).

marola stays open to partnerships without money with environmental institutions and with anyone who can share data or computing ([about](about.html)).

## How to follow or help

Use the map and tell us when it is wrong. Open an [issue](https://github.com/marola-dev/marola/issues), in Portuguese or English, or pick one labelled [good first issue](https://github.com/search?q=org%3Amarola-dev+is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22&type=issues). You can also [support the project](support.html).
