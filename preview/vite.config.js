import { defineConfig } from "vite";
import { execFileSync } from "node:child_process";
import { resolve } from "node:path";

const ROOT = __dirname;
const PY_SRC = resolve(ROOT, "../src");
const SOCLE = "/Volumes/SKYRIM/TOOLS/DESIGN/Socle";
const VIRTUAL_ID = "virtual:app-data";
const RESOLVED_ID = "\0" + VIRTUAL_ID;

// Expose les traductions et règles des applis PyQt6 (lues par AST, sans exécution)
// et recharge la preview à chaque modification d'un fichier src/*.py.
function pythonSources() {
  return {
    name: "python-sources",
    resolveId(id) {
      if (id === VIRTUAL_ID) return RESOLVED_ID;
    },
    load(id) {
      if (id !== RESOLVED_ID) return;
      const json = execFileSync("python3", ["-I", resolve(ROOT, "tools/extract.py"), PY_SRC], { encoding: "utf-8" });
      return `export default ${json};`;
    },
    configureServer(server) {
      server.watcher.add(PY_SRC); // chokidar 4 (Vite 6) n'accepte plus les globs
      server.watcher.on("change", (file) => {
        if (!file.startsWith(PY_SRC) || !file.endsWith(".py")) return;
        const mod = server.moduleGraph.getModuleById(RESOLVED_ID);
        if (mod) server.moduleGraph.invalidateModule(mod);
        server.ws.send({ type: "full-reload" });
      });
    },
  };
}

export default defineConfig({
  plugins: [pythonSources()],
  resolve: { alias: { "@socle": SOCLE } },
  server: { port: Number(process.env.PORT) || 5174, fs: { allow: [ROOT, SOCLE] } },
});
