/// Draws a virtual tree into the real DOM and applies the operations of `Vdom.diff`. Every node is
/// made with `createElement`, `createElementNS`, `createTextNode` and `setAttribute`: no markup
/// string is parsed, so a beach name with `<` in it stays text, and the CSP stays intact.
module Marola.Client.App.Dom

open System.Collections.Generic
open Fable.Core
open Fable.Core.JsInterop
open Browser
open Marola.Client

type private DomNode = Browser.Types.Node
type private DomElement = Browser.Types.Element

// The listeners of an element live in a table on the element itself: one DOM listener per event
// name for its whole life, and the table says what it runs now. A kept element whose handlers
// change (`SetHandlers`) only rewrites the table, as `Vdom` documents.
type private Table = Dictionary<string, Browser.Types.Event -> unit>

let private tableKey = "__marolaOn"

let private tableOf (el: DomElement) : Table =
    let found: obj = el?(tableKey)

    if isNullOrUndefined found then
        let table = Table()
        el?(tableKey) <- table
        table
    else
        unbox<Table> found

let private text (value: obj) : string =
    if isNullOrUndefined value then "" else string value

let private info (e: Browser.Types.Event) : EventInfo =
    { Key = text e?key
      Value = text e.target?value }

let private setHandlers (dispatch: 'msg -> unit) (el: DomElement) (handlers: (string * Handler<'msg>) list) : unit =
    let table = tableOf el

    // An event that lost its handler keeps its DOM listener and runs nothing.
    for name in List.ofSeq table.Keys do
        table[name] <- ignore

    for name, handler in handlers do
        if not (table.ContainsKey name) then
            el.addEventListener (
                name,
                fun e ->
                    match table.TryGetValue name with
                    | true, run -> run e
                    | _ -> ()
            )

        table[name] <-
            fun e ->
                match handler (info e) with
                | Some msg ->
                    // Space on a focused control would scroll the page; Escape and Enter have no default worth keeping.
                    if name = "keydown" then
                        e.preventDefault ()

                    dispatch msg
                | None -> ()

// An `on...` attribute would be an inline handler, which the CSP blocks; events go through `On`.
let private setAttr (el: DomElement) (name: string) (value: string) : unit =
    if not (name.StartsWith("on", System.StringComparison.OrdinalIgnoreCase)) then
        el.setAttribute (name, value)

let rec private create (dispatch: 'msg -> unit) (node: Node<'msg>) : DomNode =
    match node with
    | Text content -> document.createTextNode content
    | El e ->
        let dom: DomElement =
            if e.Ns = "" then
                document.createElement e.Tag
            else
                document.createElementNS (e.Ns, e.Tag)

        for a in e.Attrs do
            match a with
            | Attr(name, value) -> setAttr dom name value
            | _ -> ()

        for child in e.Children do
            dom.appendChild (create dispatch child) |> ignore

        // After the children and the attributes: a `select` takes its value from its options, and a
        // range input reads `min` and `max` first.
        for a in e.Attrs do
            match a with
            | Prop(name, value) -> dom?(name) <- value
            | Flag(name, on) -> dom?(name) <- on
            | _ -> ()

        let handlers =
            e.Attrs
            |> List.choose (fun a ->
                match a with
                | On(event, h) -> Some(event, h)
                | _ -> None)

        if not (List.isEmpty handlers) then
            setHandlers dispatch dom handlers

        dom :> DomNode

let private childAt (parent: DomNode) (index: int) : DomNode = parent.childNodes[index]

let private nodeAt (root: DomNode) (path: int list) : DomNode = List.fold childAt root path

let private elementAt (root: DomNode) (path: int list) : DomElement = nodeAt root path :?> DomElement

let private parentOf (root: DomNode) (path: int list) : DomNode * int =
    match List.rev path with
    | last :: before -> nodeAt root (List.rev before), last
    | [] -> failwith "the root has no parent"

/// Puts `node` at `index` among the children of `parent`.
let private insertAt (parent: DomNode) (index: int) (node: DomNode) : unit =
    if index >= int parent.childNodes.length then
        parent.appendChild node |> ignore
    else
        parent.insertBefore (node, childAt parent index) |> ignore

let private applyOp (root: DomNode) (dispatch: 'msg -> unit) (op: Op<'msg>) : unit =
    match op with
    | Replace(path, node) ->
        let parent, index = parentOf root path
        parent.replaceChild (create dispatch node, childAt parent index) |> ignore
    | SetText(path, content) -> (nodeAt root path :?> Browser.Types.CharacterData).data <- content
    | SetAttr(path, name, value) -> setAttr (elementAt root path) name value
    | RemoveAttr(path, name) -> (elementAt root path).removeAttribute name
    | SetProp(path, name, value) -> (elementAt root path)?(name) <- value
    | SetFlag(path, name, on) -> (elementAt root path)?(name) <- on
    | SetHandlers(path, handlers) -> setHandlers dispatch (elementAt root path) handlers
    | Insert(parentPath, index, node) -> insertAt (nodeAt root parentPath) index (create dispatch node)
    | Remove(parentPath, index) ->
        let parent = nodeAt root parentPath
        parent.removeChild (childAt parent index) |> ignore
    | Move(parentPath, from, target) ->
        let parent = nodeAt root parentPath
        let moved = childAt parent from
        parent.removeChild moved |> ignore
        insertAt parent target moved

/// Runs the operations in order, on the children of `container`.
let apply (container: DomElement) (dispatch: 'msg -> unit) (ops: Op<'msg> list) : unit =
    for op in ops do
        applyOp container dispatch op

/// Makes the children of `container` read as `after`, given that they read as `before`.
let patch (container: DomElement) (dispatch: 'msg -> unit) (before: Node<'msg> list) (after: Node<'msg> list) : unit =
    apply container dispatch (Vdom.diff before after)
