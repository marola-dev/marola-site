-- | The pages the server renders: submit, studies, a study, the account, the report form, the Atom
-- feed. Every page goes through 'Layout.page' and the Vdom, which
-- escapes text and attribute values, so no study text can add markup. No script and no inline style.
--
-- Every string the page owns is in four languages (MIP-0054 5.5): pt-BR the owner manages, en is
-- the ASD-STE100 pass after it, and ja and zh-Hant are the LLM passes.
module Marola.Server.Views
  ( url,
    notice,
    loginPath,
    submitPage,
    studiesPage,
    studyPage,
    accountPage,
    reasons,
    reportPage,
    thanksPage,
    messagePage,
    atom,
  )
where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Marola.Layout (Language (..), Locale (..), PageHead (..))
import Marola.Layout qualified as Layout
import Marola.Server.Messages qualified as Messages
import Marola.Server.StudyStore (Account (..), KeyInfo (..))
import Marola.Study hiding (notice)
import Marola.Utf16 qualified as U
import Marola.Vdom

tr :: Locale -> Text -> Text -> Text -> Text -> Text
tr loc pt en ja zh = case loc.language of
  En -> en
  Ja -> ja
  ZhHant -> zh
  PtBr -> pt

-- | The address of a page in the language of the locale.
url :: Locale -> Text -> Text
url loc p = case loc.language of
  En -> "/en" <> p
  Ja -> "/ja" <> p
  ZhHant -> "/zh-Hant" <> p
  PtBr -> p

p_ :: [Node] -> Node
p_ = el "p" []

h2, h3 :: Text -> Node
h2 s = el "h2" [] [text s]
h3 s = el "h3" [] [text s]

link :: Text -> [Node] -> Node
link href = el "a" [attr "href" href]

-- | A link that acts: drawn as a pill; @primary@ is the one filled action of a page.
pill, primary :: Text -> Text -> Node
pill href label = el "a" [cls "pill", attr "href" href] [text label]
primary href label = el "a" [cls "pill primary", attr "href" href] [text label]

-- | The eyebrow of a page outside the nav's sections; the layout writes the others'.
eyebrow :: Text -> Node
eyebrow s = el "p" [cls "eyebrow"] [text ("marola · " <> s)]

-- | A line of facts in the mono face: dates, places, hashes.
meta :: [Node] -> Node
meta = el "p" [cls "meta"]

-- | A link a visitor typed: only an https address becomes a link, with no referrer or ranking.
outside :: Text -> Text -> Node
outside href label = case httpsLink href of
  Just safe -> el "a" [attr "href" safe, attr "rel" "noopener noreferrer nofollow ugc"] [text label]
  Nothing -> text label

notice :: Locale -> Text
notice loc =
  tr
    loc
    "Sem revisão. Não é aconselhamento médico."
    "Not reviewed. Not medical advice."
    "未審査。医学的アドバイスではありません。"
    "未經審查。並非醫療建議。"

headOf :: Text -> Text -> Text -> Bool -> PageHead
headOf slug title description noIndex =
  PageHead
    { slug = slug,
      title = title <> " | marola",
      description = description,
      noIndex = noIndex,
      canonical = True,
      current = Just "studies",
      dynamic = True
    }

render :: Locale -> PageHead -> [Node] -> Text
render loc pg children = Layout.page loc pg [el "article" [cls "about-body", attr "lang" (Layout.languageTag loc.language)] children]

-- ---- names ---------------------------------------------------------------------------------------

areaLabel :: Locale -> Area -> Text
areaLabel loc = \case
  Rio -> "Rio de Janeiro"
  Floripa -> "Florianópolis"
  Salvador -> "Salvador"
  OtherArea -> tr loc "Outra área" "Another area" "他の海域" "其他地區"

topicLabel :: Locale -> Topic -> Text
topicLabel loc = \case
  WaterQuality -> tr loc "Qualidade da água" "Water quality" "水質" "水質"
  Waves -> tr loc "Ondas" "Waves" "波浪" "波浪"
  WindTopic -> tr loc "Vento" "Wind" "風" "風"
  TrailsTopic -> tr loc "Trilhas" "Trails" "歩道" "步道"
  Ecology -> tr loc "Ecologia" "Ecology" "生態" "生態"
  Safety -> tr loc "Segurança" "Safety" "安全" "安全"
  DataTopic -> tr loc "Dados" "Data" "データ" "資料"
  OtherTopic -> tr loc "Outro" "Other" "その他" "其他"

levelLabel :: Locale -> AiContribution -> Text
levelLabel loc = \case
  NoAi -> tr loc "Nenhuma IA" "No AI" "AI不使用" "未使用 AI"
  LanguageEditing -> tr loc "IA só revisou o texto" "AI edited the language" "AIは文章の推敲のみ" "AI 僅潤飾文字"
  AnalysisAssistance -> tr loc "IA ajudou na análise" "AI helped with the analysis" "AIが分析を支援" "AI 協助分析"
  Drafting -> tr loc "IA escreveu partes do texto" "AI drafted parts of the text" "AIが一部を執筆" "AI 撰寫部分內容"
  Substantial -> tr loc "IA fez a maior parte" "AI did most of the work" "AIが大部分を行った" "AI 完成大部分工作"
  Autonomous -> tr loc "IA fez tudo sozinha" "AI did all of it" "AIがすべてを行った" "AI 完成全部工作"

