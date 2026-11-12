-- | The pages the server renders: submit, studies, a study, the account, the report form, the Atom
-- feed. Every page goes through 'Layout.page' and the Vdom, which
-- escapes text and attribute values, so no study text can add markup. No script and no inline style.
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

tr :: Locale -> Text -> Text -> Text
tr loc pt en = if loc.language == En then en else pt

-- | The address of a page in the language of the locale.
url :: Locale -> Text -> Text
url loc p = (if loc.language == En then "/en" else "") <> p

p_ :: [Node] -> Node
p_ = el "p" []

h2, h3 :: Text -> Node
h2 s = el "h2" [] [text s]
h3 s = el "h3" [] [text s]

link :: Text -> [Node] -> Node
link href = el "a" [attr "href" href]

-- | A link a visitor typed: only an https address becomes a link, with no referrer or ranking.
outside :: Text -> Text -> Node
outside href label = case httpsLink href of
  Just safe -> el "a" [attr "href" safe, attr "rel" "noopener noreferrer nofollow ugc"] [text label]
  Nothing -> text label

notice :: Locale -> Text
notice loc = tr loc "Sem revisão. Não é aconselhamento médico." "Not reviewed. Not medical advice."

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
  OtherArea -> tr loc "Outra área" "Another area"

topicLabel :: Locale -> Topic -> Text
topicLabel loc = \case
  WaterQuality -> tr loc "Qualidade da água" "Water quality"
  Waves -> tr loc "Ondas" "Waves"
  WindTopic -> tr loc "Vento" "Wind"
  TrailsTopic -> tr loc "Trilhas" "Trails"
  Ecology -> tr loc "Ecologia" "Ecology"
  Safety -> tr loc "Segurança" "Safety"
  DataTopic -> tr loc "Dados" "Data"
  OtherTopic -> tr loc "Outro" "Other"

levelLabel :: Locale -> AiContribution -> Text
levelLabel loc = \case
  NoAi -> tr loc "Nenhuma IA" "No AI"
  LanguageEditing -> tr loc "IA só revisou o texto" "AI edited the language"
  AnalysisAssistance -> tr loc "IA ajudou na análise" "AI helped with the analysis"
  Drafting -> tr loc "IA escreveu partes do texto" "AI drafted parts of the text"
  Substantial -> tr loc "IA fez a maior parte" "AI did most of the work"
  Autonomous -> tr loc "IA fez tudo sozinha" "AI did all of it"

levelText :: Locale -> AiContribution -> Text
levelText loc l
  | loc.language == En = levelMeaning l
  | otherwise = case l of
      NoAi -> "Nenhum sistema de IA participou."
      LanguageEditing -> "Um sistema de IA corrigiu ou traduziu o texto. As ideias e os resultados são dos autores."
      AnalysisAssistance -> "Um sistema de IA ajudou com código, dados ou estatística. Os autores conferiram o resultado."
      Drafting -> "Um sistema de IA escreveu partes do texto. Os autores planejaram, editaram e conferiram."
      Substantial -> "Um sistema de IA fez a maior parte da análise ou da escrita. Os autores orientaram e conferiram."
      Autonomous -> "Um sistema de IA fez o trabalho sem nenhuma etapa humana entre a pergunta e o arquivo."

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

badge :: Locale -> Node
badge loc = el "span" [cls "release-tag"] [text (tr loc "sem revisão" "not reviewed")]

-- ---- /submit -------------------------------------------------------------------------------------

