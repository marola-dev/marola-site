module Tree exposing (Tree(..), attr, el, svg, svgNs, text, toHtml, toJson)

{-| A static tree for what the map draws (markers, tooltips) and the page shares with it (icons,
aspects). `maplibre_ffi.mjs` builds DOM from its JSON with createElement only, so no markup is
parsed and the CSP stays intact.
-}

import Html exposing (Html)
import Html.Attributes
import Json.Encode as E
import Svg


type Tree
    = Text String
    | El String String (List ( String, String )) (List Tree)


svgNs : String
svgNs =
    "http://www.w3.org/2000/svg"


el : String -> List ( String, String ) -> List Tree -> Tree
el =
    El ""


svg : String -> List ( String, String ) -> List Tree -> Tree
svg =
    El svgNs


text : String -> Tree
text =
    Text


attr : String -> String -> ( String, String )
attr =
    Tuple.pair


{-| `{ns, tag, attrs, children}` for an element and a bare string for text.
-}
toJson : Tree -> E.Value
toJson tree =
    case tree of
        Text t ->
            E.string t

        El ns tag attrs children ->
            E.object
                [ ( "ns", E.string ns )
                , ( "tag", E.string tag )
                , ( "attrs", E.object (List.map (\( k, v ) -> ( k, E.string v )) attrs) )
                , ( "children", E.list toJson children )
                ]


toHtml : Tree -> Html msg
toHtml tree =
    case tree of
        Text t ->
            Html.text t

        El ns tag attrs children ->
            let
                node =
                    if ns == "" then
                        Html.node

                    else
                        Svg.node
            in
            node tag (List.map (\( k, v ) -> Html.Attributes.attribute k v) attrs) (List.map toHtml children)
