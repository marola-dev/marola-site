module Dec exposing (andMap, enum, int, lossy, nullable, number, optional, required)

{-| Decoder helpers shared by the board types. A field that Thoth read with `Required.Field` must
be there; `Optional.Field` takes a missing field or a null as none.
-}

import Json.Decode as D exposing (Decoder)


number : Decoder Float
number =
    D.float


int : Decoder Int
int =
    D.int


{-| A value, or none when it does not decode (null included): Thoth's `lossyOption`.
-}
lossy : Decoder a -> Decoder (Maybe a)
lossy d =
    D.oneOf [ D.map Just d, D.succeed Nothing ]


nullable : Decoder a -> Decoder (Maybe a)
nullable =
    lossy


{-| A closed set that never crashes the page: an unknown value is the caller's `Unknown` case.
-}
enum : (String -> a) -> Decoder a
enum parse =
    D.map parse D.string


andMap : Decoder a -> Decoder (a -> b) -> Decoder b
andMap =
    D.map2 (|>)


required : String -> Decoder a -> Decoder (a -> b) -> Decoder b
required name d =
    andMap (D.field name d)


{-| A missing field or a null is none; a value of the wrong shape fails.
-}
optional : String -> Decoder a -> Decoder (Maybe a)
optional name d =
    D.maybe (D.field name D.value)
        |> D.andThen
            (\found ->
                case found of
                    Nothing ->
                        D.succeed Nothing

                    Just v ->
                        case D.decodeValue (D.null ()) v of
                            Ok _ ->
                                D.succeed Nothing

                            Err _ ->
                                case D.decodeValue d v of
                                    Ok x ->
                                        D.succeed (Just x)

                                    Err e ->
                                        D.fail (D.errorToString e)
            )
