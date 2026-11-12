import { defineConfig } from "vite";
import elm from "vite-plugin-elm";

// base "./": every URL in the built page is relative, so it works from any path it is served under.
// public/ (style.css, the vendored MapLibre, fonts, sound, trail files) is copied as it is: the page
// loads MapLibre by URL at run time (js/maplibre_ffi.mjs), and style.css is shared with the static pages.
export default defineConfig({
  base: "./",
  publicDir: "public",
  plugins: [elm({ optimize: true })],
  build: { outDir: "dist", emptyOutDir: true, modulePreload: false, target: "es2020" },
});
