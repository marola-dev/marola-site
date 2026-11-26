title: marolaについて
description: marolaとは何か、なぜ公開で非営利なのか、内部の仕組み、データの出所。

## marolaとは

::lede 海をよく知る友人を想像してください。あなたは「明日、泳げる？ 何時ごろ？」と尋ねます。彼は波、風、潮位を見て、水が泳ぎやすいか、近くにクラゲがいないかまで確かめ、それからベストの時間帯とその理由を教えてくれます。

この友人がmarolaです。現時点で、marolaは Florianópolis、Rio de Janeiro、Salvador のビーチの地図で、各ビーチに今日と明日のスコアがあります。何も捏造しません: すべての数値は公開データから来ています。リスクに関して決めるのは、誰でも読める単純なルールです。わからないときは「データなし」と言います。

## なぜ公開で非営利なのか

ブラジルの海のデータの多くは、企業や民間機関の手にあります。このデータがなければ、水質も気候災害も環境事故も予測できません。

だからmarolaは公開されており、営利を目的としません。約束は、可能な限り良い形で、すべてをみんなに返すことです。私たちがただの企業の1つだったら、データを持つ人々に提供を求めるのは難しいでしょう。

## 水質を最優先に

ブラジルの上下水道はまだ解決が遠い問題です。このページで語り尽くせる話ではありませんが、marolaが出発点を水質に定めたのはこのためです。サーフィンでも釣りでも潜水でもなく、まず「この水に入れる？」という問いが来ます。

