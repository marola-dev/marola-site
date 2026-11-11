module Marola.Server.Tests.OpenApiTests

open System
open System.Text.Json
open System.Text.RegularExpressions
open Expecto
open Microsoft.AspNetCore.Routing
open Microsoft.AspNetCore.Builder
open Microsoft.AspNetCore.Http
open Marola
open Marola.Study
open Marola.Server
open Marola.Server.Tests.Harness

let private document = JsonDocument.Parse(OpenApi.text).RootElement

let private submitSchema =
    document
        .GetProperty("paths")
        .GetProperty("/api/v1/studies")
        .GetProperty("post")
        .GetProperty("requestBody")
        .GetProperty("content")
        .GetProperty("multipart/form-data")
        .GetProperty("schema")

let private field (name: string) =
    submitSchema.GetProperty("properties").GetProperty name

let private number (e: JsonElement) (name: string) = e.GetProperty(name).GetInt32()

/// Every `/api/v1` route of the running app, as (method, pattern): read from the real route table.
let private registered (site: Site) : Set<string * string> =
    (site.App :> IEndpointRouteBuilder).DataSources
    |> Seq.collect (fun source -> source.Endpoints)
    |> Seq.choose (function
        | :? RouteEndpoint as e when e.RoutePattern.RawText.StartsWith "/api/v1" -> Some e
        | _ -> None)
    |> Seq.collect (fun e ->
        e.Metadata.GetMetadata<HttpMethodMetadata>().HttpMethods
        |> Seq.map (fun m -> m.ToLowerInvariant(), e.RoutePattern.RawText))
    |> Set.ofSeq

let private documented: Set<string * string> =
    set
        [ for path in document.GetProperty("paths").EnumerateObject() do
              for operation in path.Value.EnumerateObject() -> operation.Name, path.Name ]

let private goodFields =
    Map.ofList
        [ "title", "Enterococcus in Praia do Leblon, 2025"
          "authors", "Ana Silva | 0000-0002-1825-0097\nBruno Costa"
          "abstract", String.replicate 12 "Sampling of bathing water. "
          "area", "rio"
          "topic", "water-quality"
          "sources", "https://example.org/data"
          "rights", "true"
          "ai_contribution", "none" ]

/// The validation's verdict on the good study with one field replaced.
let private fieldErrors (name: string) (value: string) : string list =
    match validate (fun k -> if k = name then Some value else Map.tryFind k goodFields) with
    | Ok _ -> []
    | Error es -> es |> List.filter (fun e -> e.Field = name) |> List.map _.Code

let private accepted name value = List.isEmpty (fieldErrors name value)

let private text (n: int) = String.replicate n "a"

