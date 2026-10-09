# The Science of Wind

2026-10-09

Which wind forecast is right more often on the Brazilian coast: MONAN, the national model of INPE, Brazil's space research institute, or WeatherNext, Google's machine-learning forecast that [anyone can read](https://open-meteo.com/en/docs/google-weathernext-api)? Nobody has measured it at marola's beaches. [MIP-0083](https://github.com/marola-dev/marola/blob/main/docs/MIPs/MIP-0083-forecast-benchmark-job.md), the change proposal accepted on October 9, describes a job that will compare the forecasts every 4 hours with the wind the anemometers recorded. It starts with WeatherNext and the European IFS model; MONAN joins once its data is available. There are no results yet: the work is just starting.

## Why wind

Wind drives the waves, and strong wind is where safety at sea is decided. When the forecast wind is wrong, the wave forecast is wrong with it. Machine-learning models have been caught smoothing out wind peaks: all four models in one study [underestimated Storm Ciarán's peak winds](https://arxiv.org/abs/2312.02658) in Europe in 2023. That is why the study scores strong-wind hours separately.

## Why now

- **A strong El Niño is under way.** NOAA's advisory of October 8, 2026, says the equatorial Pacific (the Niño-3.4 region) is 2.1 °C warmer than normal and gives a more than 83% chance that a strong or very strong El Niño lasts through January to March 2027 ([CPC](https://www.cpc.ncep.noaa.gov/products/analysis_monitoring/enso_advisory/ensodisc.shtml)). It is when the comparison has the most to show, and it is happening now.
- **Google's forecast is not kept.** WeatherNext 2 runs 64 versions of each forecast (its ensemble members), and Open-Meteo, which distributes it, keeps only the latest run. A version nobody saved is gone ([MIP-0083, §2](https://github.com/marola-dev/marola/blob/main/docs/MIPs/MIP-0083-forecast-benchmark-job.md#2-motivation)).

## What will be compared

- **ECMWF IFS HRES**, the European forecast centre's model, on a 9 km grid, as the reference;
- **Google WeatherNext 2**, with its 64 members, on a 0.25° grid;
- **MONAN**, from INPE, once it is clear how to download its data. Today that is an open question ([marola#723](https://github.com/marola-dev/marola/issues/723), step 1).

## How a forecast gets a score

The reference is always what an instrument measured, never another model. A forecast for Thursday at noon, saved on Monday, is compared on Thursday with the anemometer reading for that hour.

- **Six points, two per state** (SC, RJ and BA): in each state, an airport with a METAR report (the airport weather report) and an automatic station of INMET, Brazil's national weather service.
- **Only points that really get strong wind.** The rule ([marola#723](https://github.com/marola-dev/marola/issues/723)) looks at the previous 5 years and asks for at least 200 hours a year of mean wind at 10.8 m/s or more (a strong breeze). It also asks for at least 5 days a year with wind or gusts at 17.2 m/s or more (a gale). Both numbers are still provisional. Points are chosen from their history only, before any forecast is scored, so nobody can say they were cherry-picked.
- **One rule for every model:** the nearest grid cell, with no estimating between grid points, and the distance to the station is shown next to every score.
- **The scores:** bias (whether a model runs high or low), root-mean-square error (RMSE, the typical size of the error) and CRPS, a score for all 64 WeatherNext versions together. All of it per model, point, lead time (24, 72, 120 and 240 hours) and the wind actually observed: calm, moderate and strong.
- **A missed run is recorded as missed,** never filled from the one next to it.

No language model takes part in the computation, which is deterministic ([MIP-0083, §5.10](https://github.com/marola-dev/marola/blob/main/docs/MIPs/MIP-0083-forecast-benchmark-job.md#510-what-is-deterministic)), and the beach scores on the map use none of it ([§6](https://github.com/marola-dev/marola/blob/main/docs/MIPs/MIP-0083-forecast-benchmark-job.md#6-scoring--safety-impact)).

## Where it stands

- The MIP was written in [marola#725](https://github.com/marola-dev/marola/pull/725) and accepted in [marola#727](https://github.com/marola-dev/marola/pull/727).
- The first task, choosing the measuring stations, is in review in [marola-app#72](https://github.com/marola-dev/marola-app/pull/72): nine candidate stations, a program that checks the rules, and a page saying what was checked for each one and what was not.
- The saved forecasts will live in storage on Google Cloud (a bucket). It should stay inside the free tier, about US/bin/bash a week by the MIP's estimate ([§5.9](https://github.com/marola-dev/marola/blob/main/docs/MIPs/MIP-0083-forecast-benchmark-job.md#59-infrastructure-besom-under-infraforecast-benchmark)), and it is created only after the project's owner confirms the cost table.

## Where the results will show up

- **A wind page on marola.dev** ([#99](https://github.com/marola-dev/marola-site/issues/99)), with the forecasts side by side and the scores for the last 7, 30 and 90 days, always with the sample size.
- **A proposed chapter in the book on WAVEWATCH III**, a wave forecasting model ([ww3-gpu#92](https://github.com/h0ffmann/ww3-gpu/issues/92)): which wind to trust as a wave model's input.
- **An open dataset with a Zenodo DOI (a permanent link for citing it), and an arXiv preprint (the paper before peer review)** ([marola#723](https://github.com/marola-dev/marola/issues/723)).

The page shows scores from the start and flags a small sample. No conclusion is drawn before 90 days of data. A first answer to the question comes only after 12 months and at least 30 strong-wind days per state. The study aims to run for 24 months, so that no general conclusion rests on a single El Niño year.

And accuracy is only part of the question. An accuracy test does not measure whether Brazil depends on a foreign model (sovereignty), whether a model takes in Brazilian measurements (assimilation) or whether it is guaranteed to run every day, and the result will say so.

## How to follow or help

The study is discussed in [marola#723](https://github.com/marola-dev/marola/issues/723). If you know of a windy station on the coast of SC, RJ or BA, or know how INPE publishes MONAN's data, tell us there, in Portuguese or English.