アイデアの1つは全国規模の水質ランキングで、すでに[公開の場で議論されています](https://github.com/marola-dev/marola/discussions/676)。この話題はまだ多く書く予定です: 誰が水を大切に管理し、誰が粗末にし、どうしてか。

## 水のスーパーアプリ

私たちはスーパーアプリの時代を生きており、marolaもいずれ水のスーパーアプリになります。水に関わるすべてを1つの場所に: ビーチ、海、水質、リスク。あなた自身にツールを渡して任せるアプリではなく、答えをそのまま届けるアプリです。

シリコンバレー最大級の投資ファンドの1つである Sequoia Capital は、この変化を「service as software」と呼んでいます。ソフトウェアはツールを売るのをやめ、完成した仕事を届けるようになります。

> @en
> "A copilot sells the tool. An autopilot sells the work."
> -- Julien Bek, [Services: The New Software](https://sequoiacap.com/article/services-the-new-software), Sequoia Capital, 2026. a ideia vem de [Generative AI's Act o1](https://sequoiacap.com/article/generative-ais-act-o1), de Sonya Huang e Pat Grady, 2024.

## なぜコードを公開するのか

2026年、クローズドなコードを書く理由はもうありません。AIのおかげで新しい機能はこれほど簡単に作れたことはなく、コードはもはや秘密ではありません。ブラジルに必要なのは、選挙の暦に左右されず、政権が変わっても死なない、長期的なプロジェクトです。コードが公開されていれば、始めた人が去った後もプロジェクトは生き続けます。

## お金を介さないパートナーシップ

marolaにはクラウドの計算資源が必要です: データを保管する場所と、モデルの学習・実行のためのGPU。非営利でありながら、これらの資源やデータを提供してくれる企業とのパートナーシップを受け入れます。見返りに、企業はサイト内に控えめなクレジットを得ます。広告もバナーもトラッキングもありません。

## パートナー

marolaは、自然に痕跡を残さず楽しむ方法を教える [Leave No Trace](https://lnt.org/) の公式パートナー（Proud Partner）です。

[OpenDiving](https://opendiving.app/) はオープンソースのダイビングログで、どのダイビングコンピューターメーカーよりも長く残るように作られています。2つのプロジェクトは公開データを使い、互いにリンクしています: OpenDiving はパートナーアプリの一覧に marola を載せています。

## marolaの組み立て方

marolaはコードのリポジトリの集まりで、それぞれに役割があります:

- **marola-app** が海の予報、ビーチ、水質を集め、スコアを計算します。
- **marola-site** はあなたが今使っている地図です。
- **marola-corpus** が海に関する注釈を、それぞれに出典つきで保存します。
- **marola-ml** は、AIが marola-app に行く前に学習とテストを行います。
- **marola-oods** はビーチと水の履歴を納める公開アーカイブです。
- **marola-research** は marola の研究を保存します。
- **marola-skills** と **marola-agents** は、プロジェクトで働くAIのスキルとエージェントの一覧です。
- **marola-devkit** は全リポジトリが使う道具箱です。
- **marola** は傘のリポジトリで、計画とルールを持ち、他のすべてをgitサブモジュールとして引き込みます。

[アーキテクチャ図を開く](/architecture) — marola のリポジトリと、それぞれが次に渡すもの。


その他の図: [データの出所](/data-flow)、[研究の流れ](/studies-flow)、[マージから marola.dev まで](/deploy-flow)、[変更が届くまで](/develop-flow)。
marolaのリポジトリと、それぞれが他に渡すもの。図は[GitHubの組織ページ](https://github.com/marola-dev)のものと同じです（出典: [marola-dev/.github](https://github.com/marola-dev/.github/blob/main/profile/README.md)）。

これを分散モノリスと呼びます。モノリスなのは、1つの部品のように動くからです: 1つのプロジェクト、1つの計画、1つの働き方で、各部のバージョンはそろって進みます。分散しているのは、各部が自分のリポジトリに、自分のテストとともにあり、独自のバージョンをリリースするからです。

こうした理由は2つあります。1つ目: コードの多くは Anthropic の Claude とともに書かれ、保守されています。Claude Project でも、ターミナルの Claude Code でもです。サブモジュール付きの傘はここで役立ちます: Claude は計画とルールが1つの場所に書かれた全体を上から俯瞰し、小さなリポジトリを1つずつ、そのリポジトリのテストとともに変更します。2つ目: 各部はある程度、傘の外でも単独で動きます。水質のデータだけ欲しい人は、残りなしで marola-oods を使えますし、1つのリポジトリの誤りが他を倒すこともありません。各部は他のコードを直接読みません: 公開されたバージョンを使い、移行するのは自分で決めたときだけです。

サイトは私たち自身のサーバーで動いています: ブラジルにある [Hostinger](https://www.hostinger.com/) の KVM 4 仮想マシンで、[NixOS](https://nixos.org/) で構成されています。同じマシンがページ、ビーチのボード、背景地図の断片を配信し、CDNも他社も間に入りません。ブラジルに置いているのは、一部の州機関がブラジルのアドレスにのみ応答するからです。

## Claude

marolaのコードの多くは、Anthropic のAIアシスタント Claude とともに Claude Project で書かれています。claude.ai 上のその空間で、Claude はリポジトリを読み、プルリクエストを開き、スレッドで私たちと対話します。そのプロジェクトの設定は公開ファイル [CLAUDE_PROJECT.config.md](https://github.com/marola-dev/marola/blob/main/CLAUDE_PROJECT.config.md)（英語）にあります: Claude が従う指示、読むリポジトリ、実行環境、そして自ら実行するルーチンです。誰でもこのファイルを読み、そこから同じプロジェクトを組み立てられます。

## スコアの仕組み

各ビーチは地図の凡例の5つの帯のどこかに落ちます: **≥70** 良い、**40–69** まずまず、**1–39** 悪い、**0** 不適、または何らかの出所が応答しなかったときの**データなし**。スコアは海、風、波、潮位、水質を考慮します。言語モデルが短い要約を書き、2番目の自動レビューが要約と数値の一致を確認します。AIは説明だけをします: スコアを変えることも、警報を下げることもありません。

## データの出所

ビーチは [OpenStreetMap](https://www.openstreetmap.org/copyright) から、海と天気の予報は [Open-Meteo](https://open-meteo.com/) から、水質は IMA/SC、INEA（RJ）、INEMA（BA）の公式発表から来ています。公開され無料の出所です。背景地図は marola 自身のものです: 地図の断片は [Protomaps](https://protomaps.com/) で OpenStreetMap のデータから切り出され、私たちのサーバーに置かれ、オープンソースの地図ライブラリ [MapLibre](https://maplibre.org/) で描かれます。現時点で有効なのはビーチと水質のレイヤーだけです。風、波、NASA の衛星画像（[GIBS](https://www.earthdata.nasa.gov/gibs)）は近日中に加わります。

## プライバシー

marolaはCookieも独自トラッキングも使いません。背景地図は marola 自身のサーバーから来ます: スタイルも断片もフォントもこのサイトのファイルです。だから地図を描いても、あなたがここを訪れたことは他の誰にも伝わりません。第三者に届くのは2つだけで、どちらもあなたが開いたときだけです: 衛星レイヤー（画像はNASAのサーバーから）と、Spotifyから読み込まれるプレーヤーです。この2つの場合に限り、彼らはあなたのIPアドレスを見ます。「現在地近く」オプションは、位置情報をブラウザの中だけで使い、外に出しません。

## 作っている人

marolaを作っている人々は[メンバーのページ](/members.html)にいます。Zenodo の marola 登録の著者一覧と同じです。

marola の研究は [marola-research](https://github.com/marola-dev/marola-research/blob/main/README.md) にあります。参加や共著を希望する方は、[投稿と出版の呼びかけ](https://github.com/marola-dev/marola-research/blob/main/chamada/chamada.pdf)（PDF）をお読みください。

研究している人なら、ここに研究を公開することもできます。みんなが送った[研究](/studies)を読むか、[あなたの研究を送って](/submit)ください。marola は研究を査読しません。

## 謝辞

緊急ボタンのアイデアは、Carlos Toledo（[@carlostoledo1891](https://github.com/carlostoledo1891)）の [swell-floripa](https://swell-floripa.vercel.app/) から来ています。

波の音は Luftrum の録音（[freesound](https://freesound.org/s/48412/)、[CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) ライセンス）で、Porrumentzio が [Blanket](https://github.com/rafaelmardojai/blanket) のためにループ編集したものです。

[OpenDiving](https://github.com/opendiving/opendiving) の Aleksei Vesnin（[@aleskiontherun](https://github.com/aleskiontherun)）が、marola をパートナーアプリとして迎え入れました。

Pedro Veras Guimarães（[@pvguima](https://github.com/pvguima)）は、marola の創設者に波の物理を教えるために時間と親切さを注ぎました。

Fabio Nascimento には、友情と、LIOC（海洋計測機器研究所）で2年間 marola の創設者に付き合ってくれたことに感謝します。そこで10年以上前に、Luiz Felipe（[@lfelipem](https://github.com/lfelipem)）と一緒にプログラミングを学びました。当時のコードは [legacy-CSUB](https://github.com/h0ffmann/legacy-CSUB) にあります。

UFSC の [ondaseventos.ufsc.br](https://ondaseventos.ufsc.br/) プロジェクトの他の同僚、そしてその忍耐に感謝します: Alicia、Carla、Ricardo。





## 協力の方法

地図を使い、間違っていたら教えてください。クラゲなど海で見たものや、足りないビーチも知らせてください。[issue](https://github.com/marola-dev/marola/issues)を、日本語でも英語でも開いてください。コード、計画、それぞれの決定はすべて[GitHub](https://github.com/marola-dev)にあります。[ドキュメント](https://docs.marola.dev/)に、動いているものとまだ計画のものが書かれています。
