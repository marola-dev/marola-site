namespace Marola

/// A study submitted by a scientist: the types, the validation of the form fields and the JSON the API
/// answers with. Pure, so the server and the tests on Node share it. The PDF is checked by the server.
module Study =

    type Area =
        | Rio
        | Floripa
        | Salvador
        | OtherArea

    type Topic =
        | WaterQuality
        | Waves
        | WindTopic
        | TrailsTopic
        | Ecology
        | Safety
        | DataTopic
        | OtherTopic

    /// Only open licences: marola hosts and serves the file.
    type Licence =
        | CcBy40
        | CcBySa40
        | Cc01

    /// How much of the work an AI system did. The author states it; marola does not check it.
    type AiContribution =
        | NoAi
        | LanguageEditing
        | AnalysisAssistance
        | Drafting
        | Substantial
        | Autonomous

    type Status =
        | Public
        | Hidden

    type Author = { Name: string; Orcid: string option }

    type Submission =
        { Title: string
          Authors: Author list
          Abstract: string
          Area: Area
          Topic: Topic
          Sources: string list
          Repository: string option
          Licence: Licence
          AiModels: string
          AiContribution: AiContribution
          AiProcess: string }

    type Record =
        { Id: string
          ReceivedUtc: string
          Sha256: string
          Submission: Submission
          AuthorLogin: string
          AuthorGithubId: int64
          Status: Status
          HiddenReason: string option
          HiddenUtc: string option }

    type FieldError =
        { Field: string
          Code: string
          Message: string }

    // The wire names. One table per set, so `parse` and `name` cannot drift apart.
    let private areaNames =
        [ Rio, "rio"; Floripa, "floripa"; Salvador, "salvador"; OtherArea, "other" ]

    let private topicNames =
        [ WaterQuality, "water-quality"
          Waves, "waves"
          WindTopic, "wind"
          TrailsTopic, "trails"
          Ecology, "ecology"
          Safety, "safety"
          DataTopic, "data"
          OtherTopic, "other" ]

    let private licenceNames =
        [ CcBy40, "CC-BY-4.0"; CcBySa40, "CC-BY-SA-4.0"; Cc01, "CC0-1.0" ]

    let private levelNames =
        [ NoAi, "none"
          LanguageEditing, "language-editing"
          AnalysisAssistance, "analysis-assistance"
          Drafting, "drafting"
          Substantial, "substantial"
          Autonomous, "autonomous" ]

    let private statusNames = [ Public, "public"; Hidden, "hidden" ]

    let private nameOf table value =
        table |> List.find (fun (v, _) -> v = value) |> snd

    let private parseWith table (text: string) =
        table |> List.tryFind (fun (_, n) -> n = text) |> Option.map fst

    let areaName a = nameOf areaNames a
    let topicName t = nameOf topicNames t
    let licenceName l = nameOf licenceNames l
    let levelName l = nameOf levelNames l
    let statusName s = nameOf statusNames s
    let parseArea = parseWith areaNames
    let parseTopic = parseWith topicNames
    let parseLicence = parseWith licenceNames
    let parseLevel = parseWith levelNames
    let parseStatus = parseWith statusNames

    let areaValues = areaNames |> List.map snd
    let topicValues = topicNames |> List.map snd
    let licenceValues = licenceNames |> List.map snd
    let levelValues = levelNames |> List.map snd

    /// What each level means, for the API guide and the pages.
    let levelMeaning (level: AiContribution) : string =
        match level with
        | NoAi -> "No AI system took part."
        | LanguageEditing -> "An AI system fixed or translated the text. The ideas and the results are the authors'."
        | AnalysisAssistance -> "An AI system helped with code, data or statistics. The authors checked the output."
        | Drafting -> "An AI system wrote parts of the text. The authors planned, edited and checked it."
        | Substantial -> "An AI system did most of the analysis or the writing. The authors directed and checked it."
        | Autonomous -> "An AI system did the work with no human step between the question and the file."

    let titleMin, titleMax = 5, 200
    let authorsMax = 20
    let authorNameMin, authorNameMax = 2, 120
    let abstractMin, abstractMax = 100, 4000
    let sourcesMax = 10
    let linkMax = 500
    let aiModelsMax = 300
    let aiProcessMax = 1500

    /// Control characters other than newline and tab are dropped; a lone carriage return goes with them.
    let cleanText (raw: string) : string =
        if isNull raw then
            ""
        else
            raw
            |> Seq.filter (fun c -> not (c < ' ' && c <> '\n' && c <> '\t') && not (c >= '\u007f' && c <= '\u009f'))
            |> Seq.toArray
            |> System.String
            |> fun s -> s.Trim()

    /// ISO 7064 MOD 11-2 check character of the first 15 digits of an ORCID iD.
    let orcidCheck (digits: string) : char =
        let total = digits |> Seq.fold (fun acc c -> (acc + (int c - int '0')) * 2) 0

        match (12 - total % 11) % 11 with
        | 10 -> 'X'
        | n -> char (int '0' + n)

    /// `0000-0002-1825-0097`: the shape, then the check character.
    let validOrcid (text: string) : bool =
        text.Length = 19
        && text
           |> Seq.mapi (fun i c ->
               if i = 4 || i = 9 || i = 14 then c = '-'
               elif i = 18 then (c >= '0' && c <= '9') || c = 'X'
               else c >= '0' && c <= '9')
           |> Seq.forall id
        && (let digits = text.Substring(0, 18).Replace("-", "")
            orcidCheck digits = text.[18])

    let private err field code message =
        { Field = field
          Code = code
          Message = message }

    let private hasLineBreak (s: string) = s.Contains "\n" || s.Contains "\t"

    /// A single-line text field with a length range.
    let private line field (lo: int) (hi: int) (value: string) : Result<string, FieldError> =
        if value = "" && lo > 0 then
            Error(err field "required" (field + " is required"))
        elif hasLineBreak value then
            Error(err field "invalid" (field + " must be one line of text"))
        elif value.Length < lo then
            Error(err field "too_short" (field + " needs at least " + string lo + " characters"))
        elif value.Length > hi then
            Error(err field "too_long" (field + " takes at most " + string hi + " characters"))
        else
            Ok value

    /// An https link that a page may print in an `href`.
    let httpsLink (url: string) : string option =
        match Html.safeHref url with
        | Some cleaned when
            cleaned.Length > 8
            && cleaned.Length <= linkMax
            && cleaned.ToLowerInvariant().StartsWith "https://"
            ->
            Some cleaned
        | _ -> None

    let private nonEmptyLines (value: string) =
        value.Split '\n'
        |> Array.map (fun l -> l.Trim())
        |> Array.filter (fun l -> l <> "")
        |> Array.toList

    let private parseAuthor (index: int) (text: string) : Result<Author, FieldError> =
        let name, orcid =
            match text.IndexOf '|' with
            | -1 -> text, None
            | i -> text.Substring(0, i).Trim(), Some(text.Substring(i + 1).Trim())

        let where = "authors line " + string (index + 1)

        if name.Length < authorNameMin || name.Length > authorNameMax then
            Error(
                err
                    "authors"
                    "bad_name"
                    (where
                     + ": the name needs "
                     + string authorNameMin
                     + " to "
                     + string authorNameMax
                     + " characters")
            )
        else
            match orcid with
            | None -> Ok { Name = name; Orcid = None }
            | Some o when not (validOrcid o) ->
                Error(err "authors" "bad_orcid" (where + ": the ORCID iD is not valid or its check digit is wrong"))
            | Some o -> Ok { Name = name; Orcid = Some o }

    let private collect (results: Result<'a, FieldError> list) : Result<'a list, FieldError list> =
        let errors =
            results
            |> List.choose (function
                | Error e -> Some e
                | Ok _ -> None)

        if List.isEmpty errors then
            Ok(
                results
                |> List.choose (function
                    | Ok v -> Some v
                    | Error _ -> None)
            )
        else
            Error errors

    let private enumField field (values: string list) parse (raw: string) : Result<'a, FieldError> =
        if raw = "" then
            Error(err field "required" (field + " is required"))
        else
            match parse raw with
            | Some v -> Ok v
            | None -> Error(err field "unknown_value" (field + " must be one of: " + String.concat ", " values))

    /// Checks every text field at once. `get` returns the raw text of a form field, or `None` when the
    /// field is missing. The PDF is not here: the server checks it and adds its own errors.
    let validate (get: string -> string option) : Result<Submission, FieldError list> =
        let text name =
            get name |> Option.map cleanText |> Option.defaultValue ""

        let title = line "title" titleMin titleMax (text "title")

        let authors =
            match nonEmptyLines (text "authors") with
            | [] -> Error [ err "authors" "required" "authors needs at least one author" ]
            | lines when List.length lines > authorsMax ->
                Error [ err "authors" "too_many" ("authors takes at most " + string authorsMax + " authors") ]
            | lines -> lines |> List.mapi parseAuthor |> collect

        let abstractText =
            let value = text "abstract"

            if value = "" then
                Error(err "abstract" "required" "abstract is required")
            elif value.Length < abstractMin then
                Error(err "abstract" "too_short" ("abstract needs at least " + string abstractMin + " characters"))
            elif value.Length > abstractMax then
                Error(err "abstract" "too_long" ("abstract takes at most " + string abstractMax + " characters"))
            else
                Ok value

        let area = enumField "area" areaValues parseArea (text "area")
        let topic = enumField "topic" topicValues parseTopic (text "topic")

        let sources =
            let lines = nonEmptyLines (text "sources")

            if List.length lines > sourcesMax then
                Error [ err "sources" "too_many" ("sources takes at most " + string sourcesMax + " links") ]
            else
                lines
                |> List.mapi (fun i l ->
                    match httpsLink l with
                    | Some link -> Ok link
                    | None ->
                        Error(err "sources" "bad_link" ("sources line " + string (i + 1) + " is not an https link")))
                |> collect

        let repository =
            match text "repository" with
            | "" -> Ok None
            | url ->
                match httpsLink url with
                | Some link -> Ok(Some link)
                | None -> Error(err "repository" "bad_link" "repository must be an https link")

        let licence =
            match text "licence" with
            | "" -> Ok CcBy40
            | raw -> enumField "licence" licenceValues parseLicence raw

        let rights =
            match text "rights" with
            | "true"
            | "1" -> Ok()
            | _ ->
                Error(
                    err
                        "rights"
                        "must_be_true"
                        "rights must be true: you may publish this file under the licence you chose"
                )

        let aiModels = line "ai_models" 0 aiModelsMax (text "ai_models")

        let level =
            enumField "ai_contribution" levelValues parseLevel (text "ai_contribution")

        let aiProcess =
            let value = text "ai_process"

            match level with
            | Ok l when l <> NoAi && value = "" ->
                Error(err "ai_process" "required" "ai_process is required when an AI system took part")
            | _ when value.Length > aiProcessMax ->
                Error(err "ai_process" "too_long" ("ai_process takes at most " + string aiProcessMax + " characters"))
            | _ -> Ok value

        let single r =
            match r with
            | Ok _ -> []
            | Error e -> [ e ]

        let many r =
            match r with
            | Ok _ -> []
            | Error es -> es

        let errors =
            single title
            @ many authors
            @ single abstractText
            @ single area
            @ single topic
            @ many sources
            @ single repository
            @ single licence
            @ single rights
            @ single aiModels
            @ single level
            @ single aiProcess

        match
            title, authors, abstractText, area, topic, sources, repository, licence, rights, aiModels, level, aiProcess
        with
        | Ok t, Ok au, Ok ab, Ok ar, Ok tp, Ok so, Ok re, Ok li, Ok(), Ok am, Ok lv, Ok ap when List.isEmpty errors ->
            Ok
                { Title = t
                  Authors = au
                  Abstract = ab
                  Area = ar
                  Topic = tp
                  Sources = so
                  Repository = re
                  Licence = li
                  AiModels = am
                  AiContribution = lv
                  AiProcess = ap }
        | _ -> Error errors

    // ---- JSON -------------------------------------------------------------------------------------

    /// A JSON value, written by hand: the server needs no JSON package for the little it sends.
    type Json =
        | JNull
        | JBool of bool
        | JInt of int64
        | JString of string
        | JArray of Json list
        | JObject of (string * Json) list

    let private escape (s: string) : string =
        let sb = System.Text.StringBuilder()

        for c in s do
            match c with
            | '"' -> sb.Append "\\\"" |> ignore
            | '\\' -> sb.Append "\\\\" |> ignore
            | '\n' -> sb.Append "\\n" |> ignore
            | '\t' -> sb.Append "\\t" |> ignore
            // `<`, `>` and `&` are escaped too, so the body is safe even if a client sniffs it as HTML.
            | c when c < ' ' || c = '<' || c = '>' || c = '&' || c = '\u2028' || c = '\u2029' ->
                let hex = "0123456789abcdef"
                let n = int c

                sb
                    .Append("\\u")
                    .Append(hex.[(n >>> 12) &&& 15])
                    .Append(hex.[(n >>> 8) &&& 15])
                    .Append(hex.[(n >>> 4) &&& 15])
                    .Append(hex.[n &&& 15])
                |> ignore
            | c -> sb.Append c |> ignore

        sb.ToString()

    let rec render (json: Json) : string =
        match json with
        | JNull -> "null"
        | JBool b -> if b then "true" else "false"
        | JInt n -> string n
        | JString s -> "\"" + escape s + "\""
        | JArray items -> "[" + (items |> List.map render |> String.concat ",") + "]"
        | JObject fields ->
            "{"
            + (fields
               |> List.map (fun (k, v) -> "\"" + escape k + "\":" + render v)
               |> String.concat ",")
            + "}"

    let private optString (o: string option) =
        match o with
        | Some s -> JString s
        | None -> JNull

    let urlOf (id: string) = "/studies/" + id
    let pdfUrlOf (id: string) = "/studies/" + id + ".pdf"

    /// The notice every public view carries, in the JSON too.
    let notice = "Not reviewed. Not medical advice."

    let errorsJson (errors: FieldError list) : Json =
        JObject
            [ "errors",
              JArray(
                  errors
                  |> List.map (fun e ->
                      JObject
                          [ "field", JString e.Field
                            "code", JString e.Code
                            "message", JString e.Message ])
              ) ]

    let submissionJson (s: Submission) : (string * Json) list =
        [ "title", JString s.Title
          "authors",
          JArray(
              s.Authors
              |> List.map (fun a -> JObject [ "name", JString a.Name; "orcid", optString a.Orcid ])
          )
          "abstract", JString s.Abstract
          "area", JString(areaName s.Area)
          "topic", JString(topicName s.Topic)
          "sources", JArray(s.Sources |> List.map JString)
          "repository", optString s.Repository
          "licence", JString(licenceName s.Licence)
          "ai_models", JString s.AiModels
          "ai_contribution", JString(levelName s.AiContribution)
          "ai_process", JString s.AiProcess ]

    /// The public record. A hidden study is a tombstone: id, hash, date, status and reason, never the text
    /// the author wrote and never a link to the file.
    let recordJson (r: Record) : Json =
        match r.Status with
        | Hidden ->
            JObject
                [ "id", JString r.Id
                  "sha256", JString r.Sha256
                  "received_utc", JString r.ReceivedUtc
                  "status", JString(statusName r.Status)
                  "reason", optString r.HiddenReason
                  "hidden_utc", optString r.HiddenUtc
                  "notice", JString notice ]
        | Public ->
            JObject(
                [ "id", JString r.Id
                  "sha256", JString r.Sha256
                  "received_utc", JString r.ReceivedUtc
                  "status", JString(statusName r.Status)
                  "review", JString "not reviewed"
                  "notice", JString notice ]
                @ submissionJson r.Submission
                @ [ "author_login", JString r.AuthorLogin
                    "author_github_id", JInt r.AuthorGithubId
                    "url", JString(urlOf r.Id)
                    "pdf_url", JString(pdfUrlOf r.Id) ]
            )

    /// The answer to a successful `POST /api/v1/studies`.
    let receiptJson (r: Record) : Json =
        JObject
            [ "id", JString r.Id
              "url", JString(urlOf r.Id)
              "pdf_url", JString(pdfUrlOf r.Id)
              "sha256", JString r.Sha256
              "received_utc", JString r.ReceivedUtc
              "status", JString(statusName r.Status)
              "record", recordJson r ]

    // ---- ids ----------------------------------------------------------------------------------------

    let idAlphabet = "abcdefghijklmnopqrstuvwxyz234567"

    /// A study id: 10 characters of lower-case base32. The only text that reaches a path or a query.
    let validId (id: string) : bool =
        not (isNull id)
        && id.Length = 10
        && id |> Seq.forall (fun c -> idAlphabet.IndexOf c >= 0)

    let validSha256 (hash: string) : bool =
        not (isNull hash)
        && hash.Length = 64
        && hash |> Seq.forall (fun c -> (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))