levelText :: Locale -> AiContribution -> Text
levelText loc l = case l of
  NoAi -> case loc.language of
    En -> levelMeaning l
    Ja -> "AIシステムは関与していません。"
    ZhHant -> "沒有任何 AI 系統參與。"
    PtBr -> "Nenhum sistema de IA participou."
  LanguageEditing -> case loc.language of
    En -> levelMeaning l
    Ja -> "AIシステムが文章を修正または翻訳しました。考え方と結果は著者によるものです。"
    ZhHant -> "AI 系統修正或翻譯了文字。想法與結果皆出自作者。"
    PtBr -> "Um sistema de IA corrigiu ou traduziu o texto. As ideias e os resultados são dos autores."
  AnalysisAssistance -> case loc.language of
    En -> levelMeaning l
    Ja -> "AIシステムがコード、データまたは統計を支援しました。著者が結果を確認しました。"
    ZhHant -> "AI 系統協助了程式、資料或統計。作者已查核結果。"
    PtBr -> "Um sistema de IA ajudou com código, dados ou estatística. Os autores conferiram o resultado."
  Drafting -> case loc.language of
    En -> levelMeaning l
    Ja -> "AIシステムが文章の一部を書きました。著者が計画し、編集し、確認しました。"
    ZhHant -> "AI 系統撰寫了部分文字。作者規劃、編輯並查核。"
    PtBr -> "Um sistema de IA escreveu partes do texto. Os autores planejaram, editaram e conferiram."
  Substantial -> case loc.language of
    En -> levelMeaning l
    Ja -> "AIシステムが分析や執筆の大部分を行いました。著者が指揮し、確認しました。"
    ZhHant -> "AI 系統完成了分析或寫作的大部分。作者主導並查核。"
    PtBr -> "Um sistema de IA fez a maior parte da análise ou da escrita. Os autores orientaram e conferiram."
  Autonomous -> case loc.language of
    En -> levelMeaning l
    Ja -> "AIシステムが質問からファイルまで、人間の工程を挟まずに作業しました。"
    ZhHant -> "AI 系統從提問到產出檔案，全程沒有人類步驟。"
    PtBr -> "Um sistema de IA fez o trabalho sem nenhuma etapa humana entre a pergunta e o arquivo."

date :: Text -> Text
date utc = if T.length utc >= 10 then T.take 10 utc else utc

-- ---- shared pieces -------------------------------------------------------------------------------

postForm :: Locale -> Text -> Text -> [Attr] -> [Node] -> Node
postForm loc action csrf extra children =
  el
    "form"
    ([attr "method" "POST", attr "action" (url loc action)] <> extra)
    (el "input" [attr "type" "hidden", attr "name" "csrf", attr "value" csrf] [] : children)

button :: Text -> Node
button label = el "button" [attr "type" "submit"] [text label]

errorList :: Locale -> [FieldError] -> Text -> [Node]
errorList loc errors f =
  [ el "p" [cls "field-error", attr "role" "alert"] [text (Messages.text loc.language e)]
  | e <- errors,
    e.field == f
  ]

alert :: Text -> Node
alert s = el "p" [cls "field-error", attr "role" "alert"] [text s]

-- | "not reviewed" as a status pill: a dot and the words.
badge :: Locale -> Node
badge loc =
  el "span" [cls "status warn"] [el "i" [] [], text (tr loc "sem revisão" "not reviewed" "未審査" "未審查")]

-- | The notice every study carries, as a banner.
banner :: Locale -> [Node] -> Node
banner loc more = el "p" [cls "notice", attr "role" "note"] ([badge loc, el "span" [] [text (notice loc)]] <> more)

tombstone :: Text -> Node
tombstone s = el "span" [cls "status off"] [el "i" [] [], text s]

-- ---- /submit -------------------------------------------------------------------------------------

loginPath :: Locale -> Text
loginPath loc =
  "/auth/github/login"
    <> case loc.language of
      En -> "?lang=en"
      Ja -> "?lang=ja"
      ZhHant -> "?lang=zh-Hant"
      PtBr -> ""

