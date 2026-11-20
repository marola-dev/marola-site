# Sic Mundus Creatus Est

2026-10-09

marola が公開されました。オープンソースで非営利です。Florianópolis、Rio de Janeiro、Salvador のビーチの地図で、今日と明日のスコアを公開データだけから計算しています。最新版の 0.2.1 は10月8日にリリースされました。

::: release v0.2.1 2026-10-08
- marola の引用に3人の新しい著者: Elisa Oliveira、Leonardo Ramos Almeida、Pablo Ribeiro（[#712](https://github.com/marola-dev/marola/pull/712)、[#714](https://github.com/marola-dev/marola/pull/714)）
- AIエージェントのスキルに固定バージョンが付き、毎週更新されるように（[MIP-0080](https://github.com/marola-dev/marola/pull/701)）
- 特定の事業者に依存せず外部の言語モデルを評価する提案（[MIP-0081](https://github.com/marola-dev/marola/pull/704)）
[リリースノート](https://github.com/marola-dev/marola/releases/tag/v0.2.1) · [0.2.0からの変更](https://github.com/marola-dev/marola/compare/v0.2.0...v0.2.1)

## 公式リンク

- 地図: [marola.dev](https://marola.dev/)
- ドキュメント: [docs.marola.dev](https://docs.marola.dev/)
- コード（MITライセンス）: [github.com/marola-dev](https://github.com/marola-dev)
- 引用: Zenodo の [10.5281/zenodo.23224155](https://doi.org/10.5281/zenodo.23224155)。このDOIは常に最新版に解決し、現時点では[0.2.1](https://github.com/marola-dev/marola/releases/tag/v0.2.1)です。[README](https://github.com/marola-dev/marola#how-to-cite)に ABNT、APA、BibTeX の書き方があります。
- marola の言語モデル marola-sea: [marola-ml](https://github.com/marola-dev/marola-ml) で訓練中。今は小さなテスト版のみ
- 公開の対話: [GitHub Discussions](https://github.com/marola-dev/marola/discussions)

## marola は何であり、何でないか

スコアは、海況、風、波、潮汐、そして Santa Catarina（IMA）、Rio de Janeiro（INEA）、Bahia（INEMA）の州環境機関による公式な水質判定を組み合わせます。人を危険にさらしうることはすべて、誰でも読める単純なルールが決めます。AI が書くのは要約だけで、スコアは決して変えません。Cookieなし、独自トラッキングなし、アカウント不要です。

marola は監視員でも、公式予報でも、警報サービスでもありません。緊急時には、地図の緊急ボタンがブラジルの無料緊急通報番号（消防・監視員の193など）を表示します。

## サイトの運営方法

地図は静的です: ページを開いても計算もAIも動きません。1日4回、プロジェクト自身のサーバー（ブラジルにある [Hostinger](https://www.hostinger.com/) の KVM 4 仮想マシン）上の処理が marola-app を実行し、各ビーチのスコアを計算してファイルを公開します。marola.dev を配信するのも同じマシンで、nginx が受け持ち、CDN も Cloudflare も間に入りません。INEA と INEMA はブラジルのアドレスにしか応答しないため、サーバーはブラジルにあり、プロキシは不要です。

データは Cloudflare R2（ファイルストレージサービス）へ、まだ建設中のデータレイクに移る予定です（R2 への移行は [marola#692](https://github.com/marola-dev/marola/pull/692) で受け入れられました; 構造の [marola-oods#22](https://github.com/marola-dev/marola-oods/pull/22) は審査中です。詳しくは下で）。

## リポジトリ

marola の各部品は [marola-dev](https://github.com/marola-dev) 組織内の独立したリポジトリで、それぞれにテストとリリースがあります。ある部品が別の部品のコードを直接使うことはなく、常に公開されたバージョンを使います。

### [marola](https://github.com/marola-dev/marola)

全体をまとめる主リポジトリ。変更の計画（MIP、marola の変更提案）、フェーズの一覧、働き方、ドキュメントサイトを持ち、引用可能なリリースはここから出ます。

### [marola-app](https://github.com/marola-dev/marola-app)

[Kyo](https://getkyo.io/) を使った Scala 3 の主力プログラム。OpenStreetMap からビーチを、Open-Meteo から海と天気を、水質公告を取得し、スコアを計算し、安全のための拒否を適用します。コマンドラインと、AIアシスタントが marola を照会できる MCP サーバーを同梱します。公開する Docker イメージが地図を組み立てます。

### [marola-site](https://github.com/marola-dev/marola-site)

marola.dev の地図。ページは Elm、サーバーと静的ページは Haskell（[ADR 0005](https://github.com/marola-dev/marola-site/blob/main/docs/adr/0005-elm-and-haskell.md)）で、サイト自身の地図の上に載り、Mapbox もトークンもありません。ポルトガル語、英語、日本語、繁体字中国語に対応しています。

### [marola-oods](https://github.com/marola-dev/marola-oods)

Open Ocean Data Store: ビーチと水質サンプルの公開データレイクの構造を保持します。まだデータはありません。

### [marola-ml](https://github.com/marola-dev/marola-ml)

地図では動かない Python のコード: DSPy でプロンプトをコンパイルし、モデルが使われる前に通すべき品質ゲートを管理し、marola-sea を訓練します。

### [marola-corpus](https://github.com/marola-dev/marola-corpus)

marola が答える元になる海についての注釈。それぞれに出典が付きます。

### [marola-devkit](https://github.com/marola-dev/marola-devkit)

全リポジトリが使う道具箱: スクリプト、git フック、AIエージェントのスキル、共有 CI。

### [agent-skills](https://github.com/marola-dev/agent-skills)

marola で使う AI エージェントのスキルの目録: どこにあり、どこから来て、何がテスト済みか。

組織は [awesome-ocean-science](https://github.com/marola-dev/awesome-ocean-science)（海に関するオープンなソフトウェア、データ、道具のリスト）も維持しています。

## 今取り組んでいること: データレイク

今日は地図を更新するたびにビーチと水質をゼロから取得し、履歴は失われています。[MIP-0075](https://github.com/marola-dev/marola/blob/main/docs/MIPs/MIP-0075-water-quality-store-r2.md) は、すべてを公開データレイクに保存することを提案しています: [DuckLake](https://ducklake.select/) — Parquet ファイルと DuckDB カタログ。MIP は Backblaze B2 向けに書かれ、[marola#692](https://github.com/marola-dev/marola/pull/692) が Cloudflare R2 への移行を提案して受け入れられました。marola-app の週次ジョブがレイクに書き込み、構造は marola-oods が定めます。まずビーチ、次に Santa Catarina の水質、その後 Rio と Bahia の順です。

構造（[marola-oods#22](https://github.com/marola-dev/marola-oods/pull/22)）は審査中です。レイクはまだデータを受け取っていません。

次の投稿で、marola にデータレイクが必要な理由を説明します。

## Leave No Trace との提携

自然に痕跡を残さず楽しむ方法を教える非営利団体 [Leave No Trace](https://lnt.org/) が、marola をコミュニティパートナーシップ・プログラムに迎え入れました。

このプログラムは、パートナーに Leave No Trace の教育資料を開放し、認定インストラクターによるコース修了証を可能にします。これが marola に何をもたらすかは、次の投稿で書きます（[#96](https://github.com/marola-dev/marola-site/issues/96)）。

marola は、環境機関や、データ・計算資源を提供できる人々との、お金を介さない提携に引き続き開かれています（[このサイトについて](about.html)）。

## 追いかける、協力する

地図を使い、間違っていたら知らせてください。ポルトガル語でも英語でも [issue](https://github.com/marola-dev/marola/issues) を開くか、[good first issue](https://github.com/search?q=org%3Amarola-dev+is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22&type=issues) のラベルが付いたものに挑戦してください。[プロジェクトを支援](support.html)することもできます。
