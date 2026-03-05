import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  define: {
    "process.env.NODE_ENV": JSON.stringify("production"),
  },
  build: {
    cssCodeSplit: false,
    outDir: "dist",
    emptyOutDir: true,
    lib: {
      entry: "src/index.tsx",
      formats: ["iife"],
      name: "StudioWidget",
      fileName: () => "index.js",
    },
    rollupOptions: {
      output: {
        assetFileNames: (assetInfo) =>
          assetInfo.name?.endsWith(".css") ? "style.css" : "assets/[name].[ext]",
      },
    },
  },
});
