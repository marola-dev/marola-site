// A stand-in for GitHub's OAuth web flow and /user, for the smoke script and for running the server by hand
// (docs/3-development.md). Dev only: the server takes its URL from MAROLA_GITHUB_BASE when MAROLA_DEV=1.
// Usage: node fake_github.mjs <client-secret> [port]. Prints the port, then serves until killed.
// Every visitor is the same user; the profile is made up.
import { createServer } from "node:http";

const [secret, portArg] = process.argv.slice(2);
if (!secret) {
  console.error("usage: node fake_github.mjs <client-secret> [port]");
  process.exit(2);
}
const token = "gho_fakeSmokeToken0123456789";
const profile = { id: 777, login: "smoke-sci", created_at: "2019-01-01T00:00:00Z" };

const server = createServer((req, res) => {
  const url = new URL(req.url, "http://fake");
  const json = (status, body) => {
    res.writeHead(status, { "content-type": "application/json" });
    res.end(JSON.stringify(body));
  };
  if (req.method === "GET" && url.pathname === "/login/oauth/authorize") {
    // The real GitHub sends the person back to the app's registered callback, with a code and the state.
    const back = new URL(url.searchParams.get("redirect_uri") ?? "");
    back.searchParams.set("code", "fakecode");
    back.searchParams.set("state", url.searchParams.get("state") ?? "");
    res.writeHead(302, { location: back.toString() });
    res.end();
  } else if (req.method === "POST" && url.pathname === "/login/oauth/access_token") {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      const f = new URLSearchParams(body);
      if (f.get("client_secret") === secret && f.get("code") === "fakecode") json(200, { access_token: token, token_type: "bearer", scope: "" });
      else json(200, { error: "bad_verification_code" });
    });
  } else if (req.method === "GET" && url.pathname === "/user") {
    if (req.headers.authorization === `Bearer ${token}`) json(200, profile);
    else json(401, { message: "Bad credentials" });
  } else {
    json(404, { message: "Not Found" });
  }
});
server.listen(portArg ? Number(portArg) : 0, "127.0.0.1", () => console.log(server.address().port));