loginPath :: Locale -> Text
loginPath loc = "/auth/github/login" <> (if loc.language == En then "?lang=en" else "")

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
          ( [ fieldNode "title" (tr loc "Título" "Title") "" (input "title" "text" titleMax),
              fieldNode
                "authors"
                (tr loc "Autores" "Authors")
                (tr loc "Um autor por linha. Para o ORCID: Nome | 0000-0002-1825-0097" "One author per line. For the ORCID: Name | 0000-0002-1825-0097")
                (area "authors" 4),
              fieldNode "abstract" (tr loc "Resumo" "Abstract") (tr loc "De 100 a 4000 caracteres." "From 100 to 4000 characters.") (area "abstract" 8),
              fieldNode "area" (tr loc "Área" "Area") "" (select "area" [(areaName a, areaLabel loc a) | a <- allAreas]),
              fieldNode "topic" (tr loc "Tema" "Topic") "" (select "topic" [(topicName t, topicLabel loc t) | t <- allTopics]),
              fieldNode
                "sources"
                (tr loc "Fontes" "Sources")
                (tr loc "Um link https por linha, até 10. Pode ficar vazio." "One https link per line, up to 10. May be empty.")
                (area "sources" 3),
              fieldNode
                "repository"
                (tr loc "Repositório do código" "Code repository")
                (tr loc "Um link https. Pode ficar vazio." "An https link. May be empty.")
                (input "repository" "url" linkMax),
              fieldNode
                "licence"
                (tr loc "Licença do arquivo" "Licence of the file")
                (tr loc "O marola guarda e mostra o arquivo, por isso só aceita licenças abertas." "marola stores and shows the file, so it accepts open licences only.")
                (select "licence" [(l, l) | l <- licenceValues]),
              fieldNode
                "ai_contribution"
                (tr loc "Quanto a IA fez" "How much the AI did")
                (tr loc "Você declara; o marola não confere." "You state it; marola does not check it.")
                (select "ai_contribution" [(levelName l, levelLabel loc l) | l <- allLevels]),
              fieldNode "ai_models" (tr loc "Modelos de IA usados" "AI models used") (tr loc "Opcional." "Optional.") (input "ai_models" "text" aiModelsMax),
              fieldNode
                "ai_process"
                (tr loc "Como a IA foi usada" "How the AI was used")
                (tr loc "Obrigatório se alguma IA participou." "Required if any AI took part.")
                (area "ai_process" 4),
              fieldNode
                "rights"
                (tr loc "Direitos" "Rights")
                ""
                ( el
                    "span"
                    []
                    [ el "input" ([attr "type" "checkbox", attr "name" "rights", attr "value" "true"] <> [attr "checked" "" | value "rights" == "true"]) [],
                      text
                        ( " "
                            <> tr loc "Tenho o direito de publicar este arquivo com a licença que escolhi." "I have the right to publish this file under the licence I chose."
                            <> " "
                        ),
                      link (url loc "/privacy") [text (tr loc "Privacidade" "Privacy")],
                      text " · ",
                      link (url loc "/takedown") [text (tr loc "Remoção" "Takedown")]
                    ]
                ),
              fieldNode
                "pdf"
                (tr loc "Arquivo PDF" "PDF file")
                (tr loc "Até 20 MB, sem script nem anexo." "Up to 20 MB, with no script and no attachment.")
                (el "input" [attr "type" "file", attr "name" "pdf", attr "accept" "application/pdf"] [])
            ]
              <> [ el "div" [cls "field-error"] (errorList loc errors "request" <> errorList loc errors "id"),
                   button (tr loc "Publicar" "Publish")
                 ]
          )
      li s = el "li" [] [text s]
      top =
        [ h2 (tr loc "Enviar um estudo" "Submit a study"),
          p_
            [ text
                ( tr
                    loc
                    "Qualquer pessoa com uma conta do GitHub de pelo menos 7 dias pode publicar um estudo sobre o mar, a costa e a água. O estudo fica público na hora, com o aviso \"sem revisão, não é aconselhamento médico\"."
                    "Anyone with a GitHub account that is at least 7 days old can publish a study about the sea, the coast and the water. The study is public at once, with the notice \"not reviewed, not medical advice\"."
                )
            ],
          h3 (tr loc "O que o marola publica" "What marola publishes"),
          el
            "ul"
            []
            [ li (tr loc "O PDF, o título, os autores, o resumo, as fontes e a licença, como você enviou." "The PDF, the title, the authors, the abstract, the sources and the licence, as you sent them."),
              li (tr loc "Seu usuário do GitHub, como autor do envio. Nenhum e-mail e nenhum endereço de IP é guardado." "Your GitHub login, as the sender. No email and no IP address is stored.")
            ],
          h3 (tr loc "O que o marola não faz" "What marola does not do"),
          el
            "ul"
            []
            [ li (tr loc "Não revisa nem confere o estudo. Não é aconselhamento médico." "It does not review or check the study. It is not medical advice."),
              li
                ( tr
                    loc
                    "A equipe pode esconder um estudo. Ele fica na lista com o hash, a data e o motivo, sem texto e sem arquivo."
                    "The team can hide a study. It stays in the list with its hash, its date and a reason, with no text and no file."
                )
            ],
          h3 (tr loc "Quanto a IA fez" "How much the AI did"),
          el "dl" [] (concat [[el "dt" [] [text (levelLabel loc l)], el "dd" [] [text (levelText loc l)]] | l <- allLevels])
        ]
      body = case csrf of
        Just token -> [formNode token]
        Nothing ->
          [ p_
              [ text
                  ( tr
                      loc
                      "Para enviar, entre com o GitHub. O marola lê só o seu perfil público (número, usuário e data de criação)."
                      "To submit, log in with GitHub. marola reads only your public profile (number, login and creation date)."
                  )
              ],
            p_ [link (loginPath loc) [text (tr loc "Entrar com o GitHub" "Log in with GitHub")]]
          ]
      agents =
        [ h3 (tr loc "Para agentes" "For agents"),
          p_
            [ text
                ( tr
                    loc
                    "Um agente envia pela API, com uma chave que você cria na sua conta. As regras estão em "
                    "An agent submits through the API, with a key you make in your account. The rules are in "
                ),
              link "/api/v1/skill.md" [text "/api/v1/skill.md"],
              text "."
            ]
        ]
      pg =
        (headOf "submit" (tr loc "Enviar um estudo" "Submit a study") (tr loc "Publique um estudo sobre o mar. Sem revisão." "Publish a study about the sea. Not reviewed.") False)
          { current = Nothing
          }
   in render loc pg (top <> body <> agents)

