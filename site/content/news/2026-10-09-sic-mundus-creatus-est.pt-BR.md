# Sic Mundus Creatus Est

2026-10-09

o marola está no ar: tem código aberto e não tem fins lucrativos. é um mapa das praias de Florianópolis, do Rio de Janeiro e de Salvador, com uma nota para hoje e amanhã feita só com dados públicos. a versão mais recente, a 0.2.1, saiu em 8 de outubro e já tem DOI, um identificador permanente para citar o marola em trabalhos científicos.

::: release v0.2.1 2026-10-08
- um DOI geral do marola no Zenodo, que sempre leva à versão mais recente ([#699](https://github.com/marola-dev/marola/pull/699))
- três novos autores no registro do Zenodo: Elisa Oliveira, Leonardo Santos Almeida e Pablo Ribeiro ([#712](https://github.com/marola-dev/marola/pull/712), [#714](https://github.com/marola-dev/marola/pull/714))
- o registro do Zenodo agora leva ao marola.dev ([#708](https://github.com/marola-dev/marola/pull/708))
- as skills dos agentes de IA agora têm versão fixa e são atualizadas toda semana ([MIP-0080](https://github.com/marola-dev/marola/pull/701))
- uma proposta para avaliar modelos de linguagem externos sem depender de um fornecedor ([MIP-0081](https://github.com/marola-dev/marola/pull/704))
[notas da versão](https://github.com/marola-dev/marola/releases/tag/v0.2.1) · [DOI 10.5281/zenodo.23224155](https://doi.org/10.5281/zenodo.23224155) · [mudanças desde a 0.2.0](https://github.com/marola-dev/marola/compare/v0.2.0...v0.2.1)

## links oficiais

- o mapa: [marola.dev](https://marola.dev/)
- a documentação: [docs.marola.dev](https://docs.marola.dev/)
- o código, sob licença MIT: [github.com/marola-dev](https://github.com/marola-dev)
- para citar: [10.5281/zenodo.23224155](https://doi.org/10.5281/zenodo.23224155), no Zenodo. esse DOI sempre leva à versão mais recente, que hoje é a [0.2.1](https://github.com/marola-dev/marola/releases/tag/v0.2.1). o [README](https://github.com/marola-dev/marola#how-to-cite) tem a referência em ABNT, APA e BibTeX.
- o modelo de linguagem do marola, o marola-sea: treinado no [marola-ml](https://github.com/marola-dev/marola-ml), por enquanto só numa versão de teste pequena
- conversas abertas: [discussões no GitHub](https://github.com/marola-dev/marola/discussions)

## o que o marola é e o que não é

a nota junta o mar, o vento, as ondas, a maré e o laudo oficial de balneabilidade do IMA/SC, do INEA (RJ) e do INEMA (BA). o que pode colocar alguém em risco é decidido por regras simples, que qualquer pessoa pode ler. a IA só escreve o resumo e nunca muda uma nota. o site não usa cookies, não tem rastreamento próprio e não pede cadastro.

o marola não é salva-vidas, não é previsão oficial e não é serviço de alerta. em caso de emergência, o botão "emergência" do mapa mostra os números gratuitos, como o 193 dos bombeiros e guarda-vidas.

## como o site roda

o mapa é estático: nenhum servidor nosso e nenhuma IA trabalham quando você abre a página. a cada 3 horas, uma automação no GitHub roda o marola-app, calcula a nota de cada praia e publica os arquivos. quem entrega o marola.dev é um [Cloudflare Worker](https://github.com/marola-dev/marola-site/blob/main/docs/3-development.md), um pequeno programa na rede da Cloudflare, no [plano gratuito](https://github.com/marola-dev/marola-site/blob/main/AGENTS.md#cost--deployment-safety-hard-rule), e o GitHub Pages fica de reserva. o INEA e o INEMA só respondem a endereços brasileiros, então a automação passa por um proxy: um computador no Brasil, mantido por voluntários, que repassa os pedidos.

os dados devem ir para o Cloudflare R2, um serviço de armazenamento de arquivos, num lago de dados que ainda está sendo montado (mais sobre isso abaixo).

## os repositórios

cada parte do marola é um repositório na organização [marola-dev](https://github.com/marola-dev), com seus próprios testes e versões. uma parte nunca usa o código da outra direto: usa sempre uma versão já publicada.

### [marola](https://github.com/marola-dev/marola)

o repositório principal, que reúne os outros. tem os planos de cada mudança (os MIPs, as propostas de mudança), a lista de fases, as regras de trabalho e o site da documentação. é dele que sai a versão citável no Zenodo.

### [marola-app](https://github.com/marola-dev/marola-app)

o programa principal, em Scala 3 com [Kyo](https://getkyo.io/). busca as praias no OpenStreetMap, o mar e o tempo no Open-Meteo e os boletins de balneabilidade, calcula a nota, aplica o veto de segurança e tem uma linha de comando e um servidor MCP, que deixa assistentes de IA consultarem o marola. a imagem Docker que ele publica é a que monta o mapa.

### [marola-site](https://github.com/marola-dev/marola-site)

o mapa em marola.dev, com o mapa-base do Mapbox. JavaScript puro, sem framework, em português e inglês.

### [marola-oods](https://github.com/marola-dev/marola-oods)

o Open Ocean Data Store: vai guardar a estrutura do lago de dados aberto de praias e de amostras de balneabilidade. ainda não tem dados.

### [marola-ml](https://github.com/marola-dev/marola-ml)

o código em Python que não roda no mapa: compila os prompts com DSPy, mantém o teste de qualidade que um modelo precisa passar antes de ser usado e treina o marola-sea.

### [marola-corpus](https://github.com/marola-dev/marola-corpus)

as anotações sobre o mar de onde o marola tira as respostas, cada uma com a sua fonte.

### [marola-devkit](https://github.com/marola-dev/marola-devkit)

a caixa de ferramentas que todos os repositórios usam: scripts, hooks do git, skills para agentes de IA e a integração contínua compartilhada.

### [agent-skills](https://github.com/marola-dev/agent-skills)

o catálogo das skills de agentes de IA usadas no marola: onde cada uma está, de onde veio e o que já foi testado.

a organização também mantém a [awesome-ocean-science](https://github.com/marola-dev/awesome-ocean-science), uma lista de software, dados e ferramentas abertas sobre o oceano.

## no que estamos trabalhando agora: o lago de dados

hoje, cada atualização do mapa busca as praias e a balneabilidade do zero, e o histórico se perde. o [MIP-0075](https://github.com/marola-dev/marola/blob/main/docs/MIPs/MIP-0075-water-quality-store-r2.md) propõe guardar tudo num lago de dados aberto: um [DuckLake](https://ducklake.select/), com arquivos Parquet e um catálogo DuckDB. o MIP foi escrito para o Backblaze B2, e a [marola#692](https://github.com/marola-dev/marola/pull/692) propõe trocar pelo Cloudflare R2. rotinas semanais do marola-app vão escrever nele, e o marola-oods define a estrutura. primeiro virão as praias, depois a balneabilidade de Santa Catarina, depois a do Rio e a da Bahia.

a estrutura ([marola-oods#22](https://github.com/marola-dev/marola-oods/pull/22)) e a troca para o R2 estão em revisão. o lago ainda não recebeu nenhum dado.

o próximo post explica por que o marola precisa de um lago.

## parceria com a Leave No Trace

a [Leave No Trace](https://lnt.org/), organização sem fins lucrativos que ensina a aproveitar a natureza sem deixar rastro, aceitou o marola no seu programa de parcerias comunitárias, o Community Partnership Program.

o programa abre o material educativo da Leave No Trace aos parceiros e permite que instrutores credenciados deem certificados de curso. o que isso vai mudar no marola vem num próximo post ([#96](https://github.com/marola-dev/marola-site/issues/96)).

o marola segue aberto a parcerias que não envolvem dinheiro com instituições ambientais e com quem possa ceder dados ou capacidade de computação ([sobre](about.html)).

## como acompanhar ou ajudar

use o mapa e avise quando ele errar. abra uma [issue](https://github.com/marola-dev/marola/issues) (um relato de problema), em português ou em inglês, ou pegue uma marcada como [good first issue](https://github.com/search?q=org%3Amarola-dev+is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22&type=issues). dá também para [apoiar o projeto](support.html).
