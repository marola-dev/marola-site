# A Ciência do Vento

2026-10-09

qual previsão de vento acerta mais no litoral brasileiro: a do MONAN (Modelo para Previsão dos Oceanos, Superfícies Terrestres e Atmosfera), o modelo nacional do INPE (Instituto Nacional de Pesquisas Espaciais), ou a do WeatherNext, que o Google faz com aprendizado de máquina, um tipo de inteligência artificial? ninguém mediu isso nas praias do marola, e agora vamos medir. a proposta do estudo foi aprovada em 9 de outubro, numa votação rigorosamente ditatorial: o piloto dos agentes de inteligência artificial decidiu, e os agentes concordaram. ainda não há nenhum resultado. quem gosta de mar gosta de vento, e este é o primeiro de uma série de posts sobre ele.

## por que o vento

é o vento que levanta as ondas, e é no vento forte que se decide a segurança no mar. se a previsão erra o vento, erra as ondas junto.

os dois modelos chegam à previsão por caminhos diferentes. o MONAN resolve as equações da física da atmosfera; o WeatherNext aprendeu os padrões do tempo com anos de registros meteorológicos ([o artigo](https://arxiv.org/abs/2506.10772)). e modelos de aprendizado de máquina já foram pegos suavizando os picos de vento: num estudo, os quatro avaliados [subestimaram o vento máximo da tempestade Ciarán](https://arxiv.org/abs/2312.02658), na Europa, em 2023. por isso as horas de vento forte vão ser avaliadas à parte.

## por que agora

um El Niño forte está em curso. o El Niño é um aquecimento fora do normal do Pacífico equatorial que, a cada poucos anos, muda a chuva e o vento em boa parte do mundo. a NOAA (National Oceanic and Atmospheric Administration), é a agência dos Estados Unidos para oceanos e atmosfera. ela dá mais de 83% de chance de ele seguir forte ou muito forte até o trimestre de janeiro a março de 2027 ([aviso de 8 de outubro](https://www.cpc.ncep.noaa.gov/products/analysis_monitoring/enso_advisory/ensodisc.shtml)). no Brasil, isso costuma trazer chuva acima da média no Sul e risco de seca no norte das regiões Norte e Nordeste ([INMET, o Instituto Nacional de Meteorologia](https://portal.inmet.gov.br/noticias/o-que-%C3%A9-e-quais-os-impactos-do-el-ni%C3%B1o-entenda-agora)). no Atlântico Norte, o efeito é outro: o El Niño costuma reduzir os furacões ([NOAA](https://www.aoml.noaa.gov/how-does-el-nino-impact-atlantic-hurricane-season/)). é um bom momento para ver como cada previsão se sai num ano fora do comum.

e não dá para esperar. o WeatherNext calcula várias versões possíveis do tempo a partir do mesmo ponto de partida ([Google](https://blog.google/technology/google-deepmind/weathernext-2/)). o serviço aberto que distribui o modelo entrega 64 dessas versões, mas guarda só as da rodada mais recente, a última vez que o modelo rodou ([Open-Meteo](https://openmeteo.substack.com/p/google-weathernext-2-is-available)). o que ninguém salvar agora se perde.

## como vai funcionar

a cada 4 horas, um programa vai salvar as previsões do WeatherNext 2 e do IFS (Integrated Forecasting System), o modelo do centro europeu de previsão do tempo, que serve de referência. o MONAN entra quando der para acessar os dados dele. o Google já anunciou o [WeatherNext 3](https://developers.google.com/weathernext/guides/models), mas o acesso a ele depende de liberação; o estudo usa a versão aberta.

depois, cada previsão é conferida com o que os anemômetros, os aparelhos que medem o vento, registraram de verdade. uma previsão para quinta ao meio-dia, salva na segunda, é comparada na quinta com a leitura daquela hora. o anemômetro mais comum tem três ou quatro conchas no alto de um mastro de 10 metros, e quanto mais forte o vento, mais rápido elas giram ([Met Office](https://weather.metoffice.gov.uk/guides/observations/how-we-measure-wind)).

- vão ser seis pontos de medição, dois em Santa Catarina, dois no Rio de Janeiro e dois na Bahia, em aeroportos e em estações automáticas do INMET.
- só entram lugares onde venta forte de verdade. a escolha vem do histórico de vento de cada lugar, feita antes de qualquer previsão ser avaliada, para ninguém dizer que foram escolhidos a dedo.
- a nota de cada modelo diz se ele erra mais para cima ou para baixo e de quanto é o erro típico. no WeatherNext, a nota olha as 64 versões juntas, não só a média delas.
- nenhum modelo de linguagem, o tipo de inteligência artificial por trás do ChatGPT, entra na conta. com os mesmos dados, o resultado é sempre o mesmo.

## quando sai a resposta

as notas vão aparecer numa página do vento no marola.dev, sempre com o tamanho da amostra. nos primeiros 90 dias, os dados ainda são poucos para concluir qualquer coisa, e a primeira resposta à pergunta do título só vem depois de 12 meses. a ideia é seguir por 24 meses, para não tirar conclusão de um único ano de El Niño, e publicar o resultado num artigo no arXiv, o repositório aberto de artigos científicos.

acertar a previsão é só parte da história. um teste de acerto não diz se o país fica dependente de um modelo de fora nem se o modelo usa as medições feitas no Brasil. os resultados vão sair com esse aviso.

## como acompanhar ou ajudar

conhece uma estação com vento forte no litoral de Santa Catarina, do Rio de Janeiro ou da Bahia? sabe como o INPE publica os dados do MONAN? conte para a gente numa [issue](https://github.com/marola-dev/marola/issues) (um relato no GitHub), em português ou em inglês. os próximos posts da série contam o que for aparecendo.