-- ---- /studies ------------------------------------------------------------------------------------

row :: Locale -> Record -> Node
row loc r =
  let s = r.submission
   in el
        "li"
        []
        [ el "h3" [] [link (url loc (urlOf r.id)) [text s.title]],
          p_ [text (T.intercalate ", " [a.name | a <- s.authors])],
          p_
            [ text (areaLabel loc s.area <> " · " <> topicLabel loc s.topic <> " · " <> date r.receivedUtc <> " "),
              badge loc,
              text (" " <> T.take 12 r.sha256)
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
          [attr "method" "GET", attr "action" (url loc "/studies"), cls "contact"]
          [ chosen "area" (areaName <$> ar) [(areaName a, areaLabel loc a) | a <- allAreas] (tr loc "Área" "Area"),
            chosen "topic" (topicName <$> tp) [(topicName t, topicLabel loc t) | t <- allTopics] (tr loc "Tema" "Topic"),
            button (tr loc "Filtrar" "Filter")
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
           in [p_ [link (url loc "/studies" <> "?" <> q) [text (tr loc "Mais antigos" "Older")]]]
        Nothing -> []
      pg =
        headOf
          "studies"
          (tr loc "Estudos" "Studies")
          (tr loc "Estudos enviados por quem pesquisa o mar. Sem revisão." "Studies sent by people who research the sea. Not reviewed.")
          False
   in render
        loc
        pg
        ( [ h2 (tr loc "Estudos" "Studies"),
            p_ [text (notice loc <> " "), link (url loc "/submit") [text (tr loc "Enviar um estudo" "Submit a study")]],
            filters
          ]
            <> ( if null studies
                   then [p_ [text (tr loc "Nenhum estudo ainda." "No studies yet.")]]
                   else [el "ul" [cls "members"] (map (row loc) studies)]
               )
            <> more
        )

-- ---- /studies/<id> -------------------------------------------------------------------------------

studyPage :: Locale -> Record -> Text
studyPage loc r = case r.status of
  Hidden ->
    let pg = headOf ("studies/" <> r.id) (tr loc "Estudo escondido" "Hidden study") (tr loc "Este estudo foi escondido." "This study was hidden.") True
        dt s = el "dt" [] [text s]
        dd ns = el "dd" [] ns
     in render
          loc
          pg
          [ h2 (tr loc "Estudo escondido" "Hidden study"),
            p_
              [ text
                  ( tr
                      loc
                      "Este estudo não está mais público. Ficam só o número, o hash, a data e o motivo."
                      "This study is no longer public. Only its id, its hash, its date and the reason remain."
                  )
              ],
            el
              "dl"
              []
              [ dt "id",
                dd [el "code" [] [text r.id]],
                dt "SHA-256",
                dd [el "code" [] [text r.sha256]],
                dt (tr loc "Recebido em" "Received on"),
                dd [text r.receivedUtc],
                dt (tr loc "Escondido em" "Hidden on"),
                dd [text (maybe "" id r.hiddenUtc)],
                dt (tr loc "Motivo" "Reason"),
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
          ( [ h2 s.title,
              p_ [badge loc, text (" " <> notice loc)],
              el "ul" [] authorsNodes,
              p_ [text (areaLabel loc s.area <> " · " <> topicLabel loc s.topic <> " · " <> date r.receivedUtc)],
              h3 (tr loc "Resumo" "Abstract"),
              p_ [text s.abstract]
            ]
              <> ( if null s.sources
                     then []
                     else [h3 (tr loc "Fontes" "Sources"), el "ul" [] [el "li" [] [outside u u] | u <- s.sources]]
                 )
              <> maybe [] (\repo -> [h3 (tr loc "Código" "Code"), p_ [outside repo repo]]) s.repository
              <> [ h3 (tr loc "Licença" "Licence"),
                   p_ [text (licenceName s.licence)],
                   h3 (tr loc "Declaração sobre IA" "AI declaration"),
                   p_ [text (levelLabel loc s.aiContribution <> ". " <> levelText loc s.aiContribution)],
                   p_ [text (tr loc "Modelos: " "Models: " <> (if T.null s.aiModels then "-" else s.aiModels))],
                   p_ [text s.aiProcess],
                   h3 (tr loc "O arquivo" "The file"),
                   p_ [link (pdfUrlOf r.id) [text (tr loc "Abrir o PDF" "Open the PDF")]],
                   p_ [text "SHA-256: ", el "code" [] [text r.sha256]],
                   p_ [text (tr loc "Enviado por " "Sent by " <> r.authorLogin <> ", " <> r.receivedUtc)],
                   p_ [link (url loc ("/report/" <> r.id)) [text (tr loc "Denunciar este estudo" "Report this study")]]
                 ]
          )

-- ---- /account ------------------------------------------------------------------------------------

accountPage :: Locale -> Account -> Text -> [KeyInfo] -> [Record] -> Maybe Text -> Bool -> Bool -> Text
accountPage loc account csrf keys studies newKey keyError deleteError =
  let pg = (headOf "account" (tr loc "Sua conta" "Your account") "" True) {current = Nothing}
      keyRow k =
        el
          "li"
          []
          [ text (tr loc "Chave " "Key " <> T.pack (show k.id) <> ", " <> date k.createdUtc <> " "),
            case k.revokedUtc of
              Just _ -> text (tr loc "(revogada)" "(revoked)")
              Nothing -> postForm loc ("/account/keys/" <> T.pack (show k.id) <> "/revoke") csrf [] [button (tr loc "Revogar" "Revoke")]
          ]
      studyRow r =
        el
          "li"
          []
          ( [link (url loc (urlOf r.id)) [text r.submission.title], text (" " <> date r.receivedUtc <> " ")]
              <> case r.status of
                Public -> [postForm loc ("/account/withdraw/" <> r.id) csrf [] [button (tr loc "Retirar" "Withdraw")]]
                Hidden -> [text (tr loc "(escondido)" "(hidden)")]
          )
   in render
        loc
        pg
        ( [ h2 (tr loc "Sua conta" "Your account"),
            p_ [text (tr loc "Entrou como " "Logged in as " <> account.login)],
            postForm loc "/logout" csrf [] [button (tr loc "Sair" "Log out")]
          ]
            <> case newKey of
              Just key ->
                [ h3 (tr loc "Sua nova chave" "Your new key"),
                  p_ [text (tr loc "Copie agora. Ela não aparece de novo." "Copy it now. It is not shown again.")],
                  p_ [el "code" [] [text key]]
                ]
              Nothing -> []
            <> [h3 (tr loc "Chaves da API" "API keys")]
            <> [alert (tr loc "Você já tem 3 chaves ativas. Revogue uma antes." "You already have 3 active keys. Revoke one first.") | keyError]
            <> [ el "ul" [] (map keyRow keys),
                 postForm loc "/account/keys" csrf [] [button (tr loc "Criar uma chave" "Create a key")],
                 h3 (tr loc "Seus estudos" "Your studies"),
                 el "ul" [] (map studyRow studies),
                 p_ [link (url loc "/submit") [text (tr loc "Enviar um estudo" "Submit a study")]],
                 h3 (tr loc "Excluir a conta" "Delete the account"),
                 p_
                   [ text
                       ( tr
                           loc
                           "Apaga suas chaves, suas sessões e a conta. Seus estudos saem do ar na hora, mas as linhas ficam como lápide, com o hash e o motivo \"conta excluída pelo autor\"; os arquivos ficam guardados e não são servidos. Quem quiser os arquivos apagados também pede à equipe. Veja "
                           "Deletes your keys, your sessions and the account. Your studies go offline at once, but the rows stay as tombstones with the hash and the reason \"account deleted by the author\"; the files are kept and not served. To have the files deleted as well, ask the board. See "
                       ),
                     link (url loc "/privacy") [text (tr loc "Privacidade" "Privacy")],
                     text " · ",
                     link (url loc "/takedown") [text (tr loc "Remoção" "Takedown")]
                   ],
                 postForm
                   loc
                   "/account/delete"
                   csrf
                   []
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
                                 )
                             ],
                           el "input" [attr "type" "text", attr "name" "confirm", attr "autocomplete" "off", attr "required" ""] []
                         ]
                     ]
                       <> [alert (tr loc "O login não confere. Nada foi apagado." "The login does not match. Nothing was deleted.") | deleteError]
                       <> [button (tr loc "Excluir minha conta" "Delete my account")]
                   )
               ]
        )

