module Note exposing (Note, NoteArg(..), decoder)

{-| The reason codes of a score (MIP-0054 section 5.1). The code stays the wire text: the page
words a code through `note.<code>`, and one it has no key for keeps the board's English.
-}

import Dec
import Dict exposing (Dict)
import Json.Decode as D exposing (Decoder)


{-| Numbers stay numbers, `avoid` is a list of places; any other shape is `Other`, never an error.
-}
type NoteArg
    = Number Float
    | Text String
    | Places (List String)
    | Other


type alias Note =
    { code : String, args : Dict String NoteArg }


argDecoder : Decoder NoteArg
argDecoder =
    D.oneOf
        [ D.map Number Dec.number
        , D.map Text D.string
        , D.map Places (D.list D.string)
        , D.succeed Other
        ]


decoder : Decoder Note
decoder =
    D.map2 Note (D.field "code" D.string) (D.field "args" (D.dict argDecoder))
