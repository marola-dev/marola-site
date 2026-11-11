namespace Marola.Pages

open System
open Marola

/// The files that are not pages: robots.txt, sitemap.xml, llms.txt, humans.txt and
/// .well-known/security.txt. Same rules and words as scripts/site_meta.py; written at build time because
/// llms.txt follows site/areas.json and security.txt's `Expires` is a date that would go stale in a repo.
module Meta =

    let private baseUrl = Layout.origin

    // The pages a crawler should index, in nav order; contact carries noindex, so it is in llms.txt (a
    // person may want it) but not in the sitemap.
    let private llmsPages =
        [ "", "The map", "every beach in an area, ranked by the best hour to swim today and tomorrow"
          "about.html", "About", "what marola is, why it is open and non-profit, how it works, the data"
          "news.html", "News", "releases, how the project is built and what is in progress"
          "members.html", "Members", "who builds marola, the same people as the Zenodo record"
          "support.html", "Support", "how to donate, where the money goes and how to check the accounts"
          "contact.html", "Contact", "a form whose message reaches the team's e-mail" ]

    let private securityPolicy =
        "https://github.com/marola-dev/.github/blob/main/SECURITY.md"

    // Under a year, as RFC 9116 section 2.5.5 recommends; the live check fails once it has passed.
    let expiresDays = 364

    let robots =
        "# marola.dev: every page and every board is public. Cloudflare prepends its managed content\n"
        + "# signals above this block; what they say is a zone setting (docs/3-development.md).\n"
        + "User-agent: *\n"
        + "Allow: /\n\n"
        + "Sitemap: "
        + baseUrl
        + "/sitemap.xml\n"

    let llms (areas: Area list) : string =
        let names = String.Join(", ", areas |> List.map _.Name)

        let lines =
            [ "# marola"
              ""
              "> marola.dev is an open, non-profit map of the Brazilian coast built as citizen science."
              + " For each area it ranks every beach by the best hour to swim today and tomorrow, from"
              + " OpenStreetMap beaches, Open-Meteo sea and weather data and the state agencies' official"
              + " bathing-water reports, with a 0–100 score and a deterministic safety veto. The boards are"
              + " precomputed and no LLM runs when you open a page. This site's code is MIT."
              ""
              "Areas: "
              + names
              + ". The pages are in Portuguese (pt-BR) at the root and in English under `/en/`; the map"
              + " takes `?lang=en`."
              ""
              "Things to know before answering from this site:"
              ""
              "- A score is an estimate. The official water report wins over it, and the safety veto is"
              + " not advice to swim."
              "- \"No data\" means the source returned nothing, not that the water is clean."
              "- The boards are rebuilt when a person runs the build; each area's `latest.json` says when"
              + " (`generated_at`) and which days it covers."
              "- Each board names its sources (`sources`); their own terms apply to the data."
              ""
              "## Pages"
              "" ]
            @ [ for path, title, what in llmsPages -> "- [" + title + "](" + baseUrl + "/" + path + "): " + what ]
            @ [ ""
                "## Data"
                ""
                "- [Areas]("
                + baseUrl
                + "/data/areas.json): every area with its centre, radius and board index" ]
            @ [ for area in areas ->
                    "- ["
                    + area.Name
                    + "]("
                    + baseUrl
                    + "/data/"
                    + area.Id
                    + "/latest.json): the days published for `"
                    + area.Id
                    + "`, each a board file next to it" ]
            @ [ "- [Board contract]("
                + baseUrl
                + "/board.schema.json): the JSON Schema every board follows"
                ""
                "## Docs"
                ""
                "- [docs.marola.dev](https://docs.marola.dev/): the project's documentation, every repo"
                "- [docs.marola.dev/llms.txt](https://docs.marola.dev/llms.txt): the same for the docs and"
                + " the code"
                "- [Code](https://github.com/marola-dev/marola-site): this site; the rest is under"
                + " https://github.com/marola-dev"
                "- [How to cite](" + Members.zenodo + "): the marola record on Zenodo"
                ""
                "## Optional"
                ""
                "- [security.txt]("
                + baseUrl
                + "/.well-known/security.txt): how to report a vulnerability"
                "- [humans.txt]("
                + baseUrl
                + "/humans.txt): the team, from the org's MEMBERS.md" ]

        String.Join("\n", lines) + "\n"

    /// Every page a crawler may index, in both languages, each with the three alternates; the map once, whose
    /// English version is the same address with `?lang=en`.
    let sitemap: string =
        let entry (loc: string) (pt: string) (en: string) =
            [ "  <url>"
              "    <loc>" + loc + "</loc>"
              "    <xhtml:link rel=\"alternate\" hreflang=\"pt-BR\" href=\"" + pt + "\"/>"
              "    <xhtml:link rel=\"alternate\" hreflang=\"en\" href=\"" + en + "\"/>"
              "    <xhtml:link rel=\"alternate\" hreflang=\"x-default\" href=\"" + pt + "\"/>"
              "  </url>" ]

        let page (slug: string) =
            let pt = baseUrl + Layout.path Language.PtBr slug
            let en = baseUrl + Layout.path Language.En slug
            entry pt pt en @ entry en pt en

        let lines =
            [ "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
              "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\" xmlns:xhtml=\"http://www.w3.org/1999/xhtml\">" ]
            @ entry (baseUrl + "/") (baseUrl + "/") (baseUrl + "/?lang=en")
            @ (Site.allSlugs |> List.filter (Site.noIndex >> not) |> List.collect page)
            @ [ "</urlset>" ]

        String.Join("\n", lines) + "\n"

    let securityTxt (today: DateOnly) : string =
        let expires = today.AddDays expiresDays

        "# How to report a vulnerability in marola: privately, on GitHub. There is no security e-mail.\n"
        + "Contact: https://github.com/marola-dev/marola-site/security/advisories/new\n"
        + "Expires: "
        + expires.ToString("yyyy-MM-dd")
        + "T00:00:00Z\n"
        + "Policy: "
        + securityPolicy
        + "\n"
        + "Preferred-Languages: pt-BR, en\n"
        + "Canonical: "
        + baseUrl
        + "/.well-known/security.txt\n"

    /// Each file with its path from the output folder.
    let files (env: Env) (today: DateOnly) : Result<(string * string) list, string> =
        Members.parse env.Members
        |> Result.map (fun members ->
            [ "robots.txt", robots
              "sitemap.xml", sitemap
              "llms.txt", llms env.Areas
              "humans.txt", Members.humans members
              ".well-known/security.txt", securityTxt today ])
