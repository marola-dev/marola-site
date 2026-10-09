# A Ciência do Vento

2026-10-09

qual previsão de vento acerta mais no litoral brasileiro: o MONAN (Modelo para Previsões de Oceano, Terra e Atmosfera), modelo nacional do INPE (Instituto Nacional de Pesquisas Espaciais), ou o WeatherNext, que o Google faz com aprendizado de máquina e que [qualquer pessoa pode consultar](https://open-meteo.com/en/docs/google-weathernext-api)? ninguém mediu isso nas praias do marola ainda. o [MIP-0083](https://github.com/marola-dev/marola/blob/main/docs/MIPs/MIP-0083-forecast-benchmark-job.md), uma proposta de mudança do marola (MIP vem de Marola Improvement Proposal), foi aprovado em 9 de outubro, numa votação rigorosamente ditatorial: o piloto dos agentes decidiu, e os agentes concordaram. ele descreve uma rotina que, a cada 4 horas, vai comparar as previsões com o vento registrado pelos anemômetros. ela começa pelo WeatherNext e pelo IFS (Integrated Forecasting System), o modelo do centro europeu de previsão do tempo. o MONAN entra quando der para acessar os dados dele. o MONAN e o IFS resolvem as equações da física da atmosfera; o WeatherNext aprendeu os padrões do tempo a partir de décadas de dados do passado. por enquanto não há nenhum resultado: o trabalho está começando. quem gosta de mar gosta de vento, e este é o primeiro de uma série de posts sobre ele.

## por que o vento

é o vento que levanta as ondas, e é no vento forte que se decide a segurança no mar. se a previsão erra o vento, erra as ondas junto. e modelos de aprendizado de máquina já foram pegos suavizando os picos de vento: num estudo, os quatro modelos avaliados [subestimaram o vento máximo da tempestade Ciarán](https://arxiv.org/abs/2312.02658), na Europa, em 2023. por isso as horas de vento forte são avaliadas à parte.

## por que agora

- um El Niño forte está em curso. o El Niño é um aquecimento fora do normal do Pacífico equatorial que, a cada poucos anos, muda o padrão de chuva e de vento em boa parte do mundo. a NOAA (National Oceanic and Atmospheric Administration), a agência dos Estados Unidos para oceanos e atmosfera, publicou um aviso em 8 de outubro de 2026. segundo ele, o mar no Pacífico equatorial (a região Niño-3.4, a faixa do oceano usada como termômetro do El Niño) está 2,1 °C acima do normal, e a chance de um El Niño de forte a muito forte durar até o trimestre de janeiro a março de 2027 passa de 83%. em partes do Pacífico equatorial leste, o mar já passa de 4,0 °C acima do normal. com um evento desse tamanho, os impactos típicos do El Niño ficam mais prováveis, embora não garantidos ([aviso do CPC (Climate Prediction Center), o centro de previsão climática da NOAA](https://www.cpc.ncep.noaa.gov/products/analysis_monitoring/enso_advisory/ensodisc.shtml)). é nesse período que a comparação tem mais a mostrar.
- no Brasil, o El Niño aumenta a chance de chuva acima da média no Sul e traz risco de seca no norte das regiões Norte e Nordeste ([INMET, o Instituto Nacional de Meteorologia](https://portal.inmet.gov.br/noticias/o-que-%C3%A9-e-quais-os-impactos-do-el-ni%C3%B1o-entenda-agora)). no Atlântico Norte, o efeito é outro: ele costuma reduzir os furacões, porque aumenta o cisalhamento do vento (a diferença de vento entre as camadas da atmosfera), e isso atrapalha a formação deles ([NOAA](https://www.aoml.noaa.gov/how-does-el-nino-impact-atlantic-hurricane-season/)). o estudo vai mostrar como cada previsão se sai durante o El Niño: as notas saem separadas por fase: com El Niño, neutra ou com La Niña, o resfriamento oposto ([marola#723](https://github.com/marola-dev/marola/issues/723)).
- a previsão do Google não fica guardada. o WeatherNext 2 roda 64 versões da mesma previsão (os membros do conjunto). cada versão parte de condições um pouco diferentes: se as 64 concordam, a previsão é mais confiável; se elas se espalham, a incerteza é grande. o Open-Meteo, que distribui o modelo, só mantém a rodada mais recente (cada rodada é uma execução do modelo, que gera uma previsão nova). o que ninguém salvar se perde ([MIP-0083, §2](https://github.com/marola-dev/marola/blob/main/docs/MIPs/MIP-0083-forecast-benchmark-job.md#2-motivation)).

## o que vai ser comparado

cada modelo divide o planeta em quadrados, a grade, e calcula um valor de vento para cada quadrado. quanto menor o quadrado, mais detalhe.

- o ECMWF IFS HRES, como referência: o IFS é o modelo do ECMWF, o Centro Europeu de Previsões Meteorológicas de Médio Prazo, e o HRES é a versão de alta resolução, com quadrados de 9 km de lado;
- o Google WeatherNext 2, com seus 64 membros, numa grade de 0,25° (quadrados de cerca de 28 km de lado). o Google já anunciou o [WeatherNext 3](https://developers.google.com/weathernext/guides/models), com passo de 1 hora, mas o acesso a ele depende de liberação do Google; a versão aberta no Open-Meteo, a que vai ser comparada, ainda é a 2;
- o MONAN, do INPE, assim que se descobrir como baixar os dados dele. isso ainda está em aberto ([marola#723](https://github.com/marola-dev/marola/issues/723), passo 1).

## como uma previsão vira nota

a referência é sempre o que um instrumento mediu, nunca outro modelo. uma previsão para quinta ao meio-dia, salva na segunda, é comparada na quinta com a leitura do anemômetro daquela hora.

o anemômetro é o aparelho que mede o vento. o mais comum tem três ou quatro conchas presas a um eixo, no alto de um mastro de 10 metros. o vento empurra as conchas, e quanto mais forte ele sopra, mais rápido elas giram; contando as voltas, o aparelho sabe a velocidade do vento. há também anemômetros sem nenhuma peça que se mexa: eles medem quanto o vento acelera ou atrasa um som que viaja entre dois sensores (o anemômetro sônico). no padrão do Met Office, o serviço meteorológico do Reino Unido, o vento médio é a média dos 10 minutos antes da leitura, e a rajada é o maior valor médio medido em 3 segundos ([Met Office](https://weather.metoffice.gov.uk/guides/observations/how-we-measure-wind)).

- são seis pontos, dois por estado (Santa Catarina, Rio de Janeiro e Bahia). em cada estado, um aeroporto com boletim METAR (sigla em inglês para boletim meteorológico de aeroporto) e uma estação automática do INMET.
- só entra ponto onde venta forte de verdade. a regra ([marola#723](https://github.com/marola-dev/marola/issues/723)) olha os 5 anos anteriores e pede pelo menos 200 horas por ano com vento médio de 10,8 m/s (cerca de 39 km/h) ou mais (vento forte). pede também pelo menos 5 dias por ano com vento ou rajadas de 17,2 m/s (cerca de 62 km/h) ou mais (ventania). esses números ainda são provisórios. os pontos saem só do histórico, antes de qualquer previsão ser avaliada, para ninguém dizer que foram escolhidos a dedo.
- todos os modelos seguem a mesma regra: vale o quadrado da grade mais próximo da estação, sem estimar valores entre um quadrado e outro, e a distância até a estação aparece ao lado de cada nota.
- as notas de erro do vento são três ([MIP-0083, §5.5](https://github.com/marola-dev/marola/blob/main/docs/MIPs/MIP-0083-forecast-benchmark-job.md#55-matching-and-scoring)). o viés (bias, em inglês) é a média da previsão menos a medição: positivo, o modelo exagera o vento; negativo, ele fica abaixo do que soprou. a raiz do erro quadrático médio (RMSE, na sigla em inglês) mede o tamanho do erro, pesando mais os erros grandes, que costumam vir justamente no vento forte. o CRPS (sigla em inglês para pontuação de probabilidade ranqueada contínua) avalia as 64 versões do WeatherNext juntas, como uma previsão em faixa: tira nota boa a que acerta o vento medido sem abrir uma faixa larga demais. para um modelo que dá um só valor, como o IFS, o CRPS vira o erro absoluto médio (MAE, na sigla em inglês): quantos m/s, em média, a previsão errou, sem olhar se foi para cima ou para baixo. é isso que deixa comparar as duas previsões na mesma régua. a direção do vento também ganha nota: o erro absoluto médio, em graus. tudo sai separado por modelo, ponto, antecedência (24, 72, 120 e 240 horas) e vento observado: calmo, moderado ou forte.
- rodada perdida fica registrada como perdida. ninguém preenche o buraco com a rodada vizinha.

nenhum modelo de linguagem, o tipo de inteligência artificial do ChatGPT, entra no cálculo. ele segue regras fixas: com os mesmos dados, a conta dá sempre o mesmo resultado (é determinístico) ([MIP-0083, §5.10](https://github.com/marola-dev/marola/blob/main/docs/MIPs/MIP-0083-forecast-benchmark-job.md#510-what-is-deterministic)), e a nota das praias no mapa não usa nada disso ([§6](https://github.com/marola-dev/marola/blob/main/docs/MIPs/MIP-0083-forecast-benchmark-job.md#6-scoring--safety-impact)).

## onde está agora

- o MIP foi escrito em [marola#725](https://github.com/marola-dev/marola/pull/725) e aprovado em [marola#727](https://github.com/marola-dev/marola/pull/727).
- a primeira tarefa, a escolha das estações de medição, está em revisão em [marola-app#72](https://github.com/marola-dev/marola-app/pull/72). são nove estações candidatas, um programa que confere as regras e uma página que diz o que foi conferido em cada uma e o que não foi.
- as previsões salvas vão para um espaço de armazenamento no Google Cloud (um bucket). pela estimativa do MIP, ele deve caber no limite gratuito, perto de US$ 0 por semana ([§5.9](https://github.com/marola-dev/marola/blob/main/docs/MIPs/MIP-0083-forecast-benchmark-job.md#59-infrastructure-besom-under-infraforecast-benchmark)), e só vai ser criado depois que o responsável pelo projeto confirmar a tabela de custos.

## onde os resultados vão aparecer

- numa página do vento no marola.dev ([#99](https://github.com/marola-dev/marola-site/issues/99)), com as previsões lado a lado e as notas dos últimos 7, 30 e 90 dias, sempre com o tamanho da amostra;
- num capítulo proposto para um livro sobre o WAVEWATCH III, um modelo de previsão de ondas: qual vento usar como entrada ([ww3-gpu#92](https://github.com/h0ffmann/ww3-gpu/issues/92));
- num conjunto de dados aberto, com DOI (identificador de objeto digital) no Zenodo, e num preprint no arXiv ([marola#723](https://github.com/marola-dev/marola/issues/723)). o DOI é um endereço permanente para citar os dados; o preprint é o artigo antes da revisão por pares.

a página mostra as notas desde o começo e avisa quando a amostra é pequena. só que nenhuma conclusão sai antes de 90 dias de dados, e uma primeira resposta à pergunta só vem depois de 12 meses e de pelo menos 30 dias de vento forte por estado. a ideia é seguir por 24 meses, para não tirar conclusão geral de um único ano de El Niño.

e acertar a previsão é só parte da história. um teste de acerto não diz se o país fica dependente de um modelo de fora (soberania), se o modelo usa as medições feitas no Brasil para acertar o ponto de partida da previsão (assimilação) nem se ele tem garantia de funcionar todo dia. os resultados vão sair com esse aviso.

## como acompanhar ou ajudar

a conversa pública sobre o estudo está em [marola#723](https://github.com/marola-dev/marola/issues/723), uma página no GitHub, o site onde fica o código do marola. se você conhece uma estação com vento forte no litoral de Santa Catarina, do Rio de Janeiro ou da Bahia, ou sabe como o INPE publica os dados do MONAN, conte lá, em português ou em inglês.
