module Language exposing (Language(..), all, fromTag, matching, resolve, source, tag)

{-| The two languages of the page (MIP-0054 5.5). -}


type Language
    = PtBr
    | En


{-| A message missing elsewhere falls back to this one.
-}
source : Language
source =
    PtBr


all : List Language
all =
    [ PtBr, En ]


tag : Language -> String
tag language =
    case language of
        PtBr ->
            "pt-BR"

        En ->
            "en"


fromTag : String -> Maybe Language
fromTag value =
    List.filter (\l -> tag l == value) all |> List.head


primarySubtag : String -> String
primarySubtag t =
    String.split "-" t |> List.head |> Maybe.withDefault ""


{-| The exact tag first (ignoring case), then the first with the same primary subtag.
-}
matching : Maybe String -> List Language -> Maybe Language
matching value supported =
    case value of
        Nothing ->
            Nothing

        Just "" ->
            Nothing

        Just raw ->
            let
                lower =
                    String.toLower raw

                by wanted primary =
                    supported
                        |> List.filter
                            (\l ->
                                let
                                    candidate =
                                        String.toLower (tag l)
                                in
                                if primary then
                                    primarySubtag candidate == wanted

                                else
                                    candidate == wanted
                            )
                        |> List.head
            in
            case by lower False of
                Just l ->
                    Just l

                Nothing ->
                    by (primarySubtag lower) True


{-| ?lang=, then the stored choice, then the browser's languages, then pt-BR.
-}
resolve : Maybe String -> Maybe String -> List String -> List Language -> Language
resolve param stored languages supported =
    (param :: stored :: List.map Just languages)
        |> List.filterMap (\t -> matching t supported)
        |> List.head
        |> Maybe.withDefault source
