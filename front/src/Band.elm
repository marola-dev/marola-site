module Band exposing (Band(..), cssClass, ofScore)

{-| The colour band of a score. The page colours by class, never by an inline style: its CSP
blocks `style=`.
-}


type Band
    = Unscored
    | Avoid
    | Poor
    | Fair
    | Good


{-| No score is `Unscored`; an unfit beach or a score of 0 or less is `Avoid`.
-}
ofScore : Maybe Int -> Bool -> Band
ofScore score unfit =
    case score of
        Nothing ->
            Unscored

        Just s ->
            if unfit || s <= 0 then
                Avoid

            else if s >= 70 then
                Good

            else if s >= 40 then
                Fair

            else
                Poor


cssClass : Band -> String
cssClass band =
    case band of
        Unscored ->
            "cna"

        Avoid ->
            "c0"

        Poor ->
            "c1"

        Fair ->
            "c40"

        Good ->
            "c70"
