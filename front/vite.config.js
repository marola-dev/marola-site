import { defineConfig } from "vite";
import elm from "vite-plugin-elm";

// base "./": every URL in the built page is relative, so it works from any path it is served under.
// The vendored MapLibre is loaded at run time by URL (js/maplibre_ffi.mjs), never bundled.
export default defineConfig({
  base: "./",
  publicDir: false,
  plugins: [elm({ optimize: true })],
  build: { outDir: "dist", emptyOutDir: true, modulePreload: false, target: "es2020" },
});
