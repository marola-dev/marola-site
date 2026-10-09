# The Science of Wind

2026-10-09

which wind forecast is right more often on the Brazilian coast: MONAN (Modelo para Previsão dos Oceanos, Superfícies Terrestres e Atmosfera), the national model from INPE (Instituto Nacional de Pesquisas Espaciais, Brazil's space research institute), or WeatherNext, which Google builds with machine learning, a kind of artificial intelligence? nobody has measured it at the beaches marola covers, and now we will. the study's proposal was approved on October 9 in a rigorously dictatorial vote: the pilot of the artificial intelligence agents decided, and the agents agreed. there are no results yet. anyone who loves the sea loves the wind, and this is the first in a series of posts about it.

## why wind

wind drives the waves, and strong wind is where safety at sea is decided. when the forecast wind is wrong, the wave forecast is wrong with it.

the two models reach a forecast in different ways. MONAN solves the physics equations of the atmosphere; WeatherNext learned weather patterns from years of past data ([the paper](https://arxiv.org/abs/2506.10772)). and machine-learning models have been caught smoothing out wind peaks: all four models in one study [underestimated Storm Ciarán's peak winds](https://arxiv.org/abs/2312.02658) in Europe in 2023. that is why strong-wind hours will be scored separately.

## why now

a strong El Niño is under way. El Niño is an unusual warming of the equatorial Pacific that, every few years, shifts rain and wind over much of the world. NOAA (the US National Oceanic and Atmospheric Administration) gives it more than an 83% chance of staying strong or very strong through January to March 2027 ([October 8 advisory](https://www.cpc.ncep.noaa.gov/products/analysis_monitoring/enso_advisory/ensodisc.shtml)). in Brazil, that usually means above-average rain in the South and a risk of drought in the northern parts of the North and Northeast regions ([INMET, the Instituto Nacional de Meteorologia, Brazil's national weather service](https://portal.inmet.gov.br/noticias/o-que-%C3%A9-e-quais-os-impactos-do-el-ni%C3%B1o-entenda-agora)). in the North Atlantic the effect is different: El Niño usually means fewer hurricanes ([NOAA](https://www.aoml.noaa.gov/how-does-el-nino-impact-atlantic-hurricane-season/)). it is a good time to see how each forecast copes with an unusual year.

and it can't wait. WeatherNext computes several possible versions of the weather from the same starting point ([Google](https://blog.google/technology/google-deepmind/weathernext-2/)). the open service that distributes it delivers 64 of those versions, but keeps only the most recent run, the last time the model ran ([Open-Meteo](https://openmeteo.substack.com/p/google-weathernext-2-is-available)). whatever nobody saves now is gone.

## how it will work

every 4 hours, a program will save the forecasts from WeatherNext 2 and from IFS (Integrated Forecasting System), the European weather forecasting center's model, which serves as the reference. MONAN joins once its data is available. Google has already announced [WeatherNext 3](https://developers.google.com/weathernext/guides/models), but access to it needs Google's approval; the study uses the open version.

then each forecast is checked against what the anemometers, the instruments that measure wind, actually recorded. a forecast for Thursday at noon, saved on Monday, is compared on Thursday with the reading for that hour. the most common kind of anemometer has three or four cups at the top of a 10 m mast, and the harder the wind blows, the faster they spin ([Met Office](https://weather.metoffice.gov.uk/guides/observations/how-we-measure-wind)).

- there will be six measuring points, two each in Santa Catarina, Rio de Janeiro and Bahia, at airports and at INMET automatic stations.
- only places where the wind really blows hard count. they are picked from their past wind records, before any forecast is scored, so nobody can say they were cherry-picked.
- each model's score says whether it runs high or low and how big its typical error is. for WeatherNext, the score looks at all 64 versions together, not just their average.
- no language model, the kind of artificial intelligence behind ChatGPT, takes part in the computation. the same data always gives the same result.

## when the answer comes

the scores will show up on a wind page on marola.dev, always with the sample size. in the first 90 days there is too little data to conclude anything, and a first answer to the question in the title comes only after 12 months. the plan is to run for 24 months, so that no conclusion rests on a single El Niño year, and to publish the result as a paper on arXiv, the open repository of scientific papers.

getting the forecast right is only part of the story. an accuracy test does not say whether Brazil ends up depending on a foreign model or whether a model uses Brazilian measurements. the results will carry that caveat.

## how to follow or help

do you know of a windy station on the coast of Santa Catarina, Rio de Janeiro or Bahia? do you know how INPE publishes MONAN's data? tell us in an [issue](https://github.com/marola-dev/marola/issues) (a report on GitHub), in Portuguese or English. the next posts in the series will cover what turns up.