let tests =
    testList
        "openapi"
        [ testTask "the document is served as JSON, cached 300 s, with the headers of every route" {
              do!
                  plainSite (fun site ->
                      task {
                          use! r = site.Client.GetAsync "/api/v1/openapi.json"
                          Expect.equal (int r.StatusCode) 200 "200"
                          Expect.equal (header r "Content-Type") (Some "application/json; charset=utf-8") "type"
                          Expect.equal (header r "Cache-Control") (Some "public, max-age=300") "cache"
                          Expect.equal (header r "X-Content-Type-Options") (Some "nosniff") "nosniff"
                          Expect.isSome (header r "Content-Security-Policy") "CSP"
                          Expect.isSome (header r "Strict-Transport-Security") "HSTS"
                          let served = r.Content.ReadAsStringAsync().Result
                          Expect.equal served OpenApi.text "the served body is the module's value"

                          Expect.equal
                              (JsonDocument.Parse(served).RootElement.GetProperty("openapi").GetString())
                              "3.1.0"
                              "version"
                      })
          }

          testTask
              "every route under /api/v1 is in the document with the same method, and every documented path is a route" {
              do!
                  plainSite (fun site ->
                      task {
                          let routes = registered site
                          Expect.isNonEmpty routes "the route table has /api/v1 routes"

                          Expect.isEmpty (Set.difference routes documented) "a route with no entry in OpenApi.document"

                          Expect.isEmpty
                              (Set.difference documented routes)
                              "an entry in OpenApi.document with no route"
                      })
          }

          test "every $ref points at a schema that exists" {
              let schemas = document.GetProperty("components").GetProperty("schemas")

              let refs =
                  [ for m in Regex.Matches(OpenApi.text, "#/components/schemas/([A-Za-z]+)") -> m.Groups[1].Value ]

              Expect.isNonEmpty refs "the document uses refs"

              for name in refs do
                  Expect.isTrue (fst (schemas.TryGetProperty name)) ("schema " + name)
          }

          test "the submit operation has the Bearer scheme and the documented status codes" {
              let scheme =
                  document.GetProperty("components").GetProperty("securitySchemes").GetProperty("bearerAuth")

              Expect.equal (scheme.GetProperty("type").GetString()) "http" "http"
              Expect.equal (scheme.GetProperty("scheme").GetString()) "bearer" "bearer"

              let post =
                  document.GetProperty("paths").GetProperty("/api/v1/studies").GetProperty "post"

              let requirement = post.GetProperty("security").EnumerateArray() |> Seq.head

              Expect.equal
                  (requirement.GetProperty("bearerAuth").GetArrayLength())
                  0
                  "the operation asks for the scheme"

              let codes = [ for r in post.GetProperty("responses").EnumerateObject() -> r.Name ]

              for code in [ "201"; "400"; "401"; "409"; "413"; "415"; "429"; "507" ] do
                  Expect.contains codes code ("response " + code)

              let dry = post.GetProperty("parameters").EnumerateArray() |> Seq.head
              Expect.equal (dry.GetProperty("name").GetString()) "dry_run" "dry run parameter"
              Expect.equal (dry.GetProperty("in").GetString()) "query" "in query"
          }

          test "the error code enum holds every code the API can send and the guide lists" {
              let enum =
                  [ for c in
                        document
                            .GetProperty("components")
                            .GetProperty("schemas")
                            .GetProperty("Error")
                            .GetProperty("properties")
                            .GetProperty("code")
                            .GetProperty("enum")
                            .EnumerateArray() -> c.GetString() ]

              let guide = StudyApi.skill.Substring(StudyApi.skill.IndexOf "## Errors")

              let listed =
                  [ for m in Regex.Matches(guide, "`([a-z_]+)`") do
                        if m.Groups[1].Value <> "id" then
                            m.Groups[1].Value ]

              for code in listed do
                  Expect.contains enum code ("skill.md code " + code + " in the enum")

              for code in Messages.codes do
                  if code <> "csrf" then
                      Expect.contains enum code ("code " + code + " in the enum")

              Expect.contains enum "not_found" "the 404 of the GET routes"
              Expect.isFalse (List.contains "csrf" enum) "csrf is the web form's, not the API's"
          }

          test "the document limits are the validation limits: title" {
              let f = field "title"
              Expect.equal (number f "minLength") titleMin "min"
              Expect.equal (number f "maxLength") titleMax "max"
              Expect.isFalse (accepted "title" (text (number f "minLength" - 1))) "below min"
              Expect.isTrue (accepted "title" (text (number f "minLength"))) "at min"
              Expect.isTrue (accepted "title" (text (number f "maxLength"))) "at max"
              Expect.isFalse (accepted "title" (text (number f "maxLength" + 1))) "above max"
          }

          test "the document limits are the validation limits: abstract" {
              let f = field "abstract"
              Expect.equal (number f "minLength") abstractMin "min"
              Expect.equal (number f "maxLength") abstractMax "max"
              Expect.isFalse (accepted "abstract" (text (number f "minLength" - 1))) "below min"
              Expect.isTrue (accepted "abstract" (text (number f "minLength"))) "at min"
              Expect.isTrue (accepted "abstract" (text (number f "maxLength"))) "at max"
              Expect.isFalse (accepted "abstract" (text (number f "maxLength" + 1))) "above max"
          }

          test "the document limits are the validation limits: ai_models and ai_process" {
              let models = field "ai_models"
              Expect.equal (number models "maxLength") aiModelsMax "ai_models"
              Expect.isTrue (accepted "ai_models" (text (number models "maxLength"))) "ai_models at max"
              Expect.isFalse (accepted "ai_models" (text (number models "maxLength" + 1))) "ai_models above max"

              let process' = field "ai_process"
              Expect.equal (number process' "maxLength") aiProcessMax "ai_process"
              Expect.isTrue (accepted "ai_process" (text (number process' "maxLength"))) "ai_process at max"
              Expect.isFalse (accepted "ai_process" (text (number process' "maxLength" + 1))) "ai_process above max"
          }

          test "the document limits are the validation limits: authors" {
              let f = field "authors"

              let lines n =
                  String.concat "\n" [ for i in 1..n -> "Author " + string i ]

              Expect.equal (number f "x-max-lines") authorsMax "lines"
              Expect.equal (number f "x-name-min-length") authorNameMin "name min"
              Expect.equal (number f "x-name-max-length") authorNameMax "name max"
              Expect.isTrue (accepted "authors" (lines (number f "x-max-lines"))) "at max lines"
              Expect.isFalse (accepted "authors" (lines (number f "x-max-lines" + 1))) "above max lines"
              Expect.isFalse (accepted "authors" (text (number f "x-name-min-length" - 1))) "name below min"
              Expect.isTrue (accepted "authors" (text (number f "x-name-min-length"))) "name at min"
              Expect.isTrue (accepted "authors" (text (number f "x-name-max-length"))) "name at max"
              Expect.isFalse (accepted "authors" (text (number f "x-name-max-length" + 1))) "name above max"
          }

          test "the document limits are the validation limits: sources and links" {
              let f = field "sources"

              let link n =
                  "https://example.org/" + text (n - "https://example.org/".Length)

              let lines n =
                  String.concat "\n" [ for i in 1..n -> "https://example.org/" + string i ]

              Expect.equal (number f "x-max-lines") sourcesMax "lines"
              Expect.equal (number f "x-max-line-length") linkMax "line length"
              Expect.isTrue (accepted "sources" (lines (number f "x-max-lines"))) "at max lines"
              Expect.isFalse (accepted "sources" (lines (number f "x-max-lines" + 1))) "above max lines"
              Expect.isTrue (accepted "sources" (link (number f "x-max-line-length"))) "link at max"
              Expect.isFalse (accepted "sources" (link (number f "x-max-line-length" + 1))) "link above max"

              let repository = field "repository"
              Expect.equal (number repository "maxLength") linkMax "repository"
              Expect.isTrue (accepted "repository" (link (number repository "maxLength"))) "repository at max"
              Expect.isFalse (accepted "repository" (link (number repository "maxLength" + 1))) "repository above max"
          }

          test "the document limits are the validation limits: enums, licence default and the file" {
              let values name =
                  [ for v in (field name).GetProperty("enum").EnumerateArray() -> v.GetString() ]

              Expect.equal (values "area") areaValues "area"
              Expect.equal (values "topic") topicValues "topic"
              Expect.equal (values "licence") licenceValues "licence"
              Expect.equal (values "ai_contribution") levelValues "ai_contribution"
              Expect.equal ((field "licence").GetProperty("default").GetString()) (licenceName CcBy40) "default licence"

              for name, list in [ "area", areaValues; "topic", topicValues; "licence", licenceValues ] do
                  for v in list do
                      Expect.isTrue (accepted name v) (name + " " + v)

                  Expect.isFalse (accepted name "nope") (name + " rejects an unknown value")

              Expect.equal ((field "pdf").GetProperty("x-max-bytes").GetInt64()) PdfIntake.maxBytes "pdf bytes"
              Expect.equal (submitSchema.GetProperty("x-max-parts").GetInt32()) StudyApi.maxParts "parts"

              Expect.equal
                  (submitSchema.GetProperty("x-max-field-bytes").GetInt32())
                  StudyApi.maxFieldBytes
                  "field bytes"

              Expect.equal
                  (submitSchema.GetProperty("x-max-request-bytes").GetInt64())
                  StudyApi.uploadLimit
                  "request bytes"
          }

          testTask "the document limits are the list limits: limit 1 to the maximum, default as documented" {
              let parameter =
                  document
                      .GetProperty("paths")
                      .GetProperty("/api/v1/studies")
                      .GetProperty("get")
                      .GetProperty("parameters")
                      .EnumerateArray()
                  |> Seq.find (fun p -> p.GetProperty("name").GetString() = "limit")

              let limit = parameter.GetProperty "schema"

              Expect.equal (number limit "minimum") 1 "min"
              Expect.equal (number limit "maximum") StudyApi.listMax "max"
              Expect.equal (number limit "default") StudyApi.listDefault "default"

              do!
                  plainSite (fun site ->
                      task {
                          for value, expected in
                              [ number limit "minimum", 200
                                number limit "maximum", 200
                                number limit "minimum" - 1, 400
                                number limit "maximum" + 1, 400 ] do
                              use! r = site.Client.GetAsync("/api/v1/studies?limit=" + string value)
                              Expect.equal (int r.StatusCode) expected ("limit=" + string value)
                      })
          } ]