submitPage :: Locale -> Maybe Text -> Map.Map Text Text -> [FieldError] -> Text
submitPage loc csrf values errors =
  let value n = Map.findWithDefault "" n values
      fieldNode n label help control =
        el "label" [] ([el "span" [] [text label]] <> [el "small" [] [text help] | help /= ""] <> [control] <> errorList loc errors n)
      input n kind (maxLength :: Int) =
        el "input" [attr "type" kind, attr "name" n, attr "value" (value n), attr "maxlength" (T.pack (show maxLength))] []
      area n (rows :: Int) = el "textarea" [attr "name" n, attr "rows" (T.pack (show rows))] [text (value n)]
      select n options =
        el "select" [attr "name" n] [el "option" ([attr "value" v] <> [attr "selected" "" | value n == v]) [text label] | (v, label) <- options]
      formNode token =
        postForm
          loc
          "/submit"
          token
          [cls "contact", attr "enctype" "multipart/form-data"]
          ( [ fieldNode
                "title"
                (tr loc "Título" "Title" "タイトル" "標題")
                ""
                (input "title" "text" titleMax),
              fieldNode
                "authors"
                (tr loc "Autores" "Authors" "著者" "作者")
                (tr loc "Um autor por linha. Para o ORCID: Nome | 0000-0002-1825-0097" "One author per line. For the ORCID: Name | 0000-0002-1825-0097" "1行に1著者。ORCIDの書き方: 名前 | 0000-0002-1825-0097" "每行一位作者。ORCID 格式：姓名 | 0000-0002-1825-0097")
                (area "authors" 4),
              fieldNode
                "abstract"
                (tr loc "Resumo" "Abstract" "要旨" "摘要")
                (tr loc "De 100 a 4000 caracteres." "From 100 to 4000 characters." "100〜4000文字。" "100 至 4000 字。")
                (area "abstract" 8),
              fieldNode "area" (tr loc "Área" "Area" "海域" "地區") "" (select "area" [(areaName a, areaLabel loc a) | a <- allAreas]),
              fieldNode "topic" (tr loc "Tema" "Topic" "テーマ" "主題") "" (select "topic" [(topicName t, topicLabel loc t) | t <- allTopics]),
              fieldNode
                "sources"
                (tr loc "Fontes" "Sources" "参照" "參考來源")
                (tr loc "Um link https por linha, até 10. Pode ficar vazio." "One https link per line, up to 10. May be empty." "1行に1つのhttpsリンク、最大10行。空でもかまいません。" "每行一個 https 連結，最多 10 個。可留空。")
                (area "sources" 3),
              fieldNode
                "repository"
                (tr loc "Repositório do código" "Code repository" "コードリポジトリ" "程式碼儲存庫")
                (tr loc "Obrigatório: o link https do repositório no GitHub, https://github.com/autor/projeto." "Required: the https link of the repository on GitHub, https://github.com/author/project." "必須: GitHubリポジトリのhttpsリンク、https://github.com/author/project。" "必填: GitHub 儲存庫的 https 連結，https://github.com/author/project。")
                (input "repository" "url" linkMax),
              fieldNode
                "archive"
                (tr loc "Arquivo do estudo" "The study's archive" "研究のアーカイブ" "研究的封存")
                (tr loc "Obrigatório: o link https do estudo no Zenodo, no arXiv ou no aiXiv." "Required: the https link of the study on Zenodo, arXiv or aiXiv." "必須: Zenodo、arXivまたはaiXiv上の研究のhttpsリンク。" "必填: 研究在 Zenodo、arXiv 或 aiXiv 上的 https 連結。")
                (input "archive" "url" linkMax),
              fieldNode
                "licence"
                (tr loc "Licença do arquivo" "Licence of the file" "ファイルのライセンス" "檔案的授權條款")
                (tr loc "O marola guarda e mostra o arquivo, por isso só aceita licenças abertas." "marola stores and shows the file, so it accepts open licences only." "marolaはファイルを保存して公開するため、オープンライセンスのみ受け付けます。" "marola 會儲存並公開檔案，因此只接受開放授權條款。")
                (select "licence" [(l, l) | l <- licenceValues]),
              fieldNode
                "ai_contribution"
                (tr loc "Quanto a IA fez" "How much the AI did" "AIの関与度" "AI 的參與程度")
                (tr loc "Você declara; o marola não confere." "You state it; marola does not check it." "あなたが宣言します。marolaは確認しません。" "由你自行聲明；marola 不查核。")
                (select "ai_contribution" [(levelName l, levelLabel loc l) | l <- allLevels]),
              fieldNode
                "ai_models"
                (tr loc "Modelos de IA usados" "AI models used" "使用したAIモデル" "使用的 AI 模型")
                (tr loc "Opcional." "Optional." "任意。" "選填。")
                (input "ai_models" "text" aiModelsMax),
              fieldNode
                "ai_process"
                (tr loc "Como a IA foi usada" "How the AI was used" "AIの使い方" "AI 的使用方式")
                (tr loc "Obrigatório se alguma IA participou." "Required if any AI took part." "AIが関与した場合は必須。" "若有 AI 參與則必填。")
                (area "ai_process" 4),
              fieldNode
                "rights"
                (tr loc "Direitos" "Rights" "権利" "權利")
                ""
                ( el
                    "span"
                    [cls "check"]
                    [ el "input" ([attr "type" "checkbox", attr "name" "rights", attr "value" "true"] <> [attr "checked" "" | value "rights" == "true"]) [],
                      text
                        ( " "
                            <> tr
                              loc
                              "Tenho o direito de publicar este arquivo com a licença que escolhi."
                              "I have the right to publish this file under the licence I chose."
                              "選んだライセンスのもとでこのファイルを公開する権利があります。"
                              "我有權以所選的授權條款公開這個檔案。"
                            <> " "
                        ),
                      link (url loc "/privacy") [text (tr loc "Privacidade" "Privacy" "プライバシー" "隱私")],
                      text " · ",
                      link (url loc "/takedown") [text (tr loc "Remoção" "Takedown" "削除依頼" "下架")]
                    ]
                ),
              fieldNode
                "pdf"
                (tr loc "Arquivo PDF" "PDF file" "PDFファイル" "PDF 檔案")
                (tr loc "Até 20 MB, sem script nem anexo." "Up to 20 MB, with no script and no attachment." "最大20 MB。スクリプトや添付ファイルは不可。" "最大 20 MB，不含指令碼或附件。")
                (el "input" [attr "type" "file", attr "name" "pdf", attr "accept" "application/pdf"] [])
            ]
              <> [ el "div" [cls "field-error"] (errorList loc errors "request" <> errorList loc errors "id"),
                   button (tr loc "Publicar" "Publish" "公開する" "發布")
                 ]
          )
      li s = el "li" [] [text s]
      top =
        [ eyebrow (tr loc "estudos" "studies" "研究" "研究"),
          h2 (tr loc "Enviar um estudo" "Submit a study" "研究を投稿する" "提交研究"),
          el
            "p"
            [cls "lede"]
            [ text
                ( tr
                    loc
                    "Qualquer pessoa com uma conta do GitHub de pelo menos 7 dias pode publicar um estudo sobre o mar, a costa e a água. O estudo fica público na hora, com o aviso \"sem revisão, não é aconselhamento médico\"."
                    "Anyone with a GitHub account that is at least 7 days old can publish a study about the sea, the coast and the water. The study is public at once, with the notice \"not reviewed, not medical advice\"."
                    "GitHubアカウントを7日以上持つ人なら誰でも、海や海岸や水に関する研究を公開できます。研究は直ちに公開され、「未審査・医学的アドバイスではありません」の注意とともに示されます。"
                    "任何 GitHub 帳號滿 7 天的人，都可以發布關於海洋、海岸與水的研究。研究即時公開，並標示「未經審查，並非醫療建議」。"
                )
            ],
          h3 (tr loc "O que o marola publica" "What marola publishes" "marolaが公開するもの" "marola 會公開什麼"),
          el
            "ul"
            []
            [ li
                ( tr
                    loc
                    "O PDF, o título, os autores, o resumo, as fontes e a licença, como você enviou."
                    "The PDF, the title, the authors, the abstract, the sources and the licence, as you sent them."
                    "送信されたままのPDF、タイトル、著者、要旨、参照、ライセンス。"
                    "依你送出的原樣: PDF、標題、作者、摘要、參考來源與授權條款。"
                ),
              li
                ( tr
                    loc
                    "Seu usuário do GitHub, como autor do envio. Nenhum e-mail e nenhum endereço de IP é guardado."
                    "Your GitHub login, as the sender. No email and no IP address is stored."
                    "送信者としてのGitHubユーザー名。メールアドレスもIPアドレスも保存しません。"
                    "你的 GitHub 帳號作為提交者。不儲存電子郵件，也不儲存 IP 位址。"
                )
            ],
          h3 (tr loc "O que o marola não faz" "What marola does not do" "marolaがしないこと" "marola 不會做什麼"),
          el
            "ul"
            []
            [ li
                ( tr
                    loc
                    "Não revisa nem confere o estudo. Não é aconselhamento médico."
                    "It does not review or check the study. It is not medical advice."
                    "研究を査読も検証もしません。医学的アドバイスではありません。"
                    "不審查、不驗證研究。並非醫療建議。"
                ),
              li
                ( tr
                    loc
                    "A equipe pode esconder um estudo. Ele fica na lista com o hash, a data e o motivo, sem texto e sem arquivo."
                    "The team can hide a study. It stays in the list with its hash, its date and a reason, with no text and no file."
                    "チームは研究を非公開にできます。一覧にはハッシュ、日付、理由だけが残り、本文もファイルも残りません。"
                    "團隊可以隱藏一篇研究。列表只保留雜湊值、日期與理由，不保留文字與檔案。"
                )
            ],
          h3 (tr loc "Quanto a IA fez" "How much the AI did" "AIの関与度" "AI 的參與程度"),
          el "dl" [cls "levels"] (concat [[el "dt" [] [text (levelLabel loc l)], el "dd" [] [text (levelText loc l)]] | l <- allLevels])
        ]
      body = case csrf of
        Just token -> [formNode token]
        Nothing ->
          [ el
              "div"
              [cls "panel"]
              [ p_
                  [ text
                      ( tr
                          loc
                          "Para enviar, entre com o GitHub. O marola lê só o seu perfil público (número, usuário e data de criação)."
                          "To submit, log in with GitHub. marola reads only your public profile (number, login and creation date)."
                          "投稿するにはGitHubでログインしてください。marolaは公開プロフィール（番号、ユーザー名、作成日）しか読みません。"
                          "如要提交，請用 GitHub 登入。marola 只讀取你的公開資料（編號、帳號與建立日期）。"
                      )
                  ],
                p_ [primary (loginPath loc) (tr loc "Entrar com o GitHub" "Log in with GitHub" "GitHubでログイン" "用 GitHub 登入")]
              ]
          ]
      agents =
        [ h3 (tr loc "Para agentes" "For agents" "エージェント向け" "給代理程式"),
          p_
            [ text
                ( tr
                    loc
                    "Um agente envia pela API, com uma chave que você cria na sua conta. As regras estão em "
                    "An agent submits through the API, with a key you make in your account. The rules are in "
                    "エージェントはAPIで投稿します。アカウントで作成したキーを使います。規則は "
                    "代理程式透過 API 提交，使用你在帳戶中建立的金鑰。規則見 "
                ),
              link "/api/v1/skill.md" [text "/api/v1/skill.md"],
              text "."
            ]
        ]
      pg =
        ( headOf
            "submit"
            (tr loc "Enviar um estudo" "Submit a study" "研究を投稿する" "提交研究")
            (tr loc "Publique um estudo sobre o mar. Sem revisão." "Publish a study about the sea. Not reviewed." "海に関する研究を公開してください。未審査。" "發布關於海洋的研究。未經審查。")
            False
        )
          { current = Nothing
          }
   in render loc pg (top <> body <> agents)

