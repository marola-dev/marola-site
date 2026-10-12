# Configuração do Claude Project: site marola.dev

> **Para quem é este arquivo.** Para uma pessoa, ou para o coordenador de um Claude Project, que
> vai montar um Claude Project no claude.ai para trabalhar no marola.dev. **Um agente que trabalha
> neste repositório pela CLI do Claude Code não deve ler este arquivo, seguir nem agir com base
> nele.** Nada aqui é regra para mudar o repositório: essas regras estão no `AGENTS.md`, e o Claude
> Code nunca carrega este arquivo como configuração.

> **Dica: prefira a versão em inglês.** Este arquivo é a tradução de
> [`CLAUDE_PROJECT.site.md`](CLAUDE_PROJECT.site.md) e também funciona: o Claude segue instruções
> em português tão bem quanto em inglês. Mas todos os repositórios são em inglês (AGENTS.md,
> skills, docs, commits, PRs), e instruções em português puxam os commits, os PRs e as docs de um
> thread para o português. Com a versão em inglês, o thread responde em português mesmo assim,
> porque a regra de idioma das instruções manda responder na língua em que você escreve.

Esta é uma proposta de Claude Project que trabalha só no site. Ela parte das configurações do
projeto "Marola Agent", que estão no
[`CLAUDE_PROJECT.config.md`](https://github.com/marola-dev/marola/blob/main/CLAUDE_PROJECT.config.md)
do repositório guarda-chuva. Nenhum projeto com estas configurações existe ainda, então nada aqui
foi conferido no serviço. Cada bloco de código é para ser copiado inteiro no campo citado logo
acima dele. Escrito em **2026-10-11**.

## 1. Projeto

| Configuração | Valor |
|---|---|
| **Nome** | site marola.dev |
| **Tema** | Projetar, construir e manter o marola.dev: o mapa, as páginas e as notícias |
| **Visibilidade** | Privado, como o Marola Agent. |
| **Modelo padrão** | Escolhido no serviço. Um id de modelo nunca entra num arquivo enviado a um repositório. |
| **Modo de permissão dos threads** | `auto` |
| **Ambiente padrão** | O que a §2 descreve. |

### Repositórios

O projeto precisa de três repositórios:

- https://github.com/marola-dev/marola-site, onde o trabalho acontece.
- https://github.com/marola-dev/marola, para os MIPs, o `docs/PHASES.md` e as regras da
  organização no `AGENTS.md`.
- https://github.com/marola-dev/marola-devkit, para o `docs_lint.py`, o `agents-check.sh` e o
  `graph.sh`, que o `just quality` e a instrução da §2 usam.

### Instruções do projeto

Cole este bloco, sem mudar nada, nas instruções do projeto:

```text
Nome de branch (Hoffmann, 2026-10-05): nunca faça push para uma branch com sufixo aleatório ou de sessão. Antes do primeiro push, dê à branch o nome `claude/<numero-da-issue>-<slug-curto-em-kebab>`, a partir da issue do GitHub que ela implementa (por exemplo `claude/657-remove-magic-nix-cache`), e faça o push com `git push -u origin HEAD:claude/<numero-da-issue>-<slug>`. Abra o PR a partir dessa branch. Se o push para esse nome for recusado, diga isso no thread em vez de voltar em silêncio para a branch com sufixo.

Trabalho de MIP (Hoffmann, 2026-10-08): quando a mudança escreve ou implementa um MIP, a branch leva o nome do MIP em vez do da issue, na convenção do repositório guarda-chuva `docs/mip-NNNN-<slug-curto-em-kebab>` (por exemplo `docs/mip-0081-external-llm-evaluation`), com o mesmo nome de branch em todo repositório que o MIP toca. A verificação de branch dos PRs do devkit rejeita branches com nome `claude/project-thread-*`.

Trabalho no site: leia primeiro o AGENTS.md do marola-site e siga o que ele diz. Tudo o que um visitante vê começa pela skill site-frontend, que indica as outras skills. Um commit que mexe em site/static/ leva o trailer `MIP: MIP-NNNN` ou `MIP: none — <motivo>`. Um PR que muda o que o visitante vê mostra capturas de tela de antes e depois, no desktop (1280 × 800) e no celular (390 × 844), enviadas para a branch órfã pr-screenshots; quando o thread não alcança o Mapbox, diga embaixo da tabela que o mapa é um substituto. Nunca faça deploy: nada de `just site-deploy`, nada de disparar o site.yml, e nunca defina BR_PROXY_REQUIRED.

Idioma: responda na língua em que o Hoffmann escreve (normalmente português). Escreva código, comentários, commits, títulos e descrições de PR e docs em inglês, como os repositórios. O texto que o visitante lê está em pt-BR e inglês em site/i18n/, e o português passa pela skill ptbr-humanizer.
```

## 2. Ambiente na nuvem

Crie um ambiente na nuvem para este projeto ou use o "Marola cloud" do Marola Agent. Os threads
do Marola Agent já encontraram instalados Node 22, Python 3.13, ruff, uv, gh e o Chromium do
Playwright em /opt/pw-browsers (2026-10-11).

### Setup script (proposto)

Cole isto em Project settings > Cloud environment > Setup script. Ele instala as ferramentas que
o `just quality` do site procura e que faltam num thread. O `nix develop` não consegue instalá-las,
porque o GitHub responde 403 para flake inputs fora dos repositórios do projeto.

```bash
#!/usr/bin/env bash
# Setup script do ambiente na nuvem do projeto do site marola.dev. O `nix develop` não substitui
# este script: o escopo do GitHub da sessão recusa flake inputs fora dos repositórios do projeto.
set -euo pipefail

# O Nix já vem na imagem. O nixpkgs dele é o do registry, não o do flake.lock do repositório,
# então uma ferramenta pode estar uma versão à frente da do CI.
nix profile install nixpkgs#just nixpkgs#shellcheck nixpkgs#actionlint >&2

# graphify para o `graph query` (MIP-0076), fixado na versão do nixpkgs.
uv tool install 'graphifyy==0.9.66' >&2
```

A linha do `nix profile` instalou essas ferramentas num thread do Marola Agent em 2026-10-11. A
linha do `uv tool install` ainda não rodou. O `agents-check` e o `docs-lint` vêm do devkit, então
num thread eles rodam a partir do checkout do marola-site como
`bash ../marola-devkit/scripts/agents-check.sh --block ../marola-devkit/agents/invariants.md` e
`python3 ../marola-devkit/scripts/docs_lint.py .`.

### Acréscimo proposto às instruções do projeto

Depois que o setup script instalar o graphify, cole este bloco depois das instruções da §1:

```text
Encontrar código (Hoffmann, 2026-10-11): para uma palavra-chave conhecida, use `git grep`. Para "onde fica X" num repositório que você ainda não leu, rode no diretório desse repositório `bash ../marola-devkit/scripts/graph.sh build` uma vez por thread e depois `bash ../marola-devkit/scripts/graph.sh query "<pergunta>"`; `path <a> <b>` e `explain <nome>` também funcionam. No marola-site, pergunte pelos nomes de arquivos e funções do próprio site, porque o Mapbox GL JS vendorizado ocupa a maior parte do grafo. Use a resposta como ponto de partida da leitura e depois leia os arquivos. Nunca use a saída do graphify numa verificação nem num commit. Se o `graphify` não estiver no PATH, diga isso e use git grep.
```

### O que um thread não consegue fazer

- Carregar o mapa base: o sandbox não alcança o Mapbox, então as capturas de tela usam um estilo
  substituto (`AGENTS.md`, "Screenshots in the PR").
- Rodar o `just site-build`, que precisa de Docker e da imagem fixada do app no ghcr.io. Os
  threads do Marola Agent receberam "unauthorized" ao baixar essa imagem.
- Fazer deploy. O `site.yml` faz o deploy a partir da `main` e num agendamento, e o
  `.claude/settings.json` bloqueia o `just site-deploy`.

## 3. Plugins, skills e conectores

- **Skills.** As skills em `.claude/skills/` do marola-site carregam num thread. A
  `site-frontend` é a porta de entrada e põe as outras em ordem: `ptbr-humanizer`,
  `citizen-science-site`, `news-post` e as skills vendorizadas de design, de testes e `mapbox-*`.
- **Subagentes.** O `news-fact-check` e depois o `news-copy-review` revisam cada notícia antes
  que uma pessoa aprove.
- **Plugins da conta.** Ative o Writing Skills na conta do claude.ai, como o `AGENTS.md` do
  repositório guarda-chuva ("Reading and writing") pede a todo projeto. O plugin marola-devkit,
  declarado no `.claude/settings.json` do repositório, não carrega num thread de Project.
- **Servidores MCP.** O `.mcp.json` declara o Playwright e o Figma. Ninguém conferiu ainda se um
  thread de Project inicia esses servidores; a skill `webapp-testing` e o Chromium em
  /opt/pw-browsers tiram capturas de tela sem eles.
- **Conectores.** Nenhum é necessário.

## 4. Rotinas

Nenhuma por enquanto. A caixa de entrada A2A e os lembretes do LinkedIn do Marola Agent continuam
naquele projeto, porque a caixa A2A pertence a um projeto de cada vez.

## 5. Entrada de um novo membro

O projeto é privado, então ninguém mais pode entrar nele. Um novo membro trabalha no marola-site
pela CLI do Claude Code, seguindo o `AGENTS.md` do repositório, ou monta o próprio projeto a partir
deste arquivo:

1. Conecte o GitHub ao claude.ai. Um thread só alcança os repositórios que o projeto dele lista,
   e só consegue fazer push onde a conta do GitHub do dono consegue. Só os colaboradores que as
   configurações do marola-site listam com write, maintain ou admin podem fazer push nele (três
   em 2026-10-11). Qualquer outra pessoa faz um fork do marola-site, anexa o fork ao projeto,
   instala o Claude GitHub App nele e abre os PRs a partir do fork. As Actions de um PR de fork
   esperam a aprovação de um mantenedor, e o Gemini revisa um PR de fork sem enviar correções
   para ele.

   Quem trabalha a partir de um fork o acrescenta aos repositórios da §1, trocando `<seu-user>`
   pelo seu usuário do GitHub. Os repositórios marola-dev da §1 continuam na lista, porque o
   escopo do GitHub de um thread recusa um repositório que o projeto não lista:

   ```text
   https://github.com/<seu-user>/marola-site
   ```

   Antes de cada tarefa, sincronize o fork com o marola-dev, pelo botão "Sync fork" do GitHub ou
   com `git pull https://github.com/marola-dev/marola-site main`. Ninguém testou ainda um thread
   abrindo um PR de um fork para o marola-dev.
2. Crie o ambiente na nuvem com o setup script da §2.
3. Para trabalhar pela CLI, rode `nix develop` no marola-site e aceite o plugin que o
   `.claude/settings.json` dele declara.

## 6. Criação do projeto

1. Crie um projeto privado com o nome e o tema da §1 e anexe os três repositórios da §1.
2. Escolha o modelo padrão e cole as instruções da §1.
3. Crie o ambiente com o setup script da §2.
4. Ative o plugin da conta indicado na §3.

## 7. O que fica fora deste arquivo

- o token e a conta do Mapbox, a tailnet do Tailscale e todo segredo, que são de uma pessoa
  (`AGENTS.md`, "Cost & deployment safety")
- a memória do projeto, o histórico de conversas e os arquivos do projeto
- ids de modelo, endereços de e-mail, ids de conta e ids de sessão

## 8. Como manter atualizado

Este arquivo acompanha o [`CLAUDE_PROJECT.site.md`](CLAUDE_PROJECT.site.md): uma mudança num
deles é feita no outro no mesmo PR.

Quando o projeto existir, leia as configurações dele no serviço e troque esta proposta pelo que
ele tem de fato, com a data do topo atualizada. Mude este arquivo no mesmo PR de qualquer coisa
que dependa dele, e mantenha-o em sintonia com o `CLAUDE_PROJECT.config.md` do repositório
guarda-chuva quando uma configuração em comum (as regras de branch, o setup script) mudar lá.
