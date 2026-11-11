// Fable.Mocha calls the global describe/it of mocha. Node's own runner has the same two, so the
// page's tests run with no npm package: this file exposes them, then loads the compiled tests.
import { describe, it } from "node:test";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

globalThis.describe = describe;
globalThis.it = it;
await import(pathToFileURL(resolve(process.argv[2])).href);