-- ---- /studies ------------------------------------------------------------------------------------

row :: Locale -> Record -> Node
row loc r =
  let s = r.submission
   in el
        "li"
        [cls "study"]
        [ el "h3" [] [link (url loc (urlOf r.id)) [text s.title]],
          el "p" [cls "study-authors"] [text (T.intercalate ", " [a.name | a <- s.authors])],
          meta
            [ badge loc,
              el "span" [cls "tag"] [text (areaLabel loc s.area)],
              el "span" [cls "tag"] [text (topicLabel loc s.topic)],
              el "time" [attr "datetime" (date r.receivedUtc)] [text (date r.receivedUtc)],
              el "code" [] [text (T.take 12 r.sha256)]
            ]
        ]

studiesPage :: Locale -> [Record] -> Maybe Area -> Maybe Topic -> Maybe Text -> Text
studiesPage loc studies ar tp next =
  let chosen n cur options anyLabel =
        el
          "label"
          []
          [ el "span" [] [text anyLabel],
            el
              "select"
              [attr "name" n]
              ( el "option" [attr "value" ""] [text "-"]
                  : [el "option" ([attr "value" v] <> [attr "selected" "" | cur == Just v]) [text label] | (v, label) <- options]
              )
          ]
      filters =
        el
          "form"
          [attr "method" "GET", attr "action" (url loc "/studies"), cls "contact filters"]
          [ chosen "area" (areaName <$> ar) [(areaName a, areaLabel loc a) | a <- allAreas] (tr loc "Área" "Area" "海域" "地區"),
            chosen "topic" (topicName <$> tp) [(topicName t, topicLabel loc t) | t <- allTopics] (tr loc "Tema" "Topic" "テーマ" "主題"),
            button (tr loc "Filtrar" "Filter" "絞り込む" "篩選")
          ]
      more = case next of
        Just lastId ->
          let q =
                T.intercalate
                  "&"
                  ( ["before=" <> lastId]
                      <> maybe [] (\a -> ["area=" <> areaName a]) ar
                      <> maybe [] (\t -> ["topic=" <> topicName t]) tp
                  )
           in [p_ [pill (url loc "/studies" <> "?" <> q) (tr loc "Mais antigos" "Older" "もっと前の研究" "更早的研究")]]
        Nothing -> []
      pg =
        headOf
          "studies"
          (tr loc "Estudos" "Studies" "研究" "研究")
          (tr loc "Estudos enviados por quem pesquisa o mar. Sem revisão." "Studies sent by people who research the sea. Not reviewed." "海を研究する人々が送った研究。未審査。" "由海洋研究者提交的研究。未經審查。")
          False
   in render
        loc
        pg
        ( [ h2 (tr loc "Estudos" "Studies" "研究" "研究"),
            banner loc [],
            p_ [primary (url loc "/submit") (tr loc "Enviar um estudo" "Submit a study" "研究を投稿する" "提交研究")],
            filters
          ]
            <> ( if null studies
                   then [el "p" [cls "empty"] [text (tr loc "Nenhum estudo ainda." "No studies yet." "まだ研究はありません。" "目前沒有研究。")]]
                   else [el "ul" [cls "studies"] (map (row loc) studies)]
               )
            <> more
        )

