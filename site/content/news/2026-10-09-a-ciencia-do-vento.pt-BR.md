# A Ciência do Vento

2026-10-09

qual previsão de vento acerta mais no litoral brasileiro: o MONAN, o modelo nacional do INPE, ou o WeatherNext, uma previsão do Google feita com aprendizado de máquina e [aberta a qualquer um](https://open-meteo.com/en/docs/google-weathernext-api)? ninguém mediu isso nas praias do marola. o [MIP-0083](https://github.com/marola-dev/marola/blob/main/docs/MIPs/MIP-0083-forecast-benchmark-job.md), a proposta de mudança aprovada em 9 de outubro, descreve uma rotina que vai comparar as previsões a cada 4 horas com o vento que os anemômetros registraram. ela começa pelo WeatherNext e pelo modelo europeu IFS; o MONAN entra quando os dados dele estiverem acessíveis. ainda não há nenhum resultado: o trabalho está começando.

## por que o vento

o vento move as ondas, e é no vento forte que se decide a segurança no mar. se o vento da previsão erra, a previsão de ondas erra junto. já se viu modelo de aprendizado de máquina suavizar os picos de vento: os quatro modelos avaliados num estudo [subestimaram o vento máximo da tempestade Ciarán](https://arxiv.org/abs/2312.02658), na Europa, em 2023. por isso o estudo avalia separadamente as horas de vento forte.

## por que agora

- **um El Niño forte está em curso.** o aviso da NOAA de 8 de outubro de 2026 diz que o mar no Pacífico equatorial (a região Niño-3.4) está 2,1 °C acima do normal e dá mais de 83 % de chance de um El Niño de forte a muito forte durar até o trimestre de janeiro a março de 2027 ([CPC](https://www.cpc.ncep.noaa.gov/products/analysis_monitoring/enso_advisory/ensodisc.shtml)). é a época em que a comparação tem mais a mostrar, e ela é agora.
- **a previsão do Google não fica guardada.** o WeatherNext 2 roda 64 versões da mesma previsão (os membros do conjunto), e o Open-Meteo, que distribui o modelo, só mantém a rodada mais recente. uma versão que ninguém salvou se perde ([MIP-0083, §2](https://github.com/marola-dev/marola/blob/main/docs/MIPs/MIP-0083-forecast-benchmark-job.md#2-motivation)).

## o que vai ser comparado

- **ECMWF IFS HRES**, o modelo do centro europeu de previsão, com grade de 9 km, como referência;
- **Google WeatherNext 2**, com seus 64 membros, numa grade de 0,25°;
- **MONAN**, do INPE, assim que se descobrir como baixar os dados dele. hoje isso é uma pergunta em aberto ([marola#723](https://github.com/marola-dev/marola/issues/723), passo 1).

## como uma previsão vira nota

a referência é sempre o que um instrumento mediu, nunca outro modelo. uma previsão para quinta ao meio-dia, salva na segunda, é comparada na quinta com o anemômetro daquela hora.

- **seis pontos, dois por estado** (SC, RJ e BA): em cada estado, um aeroporto com boletim METAR (o boletim meteorológico de aeroporto) e uma estação automática do INMET.
- **só entra ponto que recebe vento forte de verdade.** a regra ([marola#723](https://github.com/marola-dev/marola/issues/723)) olha os 5 anos anteriores e pede pelo menos 200 horas por ano com vento médio de 10,8 m/s ou mais (vento forte). pede também pelo menos 5 dias por ano com vento ou rajadas de 17,2 m/s ou mais (ventania). esses números ainda são provisórios. os pontos são escolhidos só pelo histórico, antes de qualquer previsão ser avaliada, para ninguém poder dizer que foram escolhidos a dedo.
- **a mesma regra para todos os modelos:** a célula de grade mais próxima, sem estimar valores entre os pontos da grade, e a distância até a estação aparece ao lado de cada nota.
- **as notas:** viés (se o modelo erra mais para cima ou para baixo), erro quadrático médio (RMSE, o tamanho típico do erro) e CRPS, uma nota para as 64 versões do WeatherNext juntas. tudo separado por modelo, ponto, antecedência (24, 72, 120 e 240 horas) e vento observado: calmo, moderado e forte.
- **uma rodada perdida fica registrada como perdida,** nunca preenchida com a vizinha.

nenhum modelo de linguagem participa do cálculo, que é determinístico ([MIP-0083, §5.10](https://github.com/marola-dev/marola/blob/main/docs/MIPs/MIP-0083-forecast-benchmark-job.md#510-what-is-deterministic)), e a nota das praias no mapa não usa nada disso ([§6](https://github.com/marola-dev/marola/blob/main/docs/MIPs/MIP-0083-forecast-benchmark-job.md#6-scoring--safety-impact)).

## onde está agora

- o MIP foi escrito em [marola#725](https://github.com/marola-dev/marola/pull/725) e aprovado em [marola#727](https://github.com/marola-dev/marola/pull/727).
- a primeira tarefa, a escolha das estações de medição, está em revisão em [marola-app#72](https://github.com/marola-dev/marola-app/pull/72): nove estações candidatas, um programa que confere as regras e uma página que diz o que foi conferido em cada uma e o que não foi.
- as previsões salvas vão ficar num espaço de armazenamento do Google Cloud (um bucket). ele deve ficar dentro do limite gratuito, cerca de US$ 0 por semana pela estimativa do MIP ([§5.9](https://github.com/marola-dev/marola/blob/main/docs/MIPs/MIP-0083-forecast-benchmark-job.md#59-infrastructure-besom-under-infraforecast-benchmark)), e só é criado depois que o responsável pelo projeto confirmar a tabela de custos.

## onde os resultados vão aparecer

- **uma página do vento no marola.dev** ([#99](https://github.com/marola-dev/marola-site/issues/99)), com as previsões lado a lado e as notas dos últimos 7, 30 e 90 dias, sempre com o tamanho da amostra.
- **um capítulo proposto para o livro sobre o WAVEWATCH III**, um modelo de previsão de ondas ([ww3-gpu#92](https://github.com/h0ffmann/ww3-gpu/issues/92)): qual vento escolher para alimentar um modelo de ondas.
- **um conjunto de dados aberto, com DOI (um endereço permanente para citar) no Zenodo, e um preprint (o artigo antes da revisão por pares) no arXiv** ([marola#723](https://github.com/marola-dev/marola/issues/723)).

a página mostra as notas desde o começo e avisa quando a amostra é pequena. nenhuma conclusão sai antes de 90 dias de dados. uma primeira resposta à pergunta só vem depois de 12 meses e de pelo menos 30 dias de vento forte por estado. o estudo quer cobrir 24 meses, para não tirar conclusões gerais de um único ano de El Niño.

e precisão é só uma parte da pergunta. um teste de acerto não mede se o país fica dependente de um modelo de fora (soberania), se o modelo usa as medições feitas no Brasil (assimilação) nem se ele tem garantia de funcionar todo dia, e o resultado vai deixar isso claro.

## como acompanhar ou ajudar

a discussão do estudo está em [marola#723](https://github.com/marola-dev/marola/issues/723). se você conhece uma estação com vento forte no litoral de SC, do RJ ou da BA, ou sabe como o INPE publica os dados do MONAN, conte lá, em português ou em inglês.
