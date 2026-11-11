namespace Marola.Client

open Marola

/// A JSON value and its writer. The map and the flow layer read JSON text through the two FFI
/// files, and Thoth's encoders need a per-runtime package to print. This is 50 lines, pure, and
/// prints the same text on .NET and on Fable.
type Json =
    | JNull
    | JBool of bool
    | JInt of int
    | JNum of float
    | JStr of string
    | JArr of Json list
    | JObj of (string * Json) list

module Json =

    let private hex = "0123456789abcdef"

    let private escape (text: string) : string =
        let sb = System.Text.StringBuilder()

        for c in text do
            match c with
            | '"' -> sb.Append "\\\"" |> ignore
            | '\\' -> sb.Append "\\\\" |> ignore
            | '\n' -> sb.Append "\\n" |> ignore
            | '\r' -> sb.Append "\\r" |> ignore
            | '\t' -> sb.Append "\\t" |> ignore
            | c when c < ' ' -> sb.Append("\\u00").Append(hex.[int c / 16]).Append(hex.[int c % 16]) |> ignore
            | c -> sb.Append c |> ignore

        sb.ToString()

    /// The shortest text that reads back, and `null` for NaN or infinity, which JSON cannot hold.
    let private number (n: float) : string =
        if System.Double.IsNaN n || System.Double.IsInfinity n then
            "null"
        else
            Parse.shortest n

    let rec render (json: Json) : string =
        match json with
        | JNull -> "null"
        | JBool true -> "true"
        | JBool false -> "false"
        | JInt n -> string n
        | JNum n -> number n
        | JStr s -> "\"" + escape s + "\""
        | JArr items -> "[" + (items |> List.map render |> String.concat ",") + "]"
        | JObj fields ->
            "{"
            + (fields
               |> List.map (fun (k, v) -> "\"" + escape k + "\":" + render v)
               |> String.concat ",")
            + "}"

    /// A value, or `null` for none.
    let nullable (f: 'a -> Json) (value: 'a option) : Json =
        match value with
        | Some v -> f v
        | None -> JNull
