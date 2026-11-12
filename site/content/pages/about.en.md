title: about marola
description: What marola is, why it is open and non-profit, how it works inside and where the data comes from.

## What marola is

::lede Picture a friend who knows the sea well. You ask "can I swim tomorrow? when?", and they check the waves, the wind, the tide, whether the water is fit for swimming and even whether there are jellyfish around. Then they tell you the best hour, and why.

That friend is marola. Today it is a map of the beaches of Florianópolis, Rio de Janeiro and Salvador, each with a score for today and tomorrow. It never makes things up: every number comes from public data, and anything that could put you at risk is decided by simple rules anyone can read. When it does not know, it says "no data".

## Why open and non-profit

Much of Brazil's ocean data is held by private companies and institutions. Without that data nobody can forecast water quality, climate disasters or environmental accidents.

That is why marola is open and non-profit. Our promise is to share everything with everyone, as well as we can. As just another company, it would be hard to ask the people holding that data for it.

## Water quality first

Basic sanitation in Brazil is far from solved. That is too big a can of worms for this page, but it decides where marola starts: with water quality. Before surfing, fishing or diving comes the question "can I go in this water?".

One idea is a national bathing-water ranking, already [under open discussion](https://github.com/marola-dev/marola/discussions/676). Many posts will follow: who is looking after the water well, who is not, how and why.

## A water super app

This is the era of super apps, and marola will inevitably be a super app for water: one place for everything about water: the beach, the sea, water quality and hazards. Not an app that hands you tools to work it out yourself, but one that hands you the answer.

It is the shift Sequoia Capital, one of Silicon Valley's largest venture funds, calls "service as software": software stops selling the tool and starts delivering the work.

> "A copilot sells the tool. An autopilot sells the work."
> -- Julien Bek, [Services: The New Software](https://sequoiacap.com/article/services-the-new-software), Sequoia Capital, 2026. The idea goes back to [Generative AI's Act o1](https://sequoiacap.com/article/generative-ais-act-o1) by Sonya Huang and Pat Grady, 2024.

## Why open source

In 2026 there is no reason to write closed code. With AI, building a new feature has never been easier; the code itself is no longer the secret. What Brazil needs are long-term projects that do not hang on the election calendar or end when the government changes. Open source is what lets a project outlive the people who started it.

## Partnerships without money

marola needs compute and cloud: room to store data and graphics cards to train and run models. Even as a non-profit, it is open to partnerships with companies that donate those resources, or data, with no money changing hands. In return, the company gets a discreet credit on the site. No ads, banners or tracking.

## How marola is built

marola is a set of code repositories, each with one job:

- **marola-app** brings together the sea forecast, the beaches and the water quality, and works out the score.
- **marola-site** is the map you are using.
- **marola-corpus** keeps notes about the sea, each with its source.
- **marola-ml** trains and tests the AI before it reaches marola-app.
- **marola-oods** is an open archive of the beaches' and the water's history.
- **marola-research** holds marola's research.
- **marola-skills** and **marola-agents** list the skills and AI agents that work on the project.
- **marola-devkit** is the set of tools every repository uses.
- **marola**, the umbrella, holds the plans and the rules, and brings in every other repository as a git submodule.

![How the marola repos fit together: marola, the umbrella, brings in every repo as a git submodule; marola-corpus hands a release tarball to marola-app and marola-ml; marola-app's image builds marola-site's map and brings image and resources to marola-ml, which returns compiled prompts in a PR; ETL jobs write marola-oods' data lake; every repo pins marola-devkit by tag; marola-skills reads every SKILL.md, marola-agents indexes every agent, and marola-research holds the science](/img/umbrella.svg 1000x712)
marola's repositories and what each hands to the next. The picture is the one on the [organization's GitHub page](https://github.com/marola-dev) (source: [marola-dev/.github](https://github.com/marola-dev/.github/blob/main/profile/README.en.md)).

We call this a distributed monolith. It is one project, with one plan, one way of working and versions that move together, as if it were a single system. But each part lives in its own repository, with its own tests and releases.

We built it this way for two reasons. First, much of the code is written and maintained with Anthropic's Claude, both in a Claude Project and in Claude Code from the terminal. The umbrella with submodules helps with that: Claude sees the whole project from above, with the plans and the rules written in one place, and changes one small repository at a time, with that repository's tests. Second, each part keeps some autonomy outside the umbrella. Someone who only wants the water-quality data can use marola-oods without the rest, and a mistake in one repository does not take down the others. No part reads another's code: it uses a published version and moves to a new one only when it decides to.

## Claude

Much of marola's code is written with Claude, Anthropic's AI assistant, in a Claude Project: a space on claude.ai where it reads the repositories, opens pull requests and talks with us in threads. The project's settings are in an open file, [CLAUDE_PROJECT.config.md](https://github.com/marola-dev/marola/blob/main/CLAUDE_PROJECT.config.md): the instructions Claude follows, the repositories it reads, the environment it runs in and the routines it runs on its own. Anyone can read the file or set up a project like it.

## How the score works

Each beach gets a number in one of the five bands on the map legend: **≥70** good, **40–69** fair, **1–39** poor, **0** unfit, or **no data** when a source did not answer. The score folds together the sea, wind, waves, tide and water quality. A language model writes a short summary, and a second automatic pass checks it against the numbers. The AI only explains: it never changes a score or overrides a warning.

## Where the data comes from

Beaches come from [OpenStreetMap](https://www.openstreetmap.org/copyright), sea and weather from [Open-Meteo](https://open-meteo.com/), and water quality from the official bulletins of IMA/SC, INEA (RJ) and INEMA (BA). They are public, free sources. The base map is marola's own: its tiles are cut from OpenStreetMap data with [Protomaps](https://protomaps.com/), kept on our server and drawn with MapLibre. For now only the beaches and water-quality layers are on; wind, waves and NASA's satellite imagery ([GIBS](https://www.earthdata.nasa.gov/gibs)) are coming soon.

## Privacy

marola sets no cookies and does no tracking of its own. The base map comes from marola's own server: its style, tiles and fonts are files of this site, so drawing the map tells no one else that you were here. Two things reach a third party, and only when you open them: a satellite layer, whose images come from NASA's servers, and the Spotify player, which loads from Spotify. Each of them then sees your IP address. The "near me" sort uses your location only inside your own browser; it is never sent anywhere.

## Who builds it

The people who build marola are on the [members page](/members.html), the same list of creators as marola's Zenodo record.

marola's research is in [marola-research](https://github.com/marola-dev/marola-research/blob/main/README.md). To contribute or publish with us, read the [call for contribution and publication](https://github.com/marola-dev/marola-research/blob/main/chamada/chamada.pdf) (PDF, in Portuguese).

Scientists can publish a study here too. Read the [studies](/en/studies) that people sent, or [submit one](/en/submit). marola does not review them.

## Thanks

The emergency button idea came from [swell-floripa](https://swell-floripa.vercel.app/), by Carlos Toledo ([@carlostoledo1891](https://github.com/carlostoledo1891)).

The wave sound is a recording by Luftrum ([freesound](https://freesound.org/s/48412/), [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/)), looped by Porrumentzio for [Blanket](https://github.com/rafaelmardojai/blanket).

## How to help

Use the map and tell us when it is wrong. Tell us what you see in the water, like jellyfish or a missing beach. Open an [issue](https://github.com/marola-dev/marola/issues), in Portuguese or English. The code, the plans and every decision are on [GitHub](https://github.com/marola-dev/marola), and [the docs](https://docs.marola.dev/) show what works today and what is still a plan.
