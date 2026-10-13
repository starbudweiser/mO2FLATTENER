// Mini système de fichiers en mémoire pour la preview (aucun accès au disque réel).

export class MockFS {
  constructor(spec) {
    this.spec = spec; // { "/abs/dir": [ "rel/file" | { path, size, locked } | "rel/dir/" ] }
    this.reset();
  }

  reset() {
    this.roots = new Map();
    for (const [root, entries] of Object.entries(this.spec)) {
      const tree = dirNode();
      for (const e of entries) {
        const item = typeof e === "string" ? { path: e } : e;
        const parts = item.path.split("/").filter(Boolean);
        const isDir = item.path.endsWith("/");
        let node = tree;
        const dirs = isDir ? parts : parts.slice(0, -1);
        for (const d of dirs) {
          if (!node.dirs.has(d)) node.dirs.set(d, dirNode());
          node = node.dirs.get(d);
        }
        if (!isDir) node.files.set(parts.at(-1), { size: item.size ?? 1024, locked: !!item.locked });
      }
      this.roots.set(root, tree);
    }
  }

  /** Nœud d'un chemin absolu, ou null. */
  node(path) {
    const p = normalize(path);
    for (const [root, tree] of this.roots) {
      if (p === root) return tree;
      if (p.startsWith(root + "/")) {
        let node = tree;
        for (const part of p.slice(root.length + 1).split("/")) {
          node = node.dirs.get(part);
          if (!node) return null;
        }
        return node;
      }
    }
    return null;
  }

  isDir(path) { return !!this.node(path); }

  isFile(path) {
    const p = normalize(path);
    const i = p.lastIndexOf("/");
    const parent = this.node(p.slice(0, i));
    return !!parent?.files.has(p.slice(i + 1));
  }

  file(path) {
    const p = normalize(path);
    const i = p.lastIndexOf("/");
    return this.node(p.slice(0, i))?.files.get(p.slice(i + 1)) ?? null;
  }

  /** os.walk(top, topdown) : génère [root, dirNames[], fileNames[]]. */
  *walk(top, topdown = true) {
    const start = this.node(top);
    if (!start) return;
    function* rec(path, node) {
      const dirs = [...node.dirs.keys()];
      const files = [...node.files.keys()];
      if (topdown) {
        yield [path, dirs, files]; // dirs modifiable sur place (filtrage)
        for (const d of dirs) if (node.dirs.has(d)) yield* rec(`${path}/${d}`, node.dirs.get(d));
      } else {
        for (const d of dirs) yield* rec(`${path}/${d}`, node.dirs.get(d));
        yield [path, dirs, files];
      }
    }
    yield* rec(normalize(top), start);
  }

  remove(path) {
    const p = normalize(path);
    const i = p.lastIndexOf("/");
    const f = this.file(p);
    if (f?.locked) throw new Error(`[Errno 13] Permission denied: '${p}'`);
    this.node(p.slice(0, i))?.files.delete(p.slice(i + 1));
  }

  rmtree(path) {
    const p = normalize(path);
    const i = p.lastIndexOf("/");
    this.node(p.slice(0, i))?.dirs.delete(p.slice(i + 1));
  }
}

function dirNode() { return { dirs: new Map(), files: new Map() }; }

export const normalize = (p) => p.trim().replace(/\/+$/, "");
export const relpath = (path, base) => path.slice(normalize(base).length + 1);
export const basename = (p) => normalize(p).split("/").at(-1);