-- ---- /studies/<id> -------------------------------------------------------------------------------

studyPage :: Locale -> Record -> Text
studyPage loc r = case r.status of
  Hidden ->
    let pg =
          headOf
            ("studies/" <> r.id)
            (tr loc "Estudo escondido" "Hidden study" "非公開の研究" "已隱藏的研究")
            (tr loc "Este estudo foi escondido." "This study was hidden." "この研究は非公開にされました。" "這篇研究已被隱藏。")
            True
        dt s = el "dt" [] [text s]
        dd ns = el "dd" [] ns
     in render
          loc
          pg
          [ h2 (tr loc "Estudo escondido" "Hidden study" "非公開の研究" "已隱藏的研究"),
            p_ [tombstone (tr loc "escondido" "hidden" "非公開" "已隱藏")],
            p_
              [ text
                  ( tr
                      loc
                      "Este estudo não está mais público. Ficam só o número, o hash, a data e o motivo."
                      "This study is no longer public. Only its id, its hash, its date and the reason remain."
                      "この研究は公開されていません。番号、ハッシュ、日付、理由だけが残ります。"
                      "這篇研究已不再公開。只保留編號、雜湊值、日期與理由。"
                  )
              ],
            el
              "dl"
              [cls "facts"]
              [ dt "id",
                dd [el "code" [] [text r.id]],
                dt "SHA-256",
                dd [el "code" [] [text r.sha256]],
                dt (tr loc "Recebido em" "Received on" "受領日" "收件日期"),
                dd [text r.receivedUtc],
                dt (tr loc "Escondido em" "Hidden on" "非公開日" "隱藏日期"),
                dd [text (maybe "" id r.hiddenUtc)],
                dt (tr loc "Motivo" "Reason" "理由" "理由"),
                dd [text (maybe "" id r.hiddenReason)]
              ]
          ]
  Public ->
    let s = r.submission
        pg = headOf ("studies/" <> r.id) s.title (U.take 160 s.abstract) False
        authorsNodes =
          [ el "li" [] ([text a.name] <> maybe [] (\o -> [text " ", outside ("https://orcid.org/" <> o) ("ORCID " <> o)]) a.orcid)
          | a <- s.authors
          ]
     in render
          loc
          pg
          ( [ el "h2" [cls "study-title"] [text s.title],
              banner loc [],
              el "ul" [cls "authors"] authorsNodes,
              meta
                [ el "span" [cls "tag"] [text (areaLabel loc s.area)],
                  el "span" [cls "tag"] [text (topicLabel loc s.topic)],
                  el "time" [attr "datetime" (date r.receivedUtc)] [text (date r.receivedUtc)]
                ],
              h3 (tr loc "Resumo" "Abstract" "要旨" "摘要"),
              p_ [text s.abstract]
            ]
              <> ( if null s.sources
                     then []
                     else [h3 (tr loc "Fontes" "Sources" "参照" "參考來源"), el "ul" [] [el "li" [] [outside u u] | u <- s.sources]]
                 )
              <> maybe [] (\repo -> [h3 (tr loc "Código" "Code" "コード" "程式碼"), p_ [outside repo repo]]) s.repository
              <> maybe [] (\a -> [h3 (tr loc "Arquivo" "Archive" "アーカイブ" "封存"), p_ [outside a a]]) s.archive
              <> [ h3 (tr loc "Licença" "Licence" "ライセンス" "授權條款"),
                   p_ [text (licenceName s.licence)],
                   h3 (tr loc "Declaração sobre IA" "AI declaration" "AIに関する宣言" "AI 聲明"),
                   p_ [text (levelLabel loc s.aiContribution <> ". " <> levelText loc s.aiContribution)],
                   p_ [text (tr loc "Modelos: " "Models: " "モデル: " "模型: " <> (if T.null s.aiModels then "-" else s.aiModels))],
                   p_ [text s.aiProcess],
                   h3 (tr loc "O arquivo" "The file" "ファイル" "檔案"),
                   p_ [primary (pdfUrlOf r.id) (tr loc "Abrir o PDF" "Open the PDF" "PDFを開く" "開啟 PDF")],
                   meta [text "SHA-256: ", el "code" [] [text r.sha256]],
                   meta [text (tr loc "Enviado por " "Sent by " "送信者: " "提交者: " <> r.authorLogin <> ", " <> r.receivedUtc)],
                   p_ [pill (url loc ("/report/" <> r.id)) (tr loc "Denunciar este estudo" "Report this study" "この研究を通報" "檢舉這篇研究")]
                 ]
          )

