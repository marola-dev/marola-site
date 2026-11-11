namespace Marola.Server

open System
open System.IO
open System.Security.Cryptography
open System.Text
open Microsoft.AspNetCore.Http

/// The cookies of the login and the CSRF token of a session. Nothing here is logged.
module Session =

    // `__Host-` makes a browser refuse the cookie unless it is Secure, has Path=/ and names no Domain.
    // Dev mode (plain HTTP on 127.0.0.1) cannot carry `Secure`, so it uses the bare names.
    let sessionCookie (dev: bool) = if dev then "msess" else "__Host-msess"

    let stateCookie (dev: bool) =
        if dev then "mstate" else "__Host-mstate"

    /// Equal text in time that does not depend on where the texts differ. A different length is a plain `false`.
    let safeEquals (a: string) (b: string) : bool =
        not (isNull a)
        && not (isNull b)
        && (let x = Encoding.UTF8.GetBytes a
            let y = Encoding.UTF8.GetBytes b

            x.Length = y.Length
            && CryptographicOperations.FixedTimeEquals(ReadOnlySpan x, ReadOnlySpan y))

    let private keyFile (db: string) =
        Path.Combine(Path.GetDirectoryName(Path.GetFullPath db), "csrf.key")

    /// The HMAC key of the CSRF tokens: made at the first start next to the database, mode 0600, and read
    /// afterwards. A restart keeps it, so a form opened before a deploy still posts.
    let loadKey (db: string) : byte[] =
        let path = keyFile db
        Directory.CreateDirectory(Path.GetDirectoryName path) |> ignore

        let create () =
            let options = FileStreamOptions()
            options.Mode <- FileMode.CreateNew
            options.Access <- FileAccess.Write
            options.UnixCreateMode <- UnixFileMode.UserRead ||| UnixFileMode.UserWrite
            use stream = new FileStream(path, options)
            let key = RandomNumberGenerator.GetBytes 32
            stream.Write(Encoding.ASCII.GetBytes(Convert.ToHexString key))
            key

        if File.Exists path then
            Convert.FromHexString(File.ReadAllText(path).Trim())
        else
            try
                create ()
            with :? IOException ->
                // Another start made it between the check and the create.
                Convert.FromHexString(File.ReadAllText(path).Trim())

    /// The hidden field of every POST form: an HMAC of the session's id, so it is bound to one login.
    let csrfToken (key: byte[]) (sessionHash: string) : string =
        Convert.ToHexString(HMACSHA256.HashData(key, Encoding.UTF8.GetBytes("csrf:" + sessionHash))).ToLowerInvariant()

    let csrfValid (key: byte[]) (sessionHash: string) (supplied: string) : bool =
        safeEquals (csrfToken key sessionHash) supplied

    type Live =
        {
            Account: StudyStore.Account
            /// The cookie value: needed to delete the row at logout.
            Token: string
            /// What `csrfToken` takes.
            Hash: string
        }

    /// The logged-in visitor of this request, or `None`: no cookie, a forged or expired value.
    let current (db: string) (dev: bool) (now: DateTimeOffset) (ctx: HttpContext) : Live option =
        match ctx.Request.Cookies[sessionCookie dev] with
        | null -> None
        | token ->
            StudyStore.getSession db now token
            |> Option.map (fun (account, hash) ->
                { Account = account
                  Token = token
                  Hash = hash })

    let private options (dev: bool) (maxAge: TimeSpan) =
        CookieOptions(
            HttpOnly = true,
            Secure = not dev,
            SameSite = SameSiteMode.Lax,
            Path = "/",
            MaxAge = Nullable maxAge
        )

    let set (ctx: HttpContext) (dev: bool) (name: string) (value: string) (maxAge: TimeSpan) : unit =
        ctx.Response.Cookies.Append(name, value, options dev maxAge)

    let clear (ctx: HttpContext) (dev: bool) (name: string) : unit =
        ctx.Response.Cookies.Delete(name, options dev TimeSpan.Zero)
