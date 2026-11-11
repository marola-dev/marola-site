// Dependency-free static server for app/dist: the Content-Security-Policy comes from
// csp.txt (written by app_build.sh from Csp.fs) so local runs get the real header.
// Usage: node scripts/serve.mjs [dir] [port]
import { createServer } from "node:http";
import { existsSync, readFileSync, statSync, createReadStream } from "node:fs";
import { dirname, extname, join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const dir = resolve(process.argv[2] || join(root, "app/dist"));
const port = Number(process.argv[3] || 8000);
const cspFile = join(dir, "csp.txt");

if (!existsSync(cspFile)) {
  console.error(`serve: ${cspFile} is missing; run scripts/app_build.sh first`);
  process.exit(1);
}
const csp = readFileSync(cspFile, "utf8").trim();

const types = {
  ".html": "text/html; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".mp3": "audio/mpeg",
  ".txt": "text/plain; charset=utf-8",
};

const send = (res, status, body) => {
  res.writeHead(status, { "Content-Type": "text/plain; charset=utf-8", "X-Content-Type-Options": "nosniff" });
  res.end(body);
};

createServer((req, res) => {
  if (req.method !== "GET" && req.method !== "HEAD") return send(res, 405, "method not allowed\n");
  let path;
  try {
    path = decodeURIComponent(new URL(req.url, "http://localhost").pathname);
  } catch {
    return send(res, 400, "bad request\n");
  }
  if (path.includes("\0")) return send(res, 400, "bad request\n");
  if (path.endsWith("/")) path += "index.html";
  const file = resolve(join(dir, path));
  if (file !== dir && !file.startsWith(dir + sep)) return send(res, 403, "forbidden\n");
  if (!existsSync(file) || !statSync(file).isFile()) return send(res, 404, "not found\n");
  res.writeHead(200, {
    "Content-Type": types[extname(file)] || "application/octet-stream",
    "Content-Length": statSync(file).size,
    "Content-Security-Policy": csp,
    "X-Content-Type-Options": "nosniff",
    "Cache-Control": "no-store",
  });
  if (req.method === "HEAD") return res.end();
  createReadStream(file).pipe(res);
}).listen(port, "127.0.0.1", () => console.log(`serving ${dir} at http://127.0.0.1:${port}/`));
