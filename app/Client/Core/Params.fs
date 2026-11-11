namespace Marola.Client

/// The page's query string (`?area=&day=&beach=&layer=&lang=&beaches=&trails=`). It is state the
/// visitor can share: each change replaces the URL in place.
type Query = (string * string) list

module Params =

    let private hex = "0123456789ABCDEF"

    let private isUnreserved (b: byte) : bool =
        (b >= 65uy && b <= 90uy)
        || (b >= 97uy && b <= 122uy)
        || (b >= 48uy && b <= 57uy)
        || b = 45uy
        || b = 46uy
        || b = 95uy
        || b = 126uy

    /// Percent-encodes the UTF-8 bytes of the text; only `A-Z a-z 0-9 - . _ ~` stay as they are.
    let encode (text: string) : string =
        let sb = System.Text.StringBuilder()

        for b in System.Text.Encoding.UTF8.GetBytes text do
            if isUnreserved b then
                sb.Append(char b) |> ignore
            else
                sb.Append('%').Append(hex.[int b / 16]).Append(hex.[int b % 16]) |> ignore

        sb.ToString()

    let private hexValue (c: char) : int option =
        if c >= '0' && c <= '9' then Some(int c - int '0')
        elif c >= 'a' && c <= 'f' then Some(int c - int 'a' + 10)
        elif c >= 'A' && c <= 'F' then Some(int c - int 'A' + 10)
        else None

    /// The text a form-encoded piece stands for: `+` is a space and `%XX` is a byte. A `%` that is
    /// not followed by two hex digits stays as it is, so a stray one never loses the link.
    let decode (text: string) : string =
        let bytes = System.Collections.Generic.List<byte>()
        let mutable i = 0

        while i < text.Length do
            let c = text.[i]

            let escaped =
                if c = '%' && i + 2 < text.Length then
                    match hexValue text.[i + 1], hexValue text.[i + 2] with
                    | Some h, Some l -> Some(byte (h * 16 + l))
                    | _ -> None
                else
                    None

            match escaped with
            | Some b ->
                bytes.Add b
                i <- i + 3
            | None ->
                if c = '+' then
                    bytes.Add 32uy
                else
                    for b in System.Text.Encoding.UTF8.GetBytes(string c) do
                        bytes.Add b

                i <- i + 1

        System.Text.Encoding.UTF8.GetString(bytes.ToArray())

    /// `location.search` with or without its leading `?`.
    let parse (search: string) : Query =
        let bare = if search.StartsWith "?" then search.Substring 1 else search

        bare.Split '&'
        |> Array.toList
        |> List.filter (fun pair -> pair <> "")
        |> List.map (fun pair ->
            match pair.IndexOf '=' with
            | -1 -> decode pair, ""
            | i -> decode (pair.Substring(0, i)), decode (pair.Substring(i + 1)))

    let get (query: Query) (key: string) : string option =
        query |> List.tryFind (fun (k, _) -> k = key) |> Option.map snd

    /// Replaces the key where it stands, or adds it at the end.
    let set (query: Query) (key: string) (value: string) : Query =
        if List.exists (fun (k, _) -> k = key) query then
            query |> List.map (fun (k, v) -> if k = key then key, value else k, v)
        else
            query @ [ key, value ]

    let delete (query: Query) (key: string) : Query =
        query |> List.filter (fun (k, _) -> k <> key)

    let toString (query: Query) : string =
        query |> List.map (fun (k, v) -> encode k + "=" + encode v) |> String.concat "&"
