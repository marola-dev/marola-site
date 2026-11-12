module AspectsView exposing (children)

{-| The aspect cells of a beach: the tooltip over its dot and the first rows of its card. Every
icon is followed by its word: the icon is decoration, the word is the reading.
-}

import Aspects exposing (Aspects, Cell(..))
import Icons
import Tree exposing (Tree)


reading : String -> List Tree -> Tree
reading icon body =
    Tree.el "span" [] (Icons.icon icon :: Tree.text " " :: body)


cell : Cell -> Tree
cell c =
    case c of
        Wind text Nothing ->
            reading "wind" [ Tree.text text ]

        Wind text (Just direction) ->
            reading "wind" [ Tree.text (text ++ " "), Tree.el "abbr" [ ( "class", "dir" ) ] [ Tree.text direction ] ]

        WaterTemp text ->
            reading "thermometer" [ Tree.text text ]

        Waves text ->
            reading "waves" [ Tree.text text ]

        Jellyfish text ->
            reading "jellyfish" [ Tree.text text ]

        Whales text ->
            reading "fish" [ Tree.text text ]

        Quality text unfit dotClass ->
            Tree.el "span"
                [ ( "class"
                  , if unfit then
                        "wide unfit"

                    else
                        "wide water"
                  )
                ]
                [ Tree.el "i" [ ( "class", dotClass ) ] [], Tree.text (" " ++ text) ]

        FacilityCounts parts ->
            Tree.el "span"
                [ ( "class", "wide facilities" ) ]
                (parts
                    |> List.indexedMap
                        (\i part ->
                            let
                                item =
                                    [ Icons.icon part.key, Tree.text (" " ++ part.text) ]
                            in
                            if i == 0 then
                                item

                            else
                                Tree.text " · " :: item
                        )
                    |> List.concat
                )


{-| The head line, then the grid of readings; no grid when the beach is dark.
-}
children : Aspects -> List Tree
children aspects =
    let
        head =
            Tree.el "div" [ ( "class", "head" ) ] [ Tree.text aspects.head ]
    in
    case aspects.cells of
        [] ->
            [ head ]

        cells ->
            [ head, Tree.el "div" [ ( "class", "grid" ) ] (List.map cell cells) ]
