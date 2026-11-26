title: sobre o marola
description: O que é o marola, por que é aberto e sem fins lucrativos, como funciona por dentro e de onde vêm os dados.

## o que é o marola

::lede imagine um amigo que conhece bem o mar. você pergunta "dá pra nadar amanhã? que horas?". ele olha as ondas, o vento e a maré, vê se a água está própria para banho e até se tem água-viva por perto. depois te diz o melhor horário, e por quê.

esse amigo é o marola. por enquanto, ele é um mapa das praias de Florianópolis, do Rio de Janeiro e de Salvador, e cada praia tem uma nota para hoje e outra para amanhã. ele não inventa nada: todo número vem de dados públicos. quando o assunto é risco, quem decide são regras simples, que qualquer pessoa pode ler. e quando não sabe, ele diz "sem dados".

## por que aberto e sem fins lucrativos

boa parte dos dados do mar brasileiro está na mão de empresas e instituições privadas. sem esses dados, não dá para prever a qualidade da água, os desastres climáticos nem os acidentes ambientais.

por isso o marola é aberto e não tem fins lucrativos. a promessa é devolver tudo para todo mundo, do melhor jeito que a gente conseguir. se a gente fosse só mais uma empresa, ficaria difícil pedir esses dados para quem está com eles.

## balneabilidade primeiro

o saneamento básico no Brasil ainda está longe de ser resolvido. o assunto é grande demais para esta página, mas é ele que define por onde o marola começa: pela qualidade da água. antes do surfe, da pesca ou do mergulho, vem a pergunta "posso entrar nessa água?".

