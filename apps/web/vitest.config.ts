import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
import path from "node:path";
export default defineConfig({
  plugins: [react()],
  resolve: { alias: { "@": path.resolve(__dirname, "./src") } },
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: ["./src/test/setup.ts"],
    // convex-test needs the edge-runtime-ish server env for convex/*.test.ts;
    // use jsdom for src and let convex-test provide its own module env.
    server: { deps: { inline: ["convex-test"] } },
  },
});
