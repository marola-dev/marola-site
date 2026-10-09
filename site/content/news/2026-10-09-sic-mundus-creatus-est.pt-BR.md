# Sic Mundus Creatus Est

2026-10-09

o marola está no ar, aberto e sem fins lucrativos. é um mapa das praias de Florianópolis, do Rio de Janeiro e de Salvador, com uma nota para hoje e amanhã feita só com dados públicos. a versão 0.2.0 saiu em 7 de outubro e já tem DOI.

## links oficiais

- o mapa: [marola.dev](https://marola.dev/)
- a documentação: [docs.marola.dev](https://docs.marola.dev/)
- o código, sob licença MIT: [github.com/marola-dev](https://github.com/marola-dev)
- para citar: [10.5281/zenodo.23224155](https://doi.org/10.5281/zenodo.23224155), no Zenodo. esse DOI sempre leva à versão mais recente, que hoje é a [0.2.0](https://github.com/marola-dev/marola/releases/tag/v0.2.0). o [README](https://github.com/marola-dev/marola#how-to-cite) tem a referência em ABNT, APA e BibTeX.
- o modelo de linguagem do marola, o marola-sea: publicado no Hugging Face a partir do [marola-ml](https://github.com/marola-dev/marola-ml)
- conversas abertas: [discussões no GitHub](https://github.com/marola-dev/marola/discussions)

## o que ele é, e o que não é

a nota junta o mar, o vento, as ondas, a maré e a balneabilidade oficial do IMA/SC, do INEA (RJ) e do INEMA (BA). o que pode colocar alguém em risco é decidido por regras simples, que qualquer pessoa pode ler. a IA só escreve o resumo e nunca muda uma nota. não tem cookie, rastreamento próprio nem cadastro.

o marola não é salva-vidas, não é previsão oficial e não é serviço de alerta. em caso de emergência, o botão "emergência" do mapa mostra os números gratuitos, como o 193 dos bombeiros e guarda-vidas.

## como o site roda

o mapa é estático: nenhum servidor nosso e nenhuma IA trabalham quando você abre a página. a cada 3 horas, uma automação no GitHub roda a imagem do marola-app, calcula a nota de cada praia e publica os arquivos. quem entrega o marola.dev é um [Cloudflare Worker](https://github.com/marola-dev/marola-site/blob/main/docs/3-development.md), no plano gratuito, e o GitHub Pages fica de reserva. o INEA e o INEMA só respondem a endereços brasileiros, então a automação passa por um proxy no Brasil mantido por voluntários.

os dados vão morar no Cloudflare R2, num lago de dados que ainda está sendo montado (mais sobre isso abaixo).

## os repositórios

cada parte do marola é um repositório na organização [marola-dev](https://github.com/marola-dev), com seus próprios testes e versões. uma parte nunca usa o código da outra direto: ela fixa uma versão publicada.

### [marola](https://github.com/marola-dev/marola)

o repositório guarda-chuva. tem os planos de cada mudança (os MIPs), a lista de fases, as regras de trabalho e o site da documentação. é dele que sai a versão citável no Zenodo.

### [marola-app](https://github.com/marola-dev/marola-app)

o produto, em Scala 3 com [Kyo](https://getkyo.io/). busca as praias no OpenStreetMap, o mar e o tempo no Open-Meteo e os boletins de balneabilidade, calcula a nota e o veto de segurança, e tem uma linha de comando e um servidor MCP. a imagem Docker que ele publica é a que monta o mapa.

### [marola-site](https://github.com/marola-dev/marola-site)

o mapa em marola.dev, sobre o Mapbox. JavaScript puro, sem framework, em português e inglês.

### [marola-oods](https://github.com/marola-dev/marola-oods)

o Open Ocean Data Store: o esquema do lago de dados aberto de praias e de amostras de balneabilidade. ainda não tem dados.

### [marola-ml](https://github.com/marola-dev/marola-ml)

o Python que roda fora do mapa: compila os prompts com DSPy, mantém o teste de qualidade que um modelo precisa passar antes de entrar, e treina o marola-sea.

### [marola-corpus](https://github.com/marola-dev/marola-corpus)

as anotações sobre o mar de onde o marola tira as respostas, cada uma com a sua fonte.

### [marola-devkit](https://github.com/marola-dev/marola-devkit)

a caixa de ferramentas que todos os repositórios usam: scripts, hooks do git, skills para agentes de IA e a integração contínua compartilhada.

### [agent-skills](https://github.com/marola-dev/agent-skills)

o catálogo das skills de agentes de IA usadas no marola: onde cada uma está, de onde veio e o que já foi testado.

a organização também mantém a [awesome-ocean-science](https://github.com/marola-dev/awesome-ocean-science), uma lista de software, dados e ferramentas abertas sobre o oceano.

## o grande trabalho agora: o lago de dados

hoje, cada atualização do mapa busca as praias e a balneabilidade do zero, e o histórico se perde. o [MIP-0075](https://github.com/marola-dev/marola/blob/main/docs/MIPs/MIP-0075-water-quality-store-r2.md) guarda tudo num lago de dados aberto: um [DuckLake](https://ducklake.select/), com arquivos Parquet e um catálogo DuckDB, num bucket do Cloudflare R2. rotinas semanais do marola-app escrevem nele, e o marola-oods define o esquema. primeiro vêm as praias, depois a balneabilidade de Santa Catarina, depois a do Rio e a da Bahia.

o esquema ([marola-oods#22](https://github.com/marola-dev/marola-oods/pull/22)) e a mudança para o R2 ([marola#692](https://github.com/marola-dev/marola/pull/692)) estão em revisão. o lago ainda não recebeu nenhum dado.

o próximo post explica por que o marola precisa de um lago.

## parceria com a Leave No Trace

a [Leave No Trace](https://lnt.org/), organização sem fins lucrativos que ensina a aproveitar a natureza sem deixar rastro, aceitou o marola no seu programa de parcerias comunitárias, o Community Partnership Program. a equipe deles viu no marola dados abertos de segurança no mar e de balneabilidade para quem vai às praias de Florianópolis, do Rio de Janeiro e de Salvador, e achou que as mensagens de "não deixe rastro" combinam com isso.

o programa abre o material educativo da Leave No Trace aos parceiros e permite que instrutores certificados deem certificados de curso. o que isso vai mudar no marola vem num próximo post ([#96](https://github.com/marola-dev/marola-site/issues/96)).

o marola segue aberto a parcerias sem dinheiro com instituições ambientais e com quem possa ceder dados ou computação ([sobre](about.html)).

## como acompanhar ou ajudar

use o mapa e avise quando ele errar. abra uma [issue](https://github.com/marola-dev/marola/issues), em português ou em inglês, ou pegue uma marcada como [good first issue](https://github.com/search?q=org%3Amarola-dev+is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22&type=issues). dá também para [apoiar o projeto](support.html).
