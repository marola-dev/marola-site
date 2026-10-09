# The Science of Wind

2026-10-09

which wind forecast is right more often on the Brazilian coast: MONAN (Modelo para Previsões de Oceano, Terra e Atmosfera), the national model from INPE (Instituto Nacional de Pesquisas Espaciais, Brazil's space research institute), or WeatherNext, Google's machine-learning forecast that [anyone can read](https://open-meteo.com/en/docs/google-weathernext-api)? nobody has measured it at the beaches marola covers. [MIP-0083](https://github.com/marola-dev/marola/blob/main/docs/MIPs/MIP-0083-forecast-benchmark-job.md), a marola change proposal (MIP, Marola Improvement Proposal), was accepted on October 9 in a rigorously dictatorial vote: the agents' pilot decided, and the agents agreed. it describes a job that will compare the forecasts every 4 hours with the wind the anemometers recorded. it starts with WeatherNext and IFS (Integrated Forecasting System), the model of the European weather forecasting center; MONAN joins once its data is available. MONAN and IFS solve the physics equations of the atmosphere; WeatherNext learned the weather's patterns from decades of past data. there are no results yet: the work is just starting. anyone who loves the sea loves the wind, and this is the first in a series of posts about it.

## why wind

wind drives the waves, and strong wind is where safety at sea is decided. when the forecast wind is wrong, the wave forecast is wrong with it. machine-learning models have been caught smoothing out wind peaks: all four models in one study [underestimated Storm Ciarán's peak winds](https://arxiv.org/abs/2312.02658) in Europe in 2023. that is why the study scores strong-wind hours separately.

## why now

- a strong El Niño is under way. El Niño is an unusual warming of the equatorial Pacific that, every few years, shifts rain and wind patterns over much of the world. in its October 8, 2026 advisory, NOAA (the US National Oceanic and Atmospheric Administration) says the equatorial Pacific (the Niño-3.4 region, the strip of ocean used as El Niño's thermometer) is 2.1 °C warmer than normal, and puts the chance that a strong or very strong El Niño lasts through January to March 2027 at more than 83%. in parts of the eastern equatorial Pacific the sea is already more than 4.0 °C warmer than normal. with an event this size, typical El Niño impacts are more likely, though not guaranteed ([advisory by CPC, NOAA's Climate Prediction Center](https://www.cpc.ncep.noaa.gov/products/analysis_monitoring/enso_advisory/ensodisc.shtml)). that is when the comparison has the most to show.
- in Brazil, El Niño raises the chance of above-average rain in the South and brings a risk of drought to the northern parts of Brazil's North and Northeast regions ([INMET (Instituto Nacional de Meteorologia), Brazil's national weather service](https://portal.inmet.gov.br/noticias/o-que-%C3%A9-e-quais-os-impactos-do-el-ni%C3%B1o-entenda-agora)). in the North Atlantic the effect is different: it usually means fewer hurricanes, because it increases wind shear (the difference in wind between layers of the atmosphere), which keeps storms from organizing into hurricanes ([NOAA](https://www.aoml.noaa.gov/how-does-el-nino-impact-atlantic-hurricane-season/)). the study will show how each forecast does during El Niño: the scores are reported separately by phase: El Niño, neutral, or La Niña, the opposite cooling ([marola#723](https://github.com/marola-dev/marola/issues/723)).
- Google's forecast is not kept. WeatherNext 2 runs 64 versions of each forecast (its ensemble members). each version starts from slightly different conditions: if the 64 agree, the forecast is more reliable; if they spread out, the uncertainty is large. Open-Meteo, which distributes it, keeps only the latest run (each run is one execution of the model, producing a new forecast). a version nobody saves is gone ([MIP-0083, §2](https://github.com/marola-dev/marola/blob/main/docs/MIPs/MIP-0083-forecast-benchmark-job.md#2-motivation)).

## what will be compared

each model divides the planet into squares, the grid, and computes one wind value per square. the smaller the square, the more detail.

- ECMWF IFS HRES, as the reference: IFS is the model of ECMWF, the European Centre for Medium-Range Weather Forecasts, and HRES is its high-resolution version, with squares 9 km on a side;
- Google WeatherNext 2, with its 64 members, on a 0.25° grid (squares about 28 km on a side). Google has already announced [WeatherNext 3](https://developers.google.com/weathernext/guides/models), with hourly steps, but access to it needs Google's approval; the open version on Open-Meteo, the one that will be compared, is still 2;
- MONAN, from INPE, once it is clear how to download its data. that is still open ([marola#723](https://github.com/marola-dev/marola/issues/723), step 1).

## how a forecast gets a score

the reference is always what an instrument measured, never another model. a forecast for Thursday at noon, saved on Monday, is compared on Thursday with the anemometer reading for that hour.

an anemometer is the instrument that measures wind. the most common kind has three or four cups on a spindle, at the top of a 10 m mast. the wind pushes the cups, and the harder it blows, the faster they spin; counting the turns gives the wind speed. some anemometers have no moving parts at all: they measure how much the wind speeds up or slows down a sound travelling between two sensors (a sonic anemometer). in the practice of the Met Office, the UK's weather service, the mean wind is the average over the 10 minutes before the reading, and a gust is the highest 3-second average ([Met Office](https://weather.metoffice.gov.uk/guides/observations/how-we-measure-wind)).

- there are six points, two per state (Santa Catarina, Rio de Janeiro and Bahia). in each state, an airport with a METAR report (METeorological Aerodrome Report, the airport weather report) and an automatic INMET station.
- only points where the wind really blows hard count. the rule ([marola#723](https://github.com/marola-dev/marola/issues/723)) looks at the previous 5 years and asks for at least 200 hours a year of mean wind at 10.8 m/s (about 39 km/h) or more (a strong breeze). it also asks for at least 5 days a year with wind or gusts at 17.2 m/s (about 62 km/h) or more (a gale). both numbers are still provisional. points are chosen from their history only, before any forecast is scored, so nobody can say they were cherry-picked.
- every model follows the same rule: the grid square nearest the station, with no estimating between squares, and the distance to the station is shown next to every score.
- there are three scores. bias says whether a model runs high or low. root-mean-square error (RMSE) gives the typical size of the error. CRPS (continuous ranked probability score) scores all 64 WeatherNext versions together, as a forecast range: a good score goes to the one that catches the measured wind without opening too wide a range. all of it comes out per model, point, lead time (24, 72, 120 and 240 hours) and the wind actually observed: calm, moderate or strong.
- a missed run is recorded as missed. nobody fills the gap with the run next to it.

no language model, the kind of artificial intelligence behind ChatGPT, takes part in the computation. it follows fixed rules: the same data always gives the same result (it is deterministic) ([MIP-0083, §5.10](https://github.com/marola-dev/marola/blob/main/docs/MIPs/MIP-0083-forecast-benchmark-job.md#510-what-is-deterministic)), and the beach scores on the map use none of it ([§6](https://github.com/marola-dev/marola/blob/main/docs/MIPs/MIP-0083-forecast-benchmark-job.md#6-scoring--safety-impact)).

## where it stands

- the MIP was written in [marola#725](https://github.com/marola-dev/marola/pull/725) and accepted in [marola#727](https://github.com/marola-dev/marola/pull/727).
- the first task, choosing the measuring stations, is in review in [marola-app#72](https://github.com/marola-dev/marola-app/pull/72): nine candidate stations, a program that checks the rules, and a page saying what was checked for each one and what was not.
- the saved forecasts will live in storage on Google Cloud (a bucket). it should stay inside the free tier, about US$0 a week by the MIP's estimate ([§5.9](https://github.com/marola-dev/marola/blob/main/docs/MIPs/MIP-0083-forecast-benchmark-job.md#59-infrastructure-besom-under-infraforecast-benchmark)), and it will be created only after the project's owner confirms the cost table.

## where the results will show up

- a wind page on marola.dev ([#99](https://github.com/marola-dev/marola-site/issues/99)), with the forecasts side by side and the scores for the last 7, 30 and 90 days, always with the sample size;
- a proposed chapter for a book on WAVEWATCH III, a wave forecasting model: which wind to use as its input ([ww3-gpu#92](https://github.com/h0ffmann/ww3-gpu/issues/92));
- an open dataset with a Zenodo DOI (Digital Object Identifier), and an arXiv preprint ([marola#723](https://github.com/marola-dev/marola/issues/723)). the DOI is a permanent link for citing the data; the preprint is the paper before peer review.

the page shows scores from the start and flags a small sample. but no conclusion is drawn before 90 days of data, and a first answer to the question comes only after 12 months and at least 30 strong-wind days per state. the study aims to run for 24 months, so that no general conclusion rests on a single El Niño year.

and getting the forecast right is only part of the story. an accuracy test does not measure whether Brazil depends on a foreign model (sovereignty), whether a model uses Brazilian measurements to correct the forecast's starting point (assimilation) or whether it is guaranteed to run every day. the results will carry that caveat.

## how to follow or help

the study is discussed in public in [marola#723](https://github.com/marola-dev/marola/issues/723), a page on GitHub, the site where marola's code lives. if you know of a windy station on the coast of Santa Catarina, Rio de Janeiro or Bahia, or know how INPE publishes MONAN's data, tell us there, in Portuguese or English.
