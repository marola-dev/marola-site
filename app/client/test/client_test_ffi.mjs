import { readFileSync } from "node:fs";
import { Ok, Error } from "./gleam.mjs";

export function read_file(path) {
  try {
    return new Ok(readFileSync(path, "utf8"));
  } catch (e) {
    return new Error(String(e.code ?? e));
  }
}