uma das ideias é um ranking nacional de balneabilidade, que já está [em discussão aberta](https://github.com/marola-dev/marola/discussions/676). a gente ainda vai escrever muito sobre isso: quem cuida bem da água, quem cuida mal, como e por quê.

## um super app da água

a gente vive a era dos super apps, e o marola vai acabar virando um super app da água. um lugar só para tudo o que envolve a água: a praia, o mar, a balneabilidade e os riscos. não um app que te dá ferramentas para você se virar, e sim um que te entrega a resposta pronta.

a Sequoia Capital, um dos maiores fundos de investimento do Vale do Silício, chama essa mudança de "serviço como software". o software deixa de vender a ferramenta e passa a entregar o trabalho feito.

> @en
> "A copilot sells the tool. An autopilot sells the work."
> -- Julien Bek, [Services: The New Software](https://sequoiacap.com/article/services-the-new-software), Sequoia Capital, 2026. a ideia vem de [Generative AI's Act o1](https://sequoiacap.com/article/generative-ais-act-o1), de Sonya Huang e Pat Grady, 2024.

## por que código aberto

em 2026, não tem mais motivo para fazer código fechado. com a IA, nunca foi tão fácil criar uma funcionalidade nova, e o código já não é o segredo. o Brasil precisa é de projetos de longo prazo, que não dependam do calendário eleitoral nem morram quando o governo muda. com o código aberto, o projeto segue vivo mesmo depois que quem começou vai embora.

## parcerias sem dinheiro

o marola precisa de computação em nuvem: espaço para guardar os dados e placas de vídeo para treinar e rodar os modelos. mesmo sem fins lucrativos, ele aceita parcerias com empresas que cedam esses recursos, ou dados, sem passar dinheiro. em troca, a empresa ganha um crédito discreto no site. nada de anúncio, banner ou rastreamento.

## parceiros

o marola é parceiro oficial (Proud Partner) do [Leave No Trace](https://lnt.org/), que ensina a aproveitar a natureza sem deixar rastro.

o [OpenDiving](https://opendiving.app/) é um diário de mergulho de código aberto, feito para durar mais que qualquer fabricante de computador de mergulho. os dois projetos usam dados abertos e apontam um para o outro: o OpenDiving lista o marola entre os seus apps parceiros.

## como o marola é montado

o marola é um conjunto de repositórios de código, cada um com uma tarefa:

- **marola-app** junta a previsão do mar, as praias e a balneabilidade, e calcula a nota.
- **marola-site** é o mapa que você está usando.
- **marola-corpus** guarda as anotações sobre o mar, cada uma com a sua fonte.
- **marola-ml** treina e testa a IA antes de ela ir para o marola-app.
- **marola-oods** é um arquivo aberto com o histórico das praias e da água.
- **marola-research** guarda a pesquisa do marola.
- **marola-skills** e **marola-agents** listam as habilidades e os agentes de IA que trabalham no projeto.
- **marola-devkit** reúne as ferramentas que todos os repositórios usam.
- **marola**, o repositório guarda-chuva, tem os planos e as regras, e traz cada um dos outros como submódulo git.

[abrir o diagrama da arquitetura](/architecture) — os repositórios do marola e o que cada um entrega ao seguinte.


mais diagramas: [de onde vêm os dados](/data-flow), [o caminho de um estudo](/studies-flow), [do merge ao marola.dev](/deploy-flow), [como uma mudança chega](/develop-flow).
os repositórios do marola e o que cada um entrega aos outros. a figura é a mesma da [página da organização no GitHub](https://github.com/marola-dev) (fonte: [marola-dev/.github](https://github.com/marola-dev/.github/blob/main/profile/README.md)).

o nome disso é monólito distribuído. monólito porque funciona como uma peça só: um projeto, um plano, um jeito de trabalhar, e as versões das partes andam juntas. distribuído porque cada parte fica no seu próprio repositório, com os seus testes, e lança as suas próprias versões.

a gente fez assim por dois motivos. o primeiro: boa parte do código é escrita e mantida com o Claude, da Anthropic, tanto num Claude Project quanto no Claude Code pelo terminal. o guarda-chuva com submódulos ajuda nisso: o Claude enxerga o projeto inteiro de cima, com os planos e as regras por escrito num lugar só, e mexe num repositório pequeno de cada vez, com os testes daquele repositório. o segundo: cada parte também anda sozinha, até certo ponto. quem só quer os dados de balneabilidade pode usar o marola-oods sem o resto, e um erro num repositório não derruba os outros. uma parte nunca usa o código da outra direto: ela pega uma versão publicada e só troca de versão quando decide trocar.

o site roda num servidor nosso: uma máquina virtual KVM 4 alugada da [Hostinger](https://www.hostinger.com/), no Brasil, configurada com [NixOS](https://nixos.org/). a mesma máquina entrega as páginas, os quadros das praias e os pedaços do mapa de fundo, sem CDN nem outra empresa no meio. ela fica no Brasil porque alguns órgãos estaduais só respondem a endereços brasileiros.

## Claude

boa parte do código do marola é escrita com o Claude, o assistente de IA da Anthropic, num Claude Project: um espaço no claude.ai em que ele lê os repositórios, abre pull requests e conversa com a gente em threads. as configurações desse projeto estão num arquivo aberto, o [CLAUDE_PROJECT.config.md](https://github.com/marola-dev/marola/blob/main/CLAUDE_PROJECT.config.md) (em inglês): as instruções que o Claude segue, os repositórios que ele lê, o ambiente em que ele roda e as rotinas que ele executa sozinho. qualquer pessoa pode ler o arquivo ou montar um projeto igual a partir dele.

## como funciona a nota

cada praia cai numa das cinco faixas da legenda do mapa: **≥70** bom, **40–69** razoável, **1–39** ruim, **0** imprópria, ou **sem dados** quando alguma fonte não respondeu. a nota leva em conta o mar, o vento, as ondas, a maré e a qualidade da água. um modelo de linguagem escreve um resumo curto, e uma segunda revisão automática confere se o resumo bate com os números. a IA só explica: ela nunca muda uma nota nem derruba um alerta.

## de onde vêm os dados

as praias vêm do [OpenStreetMap](https://www.openstreetmap.org/copyright), a previsão do mar e do tempo vem do [Open-Meteo](https://open-meteo.com/), e a balneabilidade, dos boletins oficiais do IMA/SC, do INEA (RJ) e do INEMA (BA). são fontes públicas e gratuitas. o mapa de fundo é do próprio marola: os pedaços do mapa são recortados dos dados do OpenStreetMap com o [Protomaps](https://protomaps.com/), ficam no nosso servidor e são desenhados com o [MapLibre](https://maplibre.org/), uma biblioteca de mapas de código aberto. por enquanto, só as camadas de praias e de balneabilidade estão ligadas. vento, ondas e as imagens de satélite da NASA ([GIBS](https://www.earthdata.nasa.gov/gibs)) chegam em breve.

## privacidade

o marola não usa cookies nem rastreamento próprio. o mapa de fundo vem do servidor do próprio marola: o estilo, os pedaços do mapa e as fontes são arquivos deste site. por isso, desenhar o mapa não avisa mais ninguém de que você passou por aqui. duas coisas chegam a terceiros, e só quando você abre: uma camada de satélite, com imagens que vêm dos servidores da NASA, e o player do Spotify, que carrega do Spotify. nesses dois casos, eles veem o seu endereço IP. a opção "perto de mim" usa a sua localização só dentro do navegador, e ela nunca sai dali.

## quem faz

as pessoas que fazem o marola estão na página de [membros](/members.html), a mesma lista de autores do registro do marola no Zenodo.

a pesquisa do marola está no [marola-research](https://github.com/marola-dev/marola-research/blob/main/README.md). para contribuir ou publicar com a gente, leia a [chamada para contribuição e publicação](https://github.com/marola-dev/marola-research/blob/main/chamada/chamada.pdf) (PDF).

quem pesquisa também pode publicar um estudo aqui. leia os [estudos](/studies) que as pessoas enviaram ou [envie o seu](/submit). o marola não revisa os estudos.

## agradecimentos

a ideia do botão de emergência veio do [swell-floripa](https://swell-floripa.vercel.app/), de Carlos Toledo ([@carlostoledo1891](https://github.com/carlostoledo1891)).

o som das ondas é uma gravação de Luftrum ([freesound](https://freesound.org/s/48412/), licença [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/)), que Porrumentzio editou em loop para o [Blanket](https://github.com/rafaelmardojai/blanket).

Aleksei Vesnin ([@aleskiontherun](https://github.com/aleskiontherun)), do [OpenDiving](https://github.com/opendiving/opendiving), recebeu o marola como app parceiro.

Pedro Veras Guimarães ([@pvguima](https://github.com/pvguima)) dedicou tempo, gentileza e atenção para explicar física de ondas ao fundador do marola.

## como ajudar

use o mapa e avise quando ele errar. conte também o que você vê na água, como água-viva, ou se está faltando alguma praia. abra uma [issue](https://github.com/marola-dev/marola/issues), em português ou em inglês. o código, os planos e cada decisão estão no [GitHub](https://github.com/marola-dev/marola). [a documentação](https://docs.marola.dev/) mostra o que já funciona e o que ainda é plano.
