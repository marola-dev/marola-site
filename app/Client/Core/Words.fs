namespace Marola.Client

open Marola

/// Words for the view: a catalog message, plain or with a piece of markup in the middle. The markup
/// is never part of a message: the piece is a node put where a marker stood, so a message cannot
/// inject any. A missing key renders the key (`I18n.t`).
module Words =

    let t (model: Model) (key: string) : string = I18n.t model.Loc key []

    let ta (model: Model) (key: string) (args: (string * IcuArg) list) : string = I18n.t model.Loc key args

    /// A private-use character no catalog message contains.
    let private marker = "\uE000"

    /// The message with `slot` where the argument `name` is. A message that does not use the
    /// argument (a branch of a `select`) comes back as text alone.
    let withSlot
        (model: Model)
        (key: string)
        (args: (string * IcuArg) list)
        (name: string)
        (slot: Node<'msg> list)
        : Node<'msg> list =
        let text = I18n.t model.Loc key (I18n.arg name marker :: args)

        text.Split marker
        |> Array.toList
        |> List.mapi (fun i part ->
            if i = 0 then
                [ Vdom.text part ]
            else
                slot @ [ Vdom.text part ])
        |> List.concat

    let pressed (on: bool) : Attr<'msg> =
        Vdom.attr "aria-pressed" (if on then "true" else "false")

    let expanded (on: bool) : Attr<'msg> =
        Vdom.attr "aria-expanded" (if on then "true" else "false")

    /// A line icon.
    let icon (name: string) : Node<'msg> = Icons.icon name
