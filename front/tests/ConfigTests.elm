module ConfigTests exposing (suite)

{-| The picker's two-letter codes and the sources' links: the state names the map reads from
`areas.json`, and the agency a water file names.
-}

import Config
import Expect
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "config"
        [ describe "areaCode"
            [ test "the Litoral do Paraná is PR" <|
                \_ ->
                    Expect.equal (Config.areaCode "parana" "Litoral do Paraná") "PR"
            , test "the Complexo Lagunar is CL" <|
                \_ ->
                    Expect.equal (Config.areaCode "complexo-lagunar" "Complexo Lagunar Sul Catarinense") "CL"
            , test "an area without a code takes the first two letters of its name" <|
                \_ ->
                    Expect.equal (Config.areaCode "x" "Bahia") "BA"
            ]
        , describe "sourceLink"
            [ test "IAT/PR links the Paraná bathing bulletin" <|
                \_ ->
                    Expect.equal (Config.sourceLink "IAT/PR") (Just "https://www.iat.pr.gov.br/Pagina/Balneabilidade")
            , test "IMA/SC links the Santa Catarina bulletin" <|
                \_ ->
                    Expect.equal (Config.sourceLink "IMA/SC") (Just "https://balneabilidade.ima.sc.gov.br/")
            , test "an unknown source has no link" <|
                \_ ->
                    Expect.equal (Config.sourceLink "Agency") Nothing
            ]
        ]