-- ---- /account ------------------------------------------------------------------------------------

accountPage :: Locale -> Account -> Text -> [KeyInfo] -> [Record] -> Maybe Text -> Bool -> Bool -> Text
accountPage loc account csrf keys studies newKey keyError deleteError =
  let pg = (headOf "account" (tr loc "Sua conta" "Your account" "あなたのアカウント" "你的帳戶") "" True) {current = Nothing}
      keyRow k =
        el
          "li"
          []
          [ el "span" [cls "row-main"] [text (tr loc "Chave " "Key " "キー " "金鑰 " <> T.pack (show k.id) <> ", " <> date k.createdUtc <> " ")],
            case k.revokedUtc of
              Just _ -> tombstone (tr loc "(revogada)" "(revoked)" "（失効）" "（已撤銷）")
              Nothing -> postForm loc ("/account/keys/" <> T.pack (show k.id) <> "/revoke") csrf [] [button (tr loc "Revogar" "Revoke" "失効させる" "撤銷")]
          ]
      studyRow r =
        el
          "li"
          []
          ( [el "span" [cls "row-main"] [link (url loc (urlOf r.id)) [text r.submission.title], text (" " <> date r.receivedUtc <> " ")]]
              <> case r.status of
                Public -> [postForm loc ("/account/withdraw/" <> r.id) csrf [] [button (tr loc "Retirar" "Withdraw" "取り下げる" "撤回")]]
                Hidden -> [tombstone (tr loc "(escondido)" "(hidden)" "（非公開）" "（已隱藏）")]
          )
   in render
        loc
        pg
        ( [ eyebrow (tr loc "conta" "account" "アカウント" "帳戶"),
            h2 (tr loc "Sua conta" "Your account" "あなたのアカウント" "你的帳戶"),
            el
              "div"
              [cls "who"]
              [ el "p" [] [text (tr loc "Entrou como " "Logged in as " "ログイン中: " "登入身分: "), el "b" [] [text account.login]],
                postForm loc "/logout" csrf [] [button (tr loc "Sair" "Log out" "ログアウト" "登出")]
              ]
          ]
            <> case newKey of
              Just key ->
                [ h3 (tr loc "Sua nova chave" "Your new key" "新しいキー" "你的新金鑰"),
                  p_ [text (tr loc "Copie agora. Ela não aparece de novo." "Copy it now. It is not shown again." "今すぐコピーしてください。再表示されません。" "請立即複製。系統不會再次顯示。")],
                  el "p" [cls "key"] [el "code" [] [text key]]
                ]
              Nothing -> []
            <> [h3 (tr loc "Chaves da API" "API keys" "APIキー" "API 金鑰")]
            <> [ alert
                   ( tr
                       loc
                       "Você já tem 3 chaves ativas. Revogue uma antes."
                       "You already have 3 active keys. Revoke one first."
                       "有効なキーが3つあります。先に1つ失効させてください。"
                       "你已有 3 把有效金鑰。請先撤銷一把。"
                   )
               | keyError
               ]
            <> [ el "ul" [cls "rows"] (map keyRow keys),
                 postForm loc "/account/keys" csrf [] [button (tr loc "Criar uma chave" "Create a key" "キーを作成" "建立金鑰")],
                 h3 (tr loc "Seus estudos" "Your studies" "あなたの研究" "你的研究"),
                 el "ul" [cls "rows"] (map studyRow studies),
                 p_ [pill (url loc "/submit") (tr loc "Enviar um estudo" "Submit a study" "研究を投稿する" "提交研究")],
                 h3 (tr loc "Excluir a conta" "Delete the account" "アカウントの削除" "刪除帳戶"),
                 p_
                   [ text
                       ( tr
                           loc
                           "Apaga suas chaves, suas sessões e a conta. Seus estudos saem do ar na hora, mas as linhas ficam como lápide, com o hash e o motivo \"conta excluída pelo autor\"; os arquivos ficam guardados e não são servidos. Quem quiser os arquivos apagados também pede à equipe. Veja "
                           "Deletes your keys, your sessions and the account. Your studies go offline at once, but the rows stay as tombstones with the hash and the reason \"account deleted by the author\"; the files are kept and not served. To have the files deleted as well, ask the board. See "
                           "キー、セッション、アカウントを削除します。あなたの研究は直ちに公開停止になりますが、行はハッシュと「著者によるアカウント削除」という理由を刻んだ墓碑として残ります。ファイルは保存されたまま公開されません。ファイルも削除したい場合はチームに依頼してください。詳しくは "
                           "刪除你的金鑰、工作階段與帳戶。你的研究立即下架，但該列會以雜湊值與「作者刪除帳戶」的理由保留為墓碑; 檔案仍保存但不提供。若也要刪除檔案，請向團隊提出。詳見 "
                       ),
                     link (url loc "/privacy") [text (tr loc "Privacidade" "Privacy" "プライバシー" "隱私")],
                     text " · ",
                     link (url loc "/takedown") [text (tr loc "Remoção" "Takedown" "削除依頼" "下架")]
                   ],
                 postForm
                   loc
                   "/account/delete"
                   csrf
                   [cls "contact danger"]
                   ( [ el
                         "label"
                         []
                         [ el
                             "span"
                             []
                             [ text
                                 ( tr
                                     loc
                                     ("Para confirmar, digite seu login do GitHub: " <> account.login)
                                     ("To confirm, type your GitHub login: " <> account.login)
                                     ("確認のため、GitHubのユーザー名を入力してください: " <> account.login)
                                     ("請輸入你的 GitHub 帳號以確認: " <> account.login)
                                 )
                             ],
                           el "input" [attr "type" "text", attr "name" "confirm", attr "autocomplete" "off", attr "required" ""] []
                         ]
                     ]
                       <> [ alert
                              ( tr
                                  loc
                                  "O login não confere. Nada foi apagado."
                                  "The login does not match. Nothing was deleted."
                                  "ユーザー名が一致しません。何も削除されていません。"
                                  "帳號不符。未刪除任何內容。"
                              )
                          | deleteError
                          ]
                       <> [button (tr loc "Excluir minha conta" "Delete my account" "アカウントを削除" "刪除我的帳戶")]
                   )
               ]
        )

