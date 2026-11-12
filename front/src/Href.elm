module Href exposing (safe)

{-| A link a page may put in an `href`: only `https:`, `http:` and `mailto:`, read the way a
browser reads it (tab and newline dropped anywhere, controls and spaces trimmed at the ends).
-}


isControl : Char -> Bool
isControl c =
    let
        code =
            Char.toCode c
    in
    code < 0x20 || (code >= 0x7F && code <= 0x9F)


trimEdges : String -> String
trimEdges text =
    let
        isEdge c =
            Char.toCode c <= 0x20

        dropFront chars =
            case chars of
                c :: rest ->
                    if isEdge c then
                        dropFront rest

                    else
                        chars

                [] ->
                    []
    in
    String.toList text |> dropFront |> List.reverse |> dropFront |> List.reverse |> String.fromList


validScheme : String -> Bool
validScheme scheme =
    case String.toList scheme of
        first :: rest ->
            Char.isAlpha first && List.all (\c -> Char.isAlphaNum c || c == '+' || c == '-' || c == '.') rest

        [] ->
            False


safe : String -> Maybe String
safe url =
    let
        cleaned =
            url |> String.replace "\t" "" |> String.replace "\n" "" |> String.replace "\u{000D}" "" |> trimEdges
    in
    case String.indexes ":" cleaned of
        i :: _ ->
            let
                scheme =
                    String.left i cleaned

                rest =
                    String.dropLeft (i + 1) cleaned
            in
            if
                rest
                    /= ""
                    && validScheme scheme
                    && List.member (String.toLower scheme) [ "https", "http", "mailto" ]
                    && not (String.any isControl cleaned)
            then
                Just cleaned

            else
                Nothing

        [] ->
            Nothing
