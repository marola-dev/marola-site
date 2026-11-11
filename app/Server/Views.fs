namespace Marola.Server

open System
open System.Security
open Marola
open Marola.Client
open Marola.Pages
open Marola.Study

/// The pages the server renders: submit, studies, a study, the account, the report form, the Atom feed. Every
/// page goes through `Layout.page` and the Vdom, which escapes text and attribute values, so no study text can
/// add markup. No script and no inline style: the CSP forbids both.
module Views =

    let private tr (loc: Locale) (pt: string) (en: string) : string =
        if loc.Language = Language.En then en else pt

    let private prefix (loc: Locale) =
        if loc.Language = Language.En then "/en" else ""

    /// The address of a page in the language of `loc`.
    let url (loc: Locale) (path: string) : string = prefix loc + path

    let private el tag attrs children : Node<unit> = Vdom.el tag attrs children
    let private txt (s: string) : Node<unit> = Vdom.text s
    let private attr = Vdom.attr
    let private p (children: Node<unit> list) = el "p" [] children
    let private h2 (s: string) = el "h2" [] [ txt s ]
    let private h3 (s: string) = el "h3" [] [ txt s ]
    let private link (href: string) (children: Node<unit> list) = el "a" [ attr "href" href ] children

    /// A link a visitor typed: only an https address becomes a link, and it carries no referrer or ranking.
    let private outside (href: string) (label: string) : Node<unit> =
        match httpsLink href with
        | Some safe -> el "a" [ attr "href" safe; attr "rel" "noopener noreferrer nofollow ugc" ] [ txt label ]
        | None -> txt label

    let notice (loc: Locale) : string =
        tr loc "Sem revisão. Não é aconselhamento médico." "Not reviewed. Not medical advice."

    let private head (loc: Locale) (slug: string) (title: string) (description: string) (noIndex: bool) : PageHead =
        { Slug = slug
          Title = title + " | marola"
          Description = description
          NoIndex = noIndex
          Canonical = true
          Current = Some "studies"
          Dynamic = true }

    let private article (loc: Locale) (children: Node<unit> list) : Node<unit> list =
        [ el "article" [ Vdom.cls "about-body"; attr "lang" (Language.tag loc.Language) ] children ]

    let private render (loc: Locale) (page: PageHead) (children: Node<unit> list) : string =
        Layout.page loc page (article loc children)

    // ---- names ----------------------------------------------------------------------------------------

    let areaLabel (loc: Locale) (a: Area) : string =
        match a with
        | Rio -> "Rio de Janeiro"
        | Floripa -> "Florianópolis"
        | Salvador -> "Salvador"
        | OtherArea -> tr loc "Outra área" "Another area"

    let topicLabel (loc: Locale) (t: Topic) : string =
        match t with
        | WaterQuality -> tr loc "Qualidade da água" "Water quality"
        | Waves -> tr loc "Ondas" "Waves"
        | WindTopic -> tr loc "Vento" "Wind"
        | TrailsTopic -> tr loc "Trilhas" "Trails"
        | Ecology -> tr loc "Ecologia" "Ecology"
        | Safety -> tr loc "Segurança" "Safety"
        | DataTopic -> tr loc "Dados" "Data"
        | OtherTopic -> tr loc "Outro" "Other"

    let levelLabel (loc: Locale) (l: AiContribution) : string =
        match l with
        | NoAi -> tr loc "Nenhuma IA" "No AI"
        | LanguageEditing -> tr loc "IA só revisou o texto" "AI edited the language"
        | AnalysisAssistance -> tr loc "IA ajudou na análise" "AI helped with the analysis"
        | Drafting -> tr loc "IA escreveu partes do texto" "AI drafted parts of the text"
        | Substantial -> tr loc "IA fez a maior parte" "AI did most of the work"
        | Autonomous -> tr loc "IA fez tudo sozinha" "AI did all of it"

    let levelText (loc: Locale) (l: AiContribution) : string =
        if loc.Language = Language.En then
            levelMeaning l
        else
            match l with
            | NoAi -> "Nenhum sistema de IA participou."
            | LanguageEditing ->
                "Um sistema de IA corrigiu ou traduziu o texto. As ideias e os resultados são dos autores."
            | AnalysisAssistance ->
                "Um sistema de IA ajudou com código, dados ou estatística. Os autores conferiram o resultado."
            | Drafting -> "Um sistema de IA escreveu partes do texto. Os autores planejaram, editaram e conferiram."
            | Substantial ->
                "Um sistema de IA fez a maior parte da análise ou da escrita. Os autores orientaram e conferiram."
            | Autonomous -> "Um sistema de IA fez o trabalho sem nenhuma etapa humana entre a pergunta e o arquivo."

    let private levels = levelValues |> List.choose parseLevel

    let private areas = areaValues |> List.choose parseArea
    let private topics = topicValues |> List.choose parseTopic

    let private date (utc: string) =
        if utc.Length >= 10 then utc.Substring(0, 10) else utc

    // ---- shared pieces --------------------------------------------------------------------------------

    let private postForm
        (loc: Locale)
        (action: string)
        (csrf: string)
        (extra: Attr<unit> list)
        (children: Node<unit> list)
        =
        el
            "form"
            ([ attr "method" "POST"; attr "action" (url loc action) ] @ extra)
            (el "input" [ attr "type" "hidden"; attr "name" "csrf"; attr "value" csrf ] []
             :: children)

    let private button (label: string) =
        el "button" [ attr "type" "submit" ] [ txt label ]

    let private errorList (loc: Locale) (errors: FieldError list) (field: string) : Node<unit> list =
        errors
        |> List.filter (fun e -> e.Field = field)
        |> List.map (fun e ->
            el "p" [ Vdom.cls "field-error"; attr "role" "alert" ] [ txt (Messages.text loc.Language e) ])

    let private badge (loc: Locale) =
        el "span" [ Vdom.cls "release-tag" ] [ txt (tr loc "sem revisão" "not reviewed") ]

    // ---- /submit --------------------------------------------------------------------------------------

    let loginPath (loc: Locale) =
        "/auth/github/login" + (if loc.Language = Language.En then "?lang=en" else "")

    let submitPage
        (loc: Locale)
        (csrf: string option)
        (values: Map<string, string>)
        (errors: FieldError list)
        : string =
        let value name =
            Map.tryFind name values |> Option.defaultValue ""

        let field (name: string) (label: string) (help: string) (control: Node<unit>) =
            el
                "label"
                []
                ([ el "span" [] [ txt label ] ]
                 @ (if help = "" then [] else [ el "small" [] [ txt help ] ])
                 @ [ control ]
                 @ errorList loc errors name)

        let input name kind (maxLength: int) =
            el
                "input"
                [ attr "type" kind
                  attr "name" name
                  attr "value" (value name)
                  attr "maxlength" (string maxLength) ]
                []

        let area name rows =
            el "textarea" [ attr "name" name; attr "rows" (string rows) ] [ txt (value name) ]

        let select name (options: (string * string) list) =
            el
                "select"
                [ attr "name" name ]
                [ for (v, label) in options ->
                      el
                          "option"
                          ([ attr "value" v ] @ (if value name = v then [ attr "selected" "" ] else []))
                          [ txt label ] ]

        let formNode (csrf: string) =
            postForm
                loc
                "/submit"
                csrf
                [ Vdom.cls "contact"; attr "enctype" "multipart/form-data" ]
                ([ field "title" (tr loc "Título" "Title") "" (input "title" "text" titleMax)
                   field
                       "authors"
                       (tr loc "Autores" "Authors")
                       (tr
                           loc
                           "Um autor por linha. Para o ORCID: Nome | 0000-0002-1825-0097"
                           "One author per line. For the ORCID: Name | 0000-0002-1825-0097")
                       (area "authors" 4)
                   field
                       "abstract"
                       (tr loc "Resumo" "Abstract")
                       (tr loc "De 100 a 4000 caracteres." "From 100 to 4000 characters.")
                       (area "abstract" 8)
                   field
                       "area"
                       (tr loc "Área" "Area")
                       ""
                       (select "area" [ for a in areas -> areaName a, areaLabel loc a ])
                   field
                       "topic"
                       (tr loc "Tema" "Topic")
                       ""
                       (select "topic" [ for t in topics -> topicName t, topicLabel loc t ])
                   field
                       "sources"
                       (tr loc "Fontes" "Sources")
                       (tr
                           loc
                           "Um link https por linha, até 10. Pode ficar vazio."
                           "One https link per line, up to 10. May be empty.")
                       (area "sources" 3)
                   field
                       "repository"
                       (tr loc "Repositório do código" "Code repository")
                       (tr loc "Um link https. Pode ficar vazio." "An https link. May be empty.")
                       (input "repository" "url" linkMax)
                   field
                       "licence"
                       (tr loc "Licença do arquivo" "Licence of the file")
                       (tr
                           loc
                           "O marola guarda e mostra o arquivo, por isso só aceita licenças abertas."
                           "marola stores and shows the file, so it accepts open licences only.")
                       (select "licence" [ for l in licenceValues -> l, l ])
                   field
                       "ai_contribution"
                       (tr loc "Quanto a IA fez" "How much the AI did")
                       (tr loc "Você declara; o marola não confere." "You state it; marola does not check it.")
                       (select "ai_contribution" [ for l in levels -> levelName l, levelLabel loc l ])
                   field
                       "ai_models"
                       (tr loc "Modelos de IA usados" "AI models used")
                       (tr loc "Opcional." "Optional.")
                       (input "ai_models" "text" aiModelsMax)
                   field
                       "ai_process"
                       (tr loc "Como a IA foi usada" "How the AI was used")
                       (tr loc "Obrigatório se alguma IA participou." "Required if any AI took part.")
                       (area "ai_process" 4)
                   field
                       "rights"
                       (tr loc "Direitos" "Rights")
                       ""
                       (el
                           "span"
                           []
                           [ el
                                 "input"
                                 ([ attr "type" "checkbox"; attr "name" "rights"; attr "value" "true" ]
                                  @ (if value "rights" = "true" then
                                         [ attr "checked" "" ]
                                     else
                                         []))
                                 []
                             txt (
                                 " "
                                 + tr
                                     loc
                                     "Tenho o direito de publicar este arquivo com a licença que escolhi."
                                     "I have the right to publish this file under the licence I chose."
                             ) ])
                   field
                       "pdf"
                       (tr loc "Arquivo PDF" "PDF file")
                       (tr loc "Até 20 MB, sem script nem anexo." "Up to 20 MB, with no script and no attachment.")
                       (el "input" [ attr "type" "file"; attr "name" "pdf"; attr "accept" "application/pdf" ] []) ]
                 @ [ el "div" [ Vdom.cls "field-error" ] (errorList loc errors "request" @ errorList loc errors "id")
                     button (tr loc "Publicar" "Publish") ])

        let top =
            [ h2 (tr loc "Enviar um estudo" "Submit a study")
              p
                  [ txt (
                        tr
                            loc
                            "Qualquer pessoa com uma conta do GitHub de pelo menos 7 dias pode publicar um estudo sobre o mar, a costa e a água. O estudo fica público na hora, com o aviso \"sem revisão, não é aconselhamento médico\"."
                            "Anyone with a GitHub account that is at least 7 days old can publish a study about the sea, the coast and the water. The study is public at once, with the notice \"not reviewed, not medical advice\"."
                    ) ]
              h3 (tr loc "O que o marola publica" "What marola publishes")
              el
                  "ul"
                  []
                  [ el
                        "li"
                        []
                        [ txt (
                              tr
                                  loc
                                  "O PDF, o título, os autores, o resumo, as fontes e a licença, como você enviou."
                                  "The PDF, the title, the authors, the abstract, the sources and the licence, as you sent them."
                          ) ]
                    el
                        "li"
                        []
                        [ txt (
                              tr
                                  loc
                                  "Seu usuário do GitHub, como autor do envio. Nenhum e-mail e nenhum endereço de IP é guardado."
                                  "Your GitHub login, as the sender. No email and no IP address is stored."
                          ) ] ]
              h3 (tr loc "O que o marola não faz" "What marola does not do")
              el
                  "ul"
                  []
                  [ el
                        "li"
                        []
                        [ txt (
                              tr
                                  loc
                                  "Não revisa nem confere o estudo. Não é aconselhamento médico."
                                  "It does not review or check the study. It is not medical advice."
                          ) ]
                    el
                        "li"
                        []
                        [ txt (
                              tr
                                  loc
                                  "A equipe pode esconder um estudo. Ele fica na lista com o hash, a data e o motivo, sem texto e sem arquivo."
                                  "The team can hide a study. It stays in the list with its hash, its date and a reason, with no text and no file."
                          ) ] ]
              h3 (tr loc "Quanto a IA fez" "How much the AI did")
              el
                  "dl"
                  []
                  [ for l in levels do
                        yield el "dt" [] [ txt (levelLabel loc l) ]
                        yield el "dd" [] [ txt (levelText loc l) ] ] ]

        let body =
            match csrf with
            | Some token -> [ formNode token ]
            | None ->
                [ p
                      [ txt (
                            tr
                                loc
                                "Para enviar, entre com o GitHub. O marola lê só o seu perfil público (número, usuário e data de criação)."
                                "To submit, log in with GitHub. marola reads only your public profile (number, login and creation date)."
                        ) ]
                  p [ link (loginPath loc) [ txt (tr loc "Entrar com o GitHub" "Log in with GitHub") ] ] ]

        let agents =
            [ h3 (tr loc "Para agentes" "For agents")
              p
                  [ txt (
                        tr
                            loc
                            "Um agente envia pela API, com uma chave que você cria na sua conta. As regras estão em "
                            "An agent submits through the API, with a key you make in your account. The rules are in "
                    )
                    link "/api/v1/skill.md" [ txt "/api/v1/skill.md" ]
                    txt "." ] ]

        let page =
            { head
                  loc
                  "submit"
                  (tr loc "Enviar um estudo" "Submit a study")
                  (tr loc "Publique um estudo sobre o mar. Sem revisão." "Publish a study about the sea. Not reviewed.")
                  false with
                Current = None }

        render loc page (top @ body @ agents)

    // ---- /studies -------------------------------------------------------------------------------------

    let private row (loc: Locale) (r: Record) : Node<unit> =
        let s = r.Submission

        el
            "li"
            []
            [ el "h3" [] [ link (url loc (urlOf r.Id)) [ txt s.Title ] ]
              p [ txt (s.Authors |> List.map _.Name |> String.concat ", ") ]
              p
                  [ txt (
                        areaLabel loc s.Area
                        + " · "
                        + topicLabel loc s.Topic
                        + " · "
                        + date r.ReceivedUtc
                        + " "
                    )
                    badge loc
                    txt (" " + r.Sha256.Substring(0, 12)) ] ]

    let studiesPage
        (loc: Locale)
        (studies: Record list)
        (area: Area option)
        (topic: Topic option)
        (next: string option)
        : string =
        let chosen (name: string) (current: string option) (options: (string * string) list) (any: string) =
            el
                "label"
                []
                [ el "span" [] [ txt any ]
                  el
                      "select"
                      [ attr "name" name ]
                      (el "option" [ attr "value" "" ] [ txt "-" ]
                       :: [ for (v, label) in options ->
                                el
                                    "option"
                                    ([ attr "value" v ] @ (if current = Some v then [ attr "selected" "" ] else []))
                                    [ txt label ] ]) ]

        let filters =
            el
                "form"
                [ attr "method" "GET"; attr "action" (url loc "/studies"); Vdom.cls "contact" ]
                [ chosen
                      "area"
                      (area |> Option.map areaName)
                      [ for a in areas -> areaName a, areaLabel loc a ]
                      (tr loc "Área" "Area")
                  chosen
                      "topic"
                      (topic |> Option.map topicName)
                      [ for t in topics -> topicName t, topicLabel loc t ]
                      (tr loc "Tema" "Topic")
                  button (tr loc "Filtrar" "Filter") ]

        let more =
            match next with
            | Some last ->
                let query =
                    [ Some("before=" + last)
                      area |> Option.map (fun a -> "area=" + areaName a)
                      topic |> Option.map (fun t -> "topic=" + topicName t) ]
                    |> List.choose id
                    |> String.concat "&"

                [ p [ link (url loc "/studies" + "?" + query) [ txt (tr loc "Mais antigos" "Older") ] ] ]
            | None -> []

        let page =
            head
                loc
                "studies"
                (tr loc "Estudos" "Studies")
                (tr
                    loc
                    "Estudos enviados por quem pesquisa o mar. Sem revisão."
                    "Studies sent by people who research the sea. Not reviewed.")
                false

        render
            loc
            { page with Current = Some "studies" }
            ([ h2 (tr loc "Estudos" "Studies")
               p
                   [ txt (notice loc + " ")
                     link (url loc "/submit") [ txt (tr loc "Enviar um estudo" "Submit a study") ] ]
               filters ]
             @ (if List.isEmpty studies then
                    [ p [ txt (tr loc "Nenhum estudo ainda." "No studies yet.") ] ]
                else
                    [ el "ul" [ Vdom.cls "members" ] (studies |> List.map (row loc)) ])
             @ more)

    // ---- /studies/<id> --------------------------------------------------------------------------------

    let studyPage (loc: Locale) (r: Record) : string =
        match r.Status with
        | Hidden ->
            let page =
                head
                    loc
                    ("studies/" + r.Id)
                    (tr loc "Estudo escondido" "Hidden study")
                    (tr loc "Este estudo foi escondido." "This study was hidden.")
                    true

            render
                loc
                page
                [ h2 (tr loc "Estudo escondido" "Hidden study")
                  p
                      [ txt (
                            tr
                                loc
                                "Este estudo não está mais público. Ficam só o número, o hash, a data e o motivo."
                                "This study is no longer public. Only its id, its hash, its date and the reason remain."
                        ) ]
                  el
                      "dl"
                      []
                      [ el "dt" [] [ txt "id" ]
                        el "dd" [] [ el "code" [] [ txt r.Id ] ]
                        el "dt" [] [ txt "SHA-256" ]
                        el "dd" [] [ el "code" [] [ txt r.Sha256 ] ]
                        el "dt" [] [ txt (tr loc "Recebido em" "Received on") ]
                        el "dd" [] [ txt r.ReceivedUtc ]
                        el "dt" [] [ txt (tr loc "Escondido em" "Hidden on") ]
                        el "dd" [] [ txt (defaultArg r.HiddenUtc "") ]
                        el "dt" [] [ txt (tr loc "Motivo" "Reason") ]
                        el "dd" [] [ txt (defaultArg r.HiddenReason "") ] ] ]
        | Public ->
            let s = r.Submission

            let page =
                head loc ("studies/" + r.Id) s.Title (s.Abstract.Substring(0, min 160 s.Abstract.Length)) false

            let authors =
                s.Authors
                |> List.map (fun a ->
                    el
                        "li"
                        []
                        ([ txt a.Name ]
                         @ (match a.Orcid with
                            | Some o -> [ txt " "; outside ("https://orcid.org/" + o) ("ORCID " + o) ]
                            | None -> [])))

            render
                loc
                page
                ([ h2 s.Title
                   p [ badge loc; txt (" " + notice loc) ]
                   el "ul" [] authors
                   p
                       [ txt (
                             areaLabel loc s.Area
                             + " · "
                             + topicLabel loc s.Topic
                             + " · "
                             + date r.ReceivedUtc
                         ) ]
                   h3 (tr loc "Resumo" "Abstract")
                   p [ txt s.Abstract ] ]
                 @ (if List.isEmpty s.Sources then
                        []
                    else
                        [ h3 (tr loc "Fontes" "Sources")
                          el "ul" [] [ for u in s.Sources -> el "li" [] [ outside u u ] ] ])
                 @ (match s.Repository with
                    | Some repo -> [ h3 (tr loc "Código" "Code"); p [ outside repo repo ] ]
                    | None -> [])
                 @ [ h3 (tr loc "Licença" "Licence")
                     p [ txt (licenceName s.Licence) ]
                     h3 (tr loc "Declaração sobre IA" "AI declaration")
                     p [ txt (levelLabel loc s.AiContribution + ". " + levelText loc s.AiContribution) ]
                     p [ txt (tr loc "Modelos: " "Models: " + (if s.AiModels = "" then "-" else s.AiModels)) ]
                     p [ txt s.AiProcess ]
                     h3 (tr loc "O arquivo" "The file")
                     p [ link (pdfUrlOf r.Id) [ txt (tr loc "Abrir o PDF" "Open the PDF") ] ]
                     p [ txt "SHA-256: "; el "code" [] [ txt r.Sha256 ] ]
                     p [ txt (tr loc "Enviado por " "Sent by " + r.AuthorLogin + ", " + r.ReceivedUtc) ]
                     p
                         [ link
                               (url loc ("/report/" + r.Id))
                               [ txt (tr loc "Denunciar este estudo" "Report this study") ] ] ])

    // ---- /account -------------------------------------------------------------------------------------

    let accountPage
        (loc: Locale)
        (account: StudyStore.Account)
        (csrf: string)
        (keys: StudyStore.KeyInfo list)
        (studies: Record list)
        (newKey: string option)
        (keyError: bool)
        : string =
        let page =
            { head loc "account" (tr loc "Sua conta" "Your account") "" true with
                Current = None }

        let keyRow (k: StudyStore.KeyInfo) =
            el
                "li"
                []
                [ txt (tr loc "Chave " "Key " + string k.Id + ", " + date k.CreatedUtc + " ")
                  (match k.RevokedUtc with
                   | Some _ -> txt (tr loc "(revogada)" "(revoked)")
                   | None ->
                       postForm
                           loc
                           ("/account/keys/" + string k.Id + "/revoke")
                           csrf
                           []
                           [ button (tr loc "Revogar" "Revoke") ]) ]

        let studyRow (r: Record) =
            el
                "li"
                []
                ([ link (url loc (urlOf r.Id)) [ txt r.Submission.Title ]
                   txt (" " + date r.ReceivedUtc + " ") ]
                 @ (match r.Status with
                    | Public ->
                        [ postForm loc ("/account/withdraw/" + r.Id) csrf [] [ button (tr loc "Retirar" "Withdraw") ] ]
                    | Hidden -> [ txt (tr loc "(escondido)" "(hidden)") ]))

        render
            loc
            page
            ([ h2 (tr loc "Sua conta" "Your account")
               p [ txt (tr loc "Entrou como " "Logged in as " + account.Login) ]
               postForm loc "/logout" csrf [] [ button (tr loc "Sair" "Log out") ] ]
             @ (match newKey with
                | Some key ->
                    [ h3 (tr loc "Sua nova chave" "Your new key")
                      p [ txt (tr loc "Copie agora. Ela não aparece de novo." "Copy it now. It is not shown again.") ]
                      p [ el "code" [] [ txt key ] ] ]
                | None -> [])
             @ [ h3 (tr loc "Chaves da API" "API keys") ]
             @ (if keyError then
                    [ el
                          "p"
                          [ Vdom.cls "field-error"; attr "role" "alert" ]
                          [ txt (
                                tr
                                    loc
                                    "Você já tem 3 chaves ativas. Revogue uma antes."
                                    "You already have 3 active keys. Revoke one first."
                            ) ] ]
                else
                    [])
             @ [ el "ul" [] (keys |> List.map keyRow)
                 postForm loc "/account/keys" csrf [] [ button (tr loc "Criar uma chave" "Create a key") ]
                 h3 (tr loc "Seus estudos" "Your studies")
                 el "ul" [] (studies |> List.map studyRow)
                 p [ link (url loc "/submit") [ txt (tr loc "Enviar um estudo" "Submit a study") ] ] ])

    // ---- /report/<id> ---------------------------------------------------------------------------------

    let reasons =
        [ "spam", "spam", "spam"
          "wrong", "dados ou conclusões erradas", "wrong data or conclusions"
          "rights", "violação de direitos", "rights violation"
          "harm", "pode causar dano", "may cause harm"
          "other", "outro motivo", "another reason" ]

    let reportPage (loc: Locale) (id: string) (error: bool) : string =
        let page =
            { head loc ("report/" + id) (tr loc "Denunciar um estudo" "Report a study") "" true with
                Current = None }

        render
            loc
            page
            [ h2 (tr loc "Denunciar um estudo" "Report a study")
              p
                  [ txt (
                        tr
                            loc
                            "Não pedimos e-mail, e não guardamos seu endereço. Só o motivo e a hora."
                            "We ask for no email and keep no address. Only the reason and the time."
                    ) ]
              el
                  "form"
                  [ attr "method" "POST"
                    attr "action" (url loc ("/report/" + id))
                    Vdom.cls "contact" ]
                  ([ el
                         "input"
                         ([ attr "type" "text"
                            attr "name" "website"
                            attr "tabindex" "-1"
                            attr "autocomplete" "off"
                            attr "aria-hidden" "true" ]
                          @ Vdom.hidden true)
                         []
                     el
                         "label"
                         []
                         [ el "span" [] [ txt (tr loc "Motivo" "Reason") ]
                           el
                               "select"
                               [ attr "name" "reason" ]
                               [ for (v, pt, en) in reasons -> el "option" [ attr "value" v ] [ txt (tr loc pt en) ] ] ]
                     el
                         "label"
                         []
                         [ el
                               "span"
                               []
                               [ txt (tr loc "Detalhes (até 1000 caracteres)" "Details (up to 1000 characters)") ]
                           el "textarea" [ attr "name" "details"; attr "rows" "5"; attr "maxlength" "1000" ] [] ] ]
                   @ (if error then
                          [ el
                                "p"
                                [ Vdom.cls "field-error"; attr "role" "alert" ]
                                [ txt (tr loc "Escreva um motivo ou detalhes." "Write a reason or details.") ] ]
                      else
                          [])
                   @ [ button (tr loc "Enviar a denúncia" "Send the report") ]) ]

    let thanksPage (loc: Locale) : string =
        let page =
            { head loc "report-sent" (tr loc "Obrigado" "Thank you") "" true with
                Current = None }

        render
            loc
            page
            [ h2 (tr loc "Obrigado" "Thank you")
              p
                  [ txt (
                        tr
                            loc
                            "Recebemos a denúncia. A equipe vai olhar."
                            "We got the report. The team will look at it."
                    ) ]
              p [ link (url loc "/studies") [ txt (tr loc "Voltar aos estudos" "Back to the studies") ] ] ]

    /// A page for a refusal or a failure: a title and one sentence, nothing from GitHub or the stack.
    let messagePage (loc: Locale) (title: string) (sentence: string) : string =
        let page =
            { head loc "message" title "" true with
                Current = None
                Canonical = false }

        render loc page [ h2 title; p [ txt sentence ] ]

    // ---- /studies.atom --------------------------------------------------------------------------------

    let private xml (s: string) : string = SecurityElement.Escape s

    /// The 50 newest public studies as Atom 1.0. Text is escaped; the summary is the first 300 characters of the abstract.
    let atom (studies: Record list) : string =
        let updated =
            match studies with
            | r :: _ -> r.ReceivedUtc
            | [] -> "1970-01-01T00:00:00Z"

        let entry (r: Record) =
            let s = r.Submission

            let summary =
                if s.Abstract.Length > 300 then
                    s.Abstract.Substring(0, 300)
                else
                    s.Abstract

            let id = Layout.origin + urlOf r.Id

            "<entry><title>"
            + xml s.Title
            + "</title><link href=\""
            + xml id
            + "\"/><id>"
            + xml id
            + "</id><updated>"
            + r.ReceivedUtc
            + "</updated><summary>"
            + xml summary
            + "</summary>"
            + (s.Authors
               |> List.map (fun a -> "<author><name>" + xml a.Name + "</name></author>")
               |> String.concat "")
            + "</entry>"

        "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<feed xmlns=\"http://www.w3.org/2005/Atom\"><title>marola: studies</title><link href=\""
        + Layout.origin
        + "/studies.atom\" rel=\"self\"/><link href=\""
        + Layout.origin
        + "/studies\"/><id>"
        + Layout.origin
        + "/studies</id><updated>"
        + updated
        + "</updated>"
        + (studies |> List.map entry |> String.concat "")
        + "</feed>\n"