-- ---- /report/<id> --------------------------------------------------------------------------------

-- | code, pt-BR, English, Japanese, Traditional Chinese.
reasons :: [(Text, Text, Text, Text, Text)]
reasons =
  [ ("spam", "spam", "spam", "スパム", "垃圾訊息"),
    ("wrong", "dados ou conclusões erradas", "wrong data or conclusions", "誤ったデータや結論", "錯誤的資料或結論"),
    ("rights", "violação de direitos", "rights violation", "権利の侵害", "侵害權利"),
    ("harm", "pode causar dano", "may cause harm", "害を及ぼす恐れ", "可能造成傷害"),
    ("other", "outro motivo", "another reason", "その他の理由", "其他理由")
  ]

reportPage :: Locale -> Text -> Bool -> Text
reportPage loc sid isError =
  let pg = (headOf ("report/" <> sid) (tr loc "Denunciar um estudo" "Report a study" "研究を通報" "檢舉研究") "" True) {current = Nothing}
   in render
        loc
        pg
        [ eyebrow (tr loc "estudos" "studies" "研究" "研究"),
          h2 (tr loc "Denunciar um estudo" "Report a study" "研究を通報" "檢舉研究"),
          p_
            [ text
                ( tr
                    loc
                    "Não pedimos e-mail, e não guardamos seu endereço. Só o motivo e a hora."
                    "We ask for no email and keep no address. Only the reason and the time."
                    "メールは求めず、住所も保存しません。理由と時刻だけを記録します。"
                    "我們不索取電子郵件，也不保存你的位址。只記錄理由與時間。"
                )
            ],
          el
            "form"
            [attr "method" "POST", attr "action" (url loc ("/report/" <> sid)), cls "contact"]
            ( [ el
                  "input"
                  ( [attr "type" "text", attr "name" "website", attr "tabindex" "-1", attr "autocomplete" "off", attr "aria-hidden" "true"]
                      <> hidden True
                  )
                  [],
                el
                  "label"
                  []
                  [ el "span" [] [text (tr loc "Motivo" "Reason" "理由" "理由")],
                    el "select" [attr "name" "reason"] [el "option" [attr "value" v] [text (tr loc pt en ja zh)] | (v, pt, en, ja, zh) <- reasons]
                  ],
                el
                  "label"
                  []
                  [ el "span" [] [text (tr loc "Detalhes (até 1000 caracteres)" "Details (up to 1000 characters)" "詳細（最大1000文字）" "細節（最多 1000 字）")],
                    el "textarea" [attr "name" "details", attr "rows" "5", attr "maxlength" "1000"] []
                  ]
              ]
                <> [ alert
                       ( tr
                           loc
                           "Escreva um motivo ou detalhes."
                           "Write a reason or details."
                           "理由または詳細を書いてください。"
                           "請填寫理由或細節。"
                       )
                   | isError
                   ]
                <> [button (tr loc "Enviar a denúncia" "Send the report" "通報を送る" "送出檢舉")]
            )
        ]

