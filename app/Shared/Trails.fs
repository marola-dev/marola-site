namespace Marola

open Thoth.Json.Core

/// One named route: the lines are the OSM ways that make it, each a list of points, so a route
/// with gaps stays in pieces.
type Route =
    { Name: string
      LengthKm: float
      Difficulty: Difficulty
      Surface: string option
      OsmWays: int list
      Lines: Point list list }

/// The routes of one bairro. A board's trails belong to no bairro.
type Group =
    { Bairro: string option
      Routes: Route list }

type Trails =
    { Area: string
      IbgeMunicipality: string option
      Source: string
      Licence: string option
      OsmBase: string option
      Note: string option
      Groups: Group list }

/// Hiking routes of an area (OpenStreetMap, ODbL 1.0), grouped by bairro. The static file
/// `data/trails/<area>.json` carries them; a board's own optional `trails` array (MIP-0030) is the
/// fallback when an area has no file.
module Trails =

    /// The file schema this page reads.
    let schema = 1

    /// Every route, in the order the panel lists them. The position is the route's id on the map
    /// and in the panel.
    let routes (trails: Trails) : Route list =
        trails.Groups |> List.collect (fun group -> group.Routes)

    let routeAt (trails: Trails) (id: int) : Route option =
        if id < 0 then None else routes trails |> List.tryItem id

    let isEmpty (trails: Trails) : bool = List.isEmpty (routes trails)

    /// A line with fewer than two points cannot be drawn.
    let drawableLines (route: Route) : Point list list =
        route.Lines
        |> List.filter (fun line ->
            match line with
            | _ :: _ :: _ -> true
            | _ -> false)

    /// The OSM page of a way. The id is a number, so the link needs no checking.
    let wayUrl (id: int) : string =
        "https://www.openstreetmap.org/way/" + string id

    /// The board's trails as one group with no bairro. Its source is the board generator's, which
    /// reads OSM.
    let fromBoard (area: string) (trails: Trail list) : Trails =
        let routes =
            trails
            |> List.filter Trail.drawable
            |> List.map (fun t ->
                { Name = t.Name
                  LengthKm = t.LengthKm
                  Difficulty = t.Difficulty
                  Surface = t.Surface
                  OsmWays = []
                  Lines = [ t.Geometry ] })

        { Area = area
          IbgeMunicipality = None
          Source = "OpenStreetMap contributors"
          Licence = Some "ODbL-1.0"
          OsmBase = None
          Note = None
          Groups =
            match routes with
            | [] -> []
            | _ -> [ { Bairro = None; Routes = routes } ] }

    /// A `[lat, lon]` pair.
    let private pointDecoder: Decoder<Point> =
        Decode.list Decoders.number
        |> Decode.andThen (fun pair ->
            match pair with
            | [ lat; lon ] -> Decode.succeed { Lat = lat; Lon = lon }
            | _ -> Decode.fail "Expecting a [lat, lon] pair")

    let private routeDecoder: Decoder<Route> =
        Decode.object (fun get ->
            { Name = get.Required.Field "name" Decode.string
              LengthKm = get.Required.Field "length_km" Decoders.number
              Difficulty = get.Required.Field "difficulty" Difficulty.decoder
              Surface = get.Required.Field "surface" Decoders.nullableString
              OsmWays = get.Required.Field "osm_ways" (Decode.list Decoders.int)
              Lines = get.Required.Field "lines" (Decode.list (Decode.list pointDecoder)) })

    let private groupDecoder: Decoder<Group> =
        Decode.object (fun get ->
            { Bairro = Some(get.Required.Field "bairro" Decode.string)
              Routes = get.Required.Field "trails" (Decode.list routeDecoder) })

    let private body: Decoder<Trails> =
        Decode.object (fun get ->
            { Area = get.Required.Field "area" Decode.string
              IbgeMunicipality = Some(get.Required.Field "ibge_municipality" Decode.string)
              Source = get.Required.Field "source" Decode.string
              Licence = Some(get.Required.Field "licence" Decode.string)
              OsmBase = Some(get.Required.Field "osm_base" Decode.string)
              Note = get.Optional.Field "note" Decode.string
              Groups = get.Required.Field "bairros" (Decode.list groupDecoder) })

    let decoder: Decoder<Trails> =
        Decode.field "schema" Decoders.int
        |> Decode.andThen (fun found ->
            if found = schema then
                body
            else
                Decode.fail ("Expecting schema " + string schema + " but got " + string found))
