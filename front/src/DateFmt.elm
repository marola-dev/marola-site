module DateFmt exposing (minusDays, short)

{-| A calendar day as the page prints it: `Intl.DateTimeFormat(locale, {day: 'numeric', month:
'short'})` on a UTC date, written out as tables.
-}

import Language exposing (Language(..))
import Parse


ptMonths : List String
ptMonths =
    [ "jan.", "fev.", "mar.", "abr.", "mai.", "jun.", "jul.", "ago.", "set.", "out.", "nov.", "dez." ]


enMonths : List String
enMonths =
    [ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" ]


nth : Int -> List String -> String
nth i xs =
    List.drop i xs |> List.head |> Maybe.withDefault ""


{-| "2026-11-07" is "7 de nov." in pt-BR and "Nov 7" in English; other text comes back as it is.
-}
short : String -> Language -> String
short iso language =
    case String.split "-" iso of
        [ _, month, day ] ->
            case ( Parse.tryInt month, Parse.tryInt (String.left 2 day) ) of
                ( Just m, Just d ) ->
                    if m >= 1 && m <= 12 then
                        case language of
                            PtBr ->
                                String.fromInt d ++ " de " ++ nth (m - 1) ptMonths

                            En ->
                                nth (m - 1) enMonths ++ " " ++ String.fromInt d

                    else
                        iso

                _ ->
                    iso

        _ ->
            iso


{-| Truncating division (toward zero), which the date arithmetic below was written for.
-}
quot : Int -> Int -> Int
quot a b =
    truncate (toFloat a / toFloat b)


{-| Days since 1970-01-01 (Howard Hinnant's `days_from_civil`).
-}
toDays : Int -> Int -> Int -> Int
toDays year month day =
    let
        yy =
            if month <= 2 then
                year - 1

            else
                year

        era =
            quot yy 400

        yoe =
            yy - era * 400

        shifted =
            if month > 2 then
                month - 3

            else
                month + 9

        doy =
            quot (153 * shifted + 2) 5 + day - 1

        doe =
            yoe * 365 + quot yoe 4 - quot yoe 100 + doy
    in
    era * 146097 + doe - 719468


pad : Int -> Int -> String
pad n w =
    String.padLeft w '0' (String.fromInt n)


fromDays : Int -> String
fromDays days =
    let
        z =
            days + 719468

        era =
            quot z 146097

        doe =
            z - era * 146097

        yoe =
            quot (doe - quot doe 1460 + quot doe 36524 - quot doe 146096) 365

        doy =
            doe - (365 * yoe + quot yoe 4 - quot yoe 100)

        mp =
            quot (5 * doy + 2) 153

        day =
            doy - quot (153 * mp + 2) 5 + 1

        month =
            if mp < 10 then
                mp + 3

            else
                mp - 9

        year =
            if month <= 2 then
                yoe + era * 400 + 1

            else
                yoe + era * 400
    in
    pad year 4 ++ "-" ++ pad month 2 ++ "-" ++ pad day 2


{-| The ISO day `days` before `iso`; a text that is not an ISO day comes back as it is.
-}
minusDays : String -> Int -> String
minusDays iso days =
    case String.split "-" iso of
        [ y, m, d ] ->
            case ( Parse.tryInt y, Parse.tryInt m, Parse.tryInt d ) of
                ( Just year, Just month, Just day ) ->
                    if year >= 1 && month >= 1 && month <= 12 && day >= 1 && day <= 31 then
                        fromDays (toDays year month day - days)

                    else
                        iso

                _ ->
                    iso

        _ ->
            iso
