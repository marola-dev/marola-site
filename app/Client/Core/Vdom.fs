namespace Marola.Client

/// What a handler reads off a DOM event: the key of a keydown and the value of the target.
type EventInfo = { Key: string; Value: string }

type Handler<'msg> = EventInfo -> 'msg option

type Attr<'msg> =
    /// An attribute: `class`, `id`, `href`, `aria-*`.
    | Attr of name: string * value: string
    /// A DOM property that an attribute does not keep current once the visitor edits it: `value`.
    | Prop of name: string * value: string
    /// A boolean property: `disabled`, `selected`.
    | Flag of name: string * on: bool
    | On of event: string * handler: Handler<'msg>

type Node<'msg> =
    | Text of string
    | El of Element<'msg>

and Element<'msg> =
    {
        Ns: string
        Tag: string
        /// Children that all have a key are matched by it, so a list that reorders keeps its DOM nodes.
        Key: string option
        Attrs: Attr<'msg> list
        Children: Node<'msg> list
    }

/// One change of the DOM, at a path of child indexes from the container. `diff` returns them in
/// the order to apply them; the patcher on the DOM (App) only runs them.
type Op<'msg> =
    | Replace of path: int list * Node<'msg>
    | SetText of path: int list * text: string
    | SetAttr of path: int list * name: string * value: string
    | RemoveAttr of path: int list * name: string
    | SetProp of path: int list * name: string * value: string
    | SetFlag of path: int list * name: string * on: bool
    /// Handlers are closures and cannot be compared, so every kept element that has some gets them
    /// again. That is a field write in the patcher, not a listener change.
    | SetHandlers of path: int list * handlers: (string * Handler<'msg>) list
    | Insert of parent: int list * index: int * Node<'msg>
    | Remove of parent: int list * index: int
    | Move of parent: int list * from: int * target: int

/// A tiny virtual DOM of our own: Feliz, Sutil and Lit each bring a runtime, an npm package or a
/// build step, and the page needs elements, text, attributes, events, keyed lists and a patch.
module Vdom =

    let svgNs = "http://www.w3.org/2000/svg"

    let element (ns: string) (tag: string) (attrs: Attr<'msg> list) (children: Node<'msg> list) : Node<'msg> =
        El
            { Ns = ns
              Tag = tag
              Key = None
              Attrs = attrs
              Children = children }

    let el (tag: string) (attrs: Attr<'msg> list) (children: Node<'msg> list) : Node<'msg> =
        element "" tag attrs children

    let svg (tag: string) (attrs: Attr<'msg> list) (children: Node<'msg> list) : Node<'msg> =
        element svgNs tag attrs children

    let text (content: string) : Node<'msg> = Text content

    /// The node with a key for the list it sits in.
    let keyed (key: string) (node: Node<'msg>) : Node<'msg> =
        match node with
        | El e -> El { e with Key = Some key }
        | Text _ -> node

    let attr (name: string) (value: string) : Attr<'msg> = Attr(name, value)
    let cls (value: string) : Attr<'msg> = Attr("class", value)
    let elId (value: string) : Attr<'msg> = Attr("id", value)

    /// The `hidden` attribute when `on`, else nothing.
    let hidden (on: bool) : Attr<'msg> list =
        if on then [ Attr("hidden", "") ] else []

    let onClick (msg: 'msg) : Attr<'msg> = On("click", fun _ -> Some msg)

    /// Enter or Space on a focused element does what a click does; any other key dispatches nothing.
    let onActivate (msg: 'msg) : Attr<'msg> =
        On(
            "keydown",
            fun e ->
                match e.Key with
                | "Enter"
                | " " -> Some msg
                | _ -> None
        )

    let onInput (f: string -> 'msg) : Attr<'msg> = On("input", fun e -> Some(f e.Value))
    let onChange (f: string -> 'msg) : Attr<'msg> = On("change", fun e -> Some(f e.Value))

    let private isEvent (a: Attr<'msg>) : bool =
        match a with
        | On _ -> true
        | _ -> false

    let private handlers (attrs: Attr<'msg> list) : (string * Handler<'msg>) list =
        attrs
        |> List.choose (fun a ->
            match a with
            | On(event, h) -> Some(event, h)
            | _ -> None)

    // The key an attribute is compared under: a name in its own kind.
    let private slot (a: Attr<'msg>) : string =
        match a with
        | Attr(n, _) -> "a:" + n
        | Prop(n, _) -> "p:" + n
        | Flag(n, _) -> "f:" + n
        | On(n, _) -> "e:" + n

    let private diffAttrs (path: int list) (olds: Attr<'msg> list) (news: Attr<'msg> list) : Op<'msg> list =
        let plain (xs: Attr<'msg> list) = xs |> List.filter (isEvent >> not)
        let olds = plain olds
        let news = plain news
        let newSlots = news |> List.map slot

        let removed =
            olds
            |> List.choose (fun o ->
                if List.contains (slot o) newSlots then
                    None
                else
                    match o with
                    | Attr(n, _) -> Some(RemoveAttr(path, n))
                    // A property that goes has no attribute to remove: reset it to its empty value.
                    | Prop(n, _) -> Some(SetProp(path, n, ""))
                    | Flag(n, _) -> Some(SetFlag(path, n, false))
                    | On _ -> None)

        let changed =
            news
            |> List.choose (fun n ->
                let before = olds |> List.tryFind (fun o -> slot o = slot n)

                match n, before with
                | Attr(name, v), Some(Attr(_, w)) when v = w -> None
                | Attr(name, v), _ -> Some(SetAttr(path, name, v))
                | Prop(name, v), Some(Prop(_, w)) when v = w -> None
                | Prop(name, v), _ -> Some(SetProp(path, name, v))
                | Flag(name, v), Some(Flag(_, w)) when v = w -> None
                | Flag(name, v), None when not v -> None
                | Flag(name, v), _ -> Some(SetFlag(path, name, v))
                | On _, _ -> None)

        removed @ changed

    let private keyOf (node: Node<'msg>) : string option =
        match node with
        | El e -> e.Key
        | Text _ -> None

    /// The keys of a list in which every child has one and none repeats; else the list matches by position.
    let private keysOf (nodes: Node<'msg> list) : string list option =
        let keys = nodes |> List.map keyOf

        if not (List.isEmpty keys) && List.forall Option.isSome keys then
            let ks = List.choose id keys

            if List.length (List.distinct ks) = List.length ks then
                Some ks
            else
                None
        else
            None

    let rec private diffNode (path: int list) (a: Node<'msg>) (b: Node<'msg>) : Op<'msg> list =
        match a, b with
        | Text x, Text y -> if x = y then [] else [ SetText(path, y) ]
        | El x, El y when x.Ns = y.Ns && x.Tag = y.Tag ->
            let hs = handlers y.Attrs

            let events =
                if List.isEmpty hs && List.isEmpty (handlers x.Attrs) then
                    []
                else
                    [ SetHandlers(path, hs) ]

            diffAttrs path x.Attrs y.Attrs
            @ events
            @ diffChildren path x.Children y.Children
        | _ -> [ Replace(path, b) ]

    and private diffChildren (parent: int list) (olds: Node<'msg> list) (news: Node<'msg> list) : Op<'msg> list =
        match keysOf olds, keysOf news with
        | Some oldKeys, Some newKeys -> diffKeyed parent olds oldKeys news newKeys
        | _ ->
            let common = min (List.length olds) (List.length news)

            let inPlace =
                List.zip (List.truncate common olds) (List.truncate common news)
                |> List.mapi (fun i (a, b) -> diffNode (parent @ [ i ]) a b)
                |> List.concat

            let added =
                news |> List.skip common |> List.mapi (fun i n -> Insert(parent, common + i, n))

            let removed =
                [ List.length olds - 1 .. -1 .. common ]
                |> List.map (fun i -> Remove(parent, i))

            inPlace @ added @ removed

    and private diffKeyed
        (parent: int list)
        (olds: Node<'msg> list)
        (oldKeys: string list)
        (news: Node<'msg> list)
        (newKeys: string list)
        : Op<'msg> list =
        // Drop what left, last index first so the indexes below stay true.
        let removes =
            oldKeys
            |> List.mapi (fun i k -> i, k)
            |> List.filter (fun (_, k) -> not (List.contains k newKeys))
            |> List.rev
            |> List.map (fun (i, _) -> Remove(parent, i))

        // Then put each new key at its place: move it up if it is further down the list, else insert it.
        let step (current: string list, ops: Op<'msg> list) (i: int, key: string, node: Node<'msg>) =
            match List.tryItem i current with
            | Some k when k = key -> current, ops
            | _ ->
                match List.tryFindIndex ((=) key) current with
                | Some j ->
                    let without = List.removeAt j current
                    List.insertAt i key without, ops @ [ Move(parent, j, i) ]
                | None -> List.insertAt i key current, ops @ [ Insert(parent, i, node) ]

        let start = oldKeys |> List.filter (fun k -> List.contains k newKeys)

        let _, reorder =
            List.zip newKeys news
            |> List.mapi (fun i (k, n) -> i, k, n)
            |> List.fold step (start, [])

        // The content of what stayed, at its final place.
        let inner =
            List.zip newKeys news
            |> List.mapi (fun i (k, n) ->
                match List.tryFindIndex ((=) k) oldKeys with
                | Some j -> diffNode (parent @ [ i ]) (List.item j olds) n
                | None -> [])
            |> List.concat

        removes @ reorder @ inner

    /// The changes that make the DOM of `before` read as `after`. Both are the children of the
    /// page's container.
    let diff (before: Node<'msg> list) (after: Node<'msg> list) : Op<'msg> list = diffChildren [] before after

    let private pathText (path: int list) : string =
        path |> List.map string |> String.concat "/"

    let rec private nodeText (node: Node<'msg>) : string =
        match node with
        | Text t -> "\"" + t + "\""
        | El e -> "<" + e.Tag + ">" + (e.Children |> List.map nodeText |> String.concat "")

    /// An op as one line, for tests and for a trace.
    let show (op: Op<'msg>) : string =
        match op with
        | Replace(p, n) -> "replace " + pathText p + " " + nodeText n
        | SetText(p, t) -> "text " + pathText p + " " + t
        | SetAttr(p, n, v) -> "attr " + pathText p + " " + n + "=" + v
        | RemoveAttr(p, n) -> "unattr " + pathText p + " " + n
        | SetProp(p, n, v) -> "prop " + pathText p + " " + n + "=" + v
        | SetFlag(p, n, v) -> "flag " + pathText p + " " + n + "=" + (if v then "true" else "false")
        | SetHandlers(p, hs) -> "on " + pathText p + " " + (hs |> List.map fst |> String.concat ",")
        | Insert(p, i, n) -> "insert " + pathText p + "@" + string i + " " + nodeText n
        | Remove(p, i) -> "remove " + pathText p + "@" + string i
        | Move(p, f, t) -> "move " + pathText p + " " + string f + ">" + string t

    /// A static tree as JSON, for a marker or a popup that `maplibre_ffi.mjs` builds: `{ns, tag,
    /// attrs, children}` for an element and a bare string for text. Handlers are left out.
    let rec toJson (node: Node<'msg>) : Json =
        match node with
        | Text t -> JStr t
        | El e ->
            JObj
                [ "ns", JStr e.Ns
                  "tag", JStr e.Tag
                  "attrs",
                  JObj(
                      e.Attrs
                      |> List.choose (fun a ->
                          match a with
                          | Attr(n, v) -> Some(n, JStr v)
                          | _ -> None)
                  )
                  "children", JArr(List.map toJson e.Children) ]

    let private voidTags =
        set
            [ "area"
              "base"
              "br"
              "col"
              "hr"
              "img"
              "input"
              "link"
              "meta"
              "source"
              "wbr" ]

    let private escapeText (s: string) : string =
        s.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;")

    let private escapeAttr (s: string) : string = (escapeText s).Replace("\"", "&quot;")

    let private attrHtml (a: Attr<'msg>) : string =
        match a with
        | Attr(n, v)
        | Prop(n, v) -> " " + n + "=\"" + escapeAttr v + "\""
        | Flag(n, true) -> " " + n
        | Flag(_, false)
        | On _ -> ""

    /// A static tree as HTML text, for a page rendered ahead of time (app/Pages). Text and attribute
    /// values are escaped and there is no raw node, so no message can add markup. A name is trusted:
    /// tags and attribute names come from code, never from data. Handlers are left out.
    let rec toHtml (node: Node<'msg>) : string =
        match node with
        | Text t -> escapeText t
        | El e ->
            let open' = "<" + e.Tag + (e.Attrs |> List.map attrHtml |> String.concat "")

            if e.Ns = "" && Set.contains e.Tag voidTags then
                open' + ">"
            else
                open'
                + ">"
                + (e.Children |> List.map toHtml |> String.concat "")
                + "</"
                + e.Tag
                + ">"