thanksPage :: Locale -> Text
thanksPage loc =
  let pg = (headOf "report-sent" (tr loc "Obrigado" "Thank you" "ありがとうございます" "謝謝") "" True) {current = Nothing}
   in render
        loc
        pg
        [ eyebrow (tr loc "estudos" "studies" "研究" "研究"),
          h2 (tr loc "Obrigado" "Thank you" "ありがとうございます" "謝謝"),
          el
            "p"
            [cls "lede"]
            [ text
                ( tr
                    loc
                    "Recebemos a denúncia. A equipe vai olhar."
                    "We got the report. The team will look at it."
                    "通報を受け付けました。チームが確認します。"
                    "已收到檢舉。團隊將會查看。"
                )
            ],
          p_ [pill (url loc "/studies") (tr loc "Voltar aos estudos" "Back to the studies" "研究に戻る" "返回研究")]
        ]

-- | A page for a refusal or a failure: a title and one sentence, nothing from GitHub or the stack.
messagePage :: Locale -> Text -> Text -> Text
messagePage loc title sentence =
  let pg = (headOf "message" title "" True) {current = Nothing, canonical = False}
   in render loc pg [el "p" [cls "eyebrow"] [text "marola"], h2 title, el "p" [cls "lede"] [text sentence]]

-- ---- /studies.atom -------------------------------------------------------------------------------

-- | SecurityElement.Escape: the five XML characters.
xml :: Text -> Text
xml = T.concatMap $ \case
  '<' -> "&lt;"
  '>' -> "&gt;"
  '"' -> "&quot;"
  '\'' -> "&apos;"
  '&' -> "&amp;"
  c -> T.singleton c

-- | The 50 newest public studies as Atom 1.0. The summary is the first 300 characters of the abstract.
atom :: [Record] -> Text
atom studies =
  let updated = case studies of
        r : _ -> r.receivedUtc
        [] -> "1970-01-01T00:00:00Z"
      entry r =
        let s = r.submission
            i = Layout.origin <> urlOf r.id
         in "<entry><title>"
              <> xml s.title
              <> "</title><link href=\""
              <> xml i
              <> "\"/><id>"
              <> xml i
              <> "</id><updated>"
              <> r.receivedUtc
              <> "</updated><summary>"
              <> xml (U.take 300 s.abstract)
              <> "</summary>"
              <> T.concat ["<author><name>" <> xml a.name <> "</name></author>" | a <- s.authors]
              <> "</entry>"
      o = Layout.origin
   in "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<feed xmlns=\"http://www.w3.org/2005/Atom\"><title>marola: studies</title><link href=\""
        <> o
        <> "/studies.atom\" rel=\"self\"/><link href=\""
        <> o
        <> "/studies\"/><id>"
        <> o
        <> "/studies</id><updated>"
        <> updated
        <> "</updated>"
        <> T.concat (map entry studies)
        <> "</feed>\n"