-- ---- /report/<id> --------------------------------------------------------------------------------

reasons :: [(Text, Text, Text)]
reasons =
  [ ("spam", "spam", "spam"),
    ("wrong", "dados ou conclusões erradas", "wrong data or conclusions"),
    ("rights", "violação de direitos", "rights violation"),
    ("harm", "pode causar dano", "may cause harm"),
    ("other", "outro motivo", "another reason")
  ]

reportPage :: Locale -> Text -> Bool -> Text
reportPage loc sid isError =
  let pg = (headOf ("report/" <> sid) (tr loc "Denunciar um estudo" "Report a study") "" True) {current = Nothing}
   in render
        loc
        pg
        [ h2 (tr loc "Denunciar um estudo" "Report a study"),
          p_ [text (tr loc "Não pedimos e-mail, e não guardamos seu endereço. Só o motivo e a hora." "We ask for no email and keep no address. Only the reason and the time.")],
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
                  [ el "span" [] [text (tr loc "Motivo" "Reason")],
                    el "select" [attr "name" "reason"] [el "option" [attr "value" v] [text (tr loc pt en)] | (v, pt, en) <- reasons]
                  ],
                el
                  "label"
                  []
                  [ el "span" [] [text (tr loc "Detalhes (até 1000 caracteres)" "Details (up to 1000 characters)")],
                    el "textarea" [attr "name" "details", attr "rows" "5", attr "maxlength" "1000"] []
                  ]
              ]
                <> [alert (tr loc "Escreva um motivo ou detalhes." "Write a reason or details.") | isError]
                <> [button (tr loc "Enviar a denúncia" "Send the report")]
            )
        ]

thanksPage :: Locale -> Text
thanksPage loc =
  let pg = (headOf "report-sent" (tr loc "Obrigado" "Thank you") "" True) {current = Nothing}
   in render
        loc
        pg
        [ h2 (tr loc "Obrigado" "Thank you"),
          p_ [text (tr loc "Recebemos a denúncia. A equipe vai olhar." "We got the report. The team will look at it.")],
          p_ [link (url loc "/studies") [text (tr loc "Voltar aos estudos" "Back to the studies")]]
        ]

-- | A page for a refusal or a failure: a title and one sentence, nothing from GitHub or the stack.
messagePage :: Locale -> Text -> Text -> Text
messagePage loc title sentence =
  let pg = (headOf "message" title "" True) {current = Nothing, canonical = False}
   in render loc pg [h2 title, p_ [text sentence]]

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
