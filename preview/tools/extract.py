#!/usr/bin/env python3
"""Extrait des sources Python (sans les exécuter) les données affichées par la preview :
traductions, langues, règles de filtrage. Sortie JSON sur stdout."""
import ast
import json
import sys
from pathlib import Path

SRC = Path(sys.argv[1])


def module(name: str) -> ast.Module:
    return ast.parse((SRC / name).read_text(encoding="utf-8"))


def top_level(tree: ast.Module) -> dict:
    """Constantes de niveau module (dict, list, set de littéraux)."""
    out = {}
    for node in tree.body:
        target = None
        if isinstance(node, ast.Assign) and isinstance(node.targets[0], ast.Name):
            target, value = node.targets[0].id, node.value
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name) and node.value:
            target, value = node.target.id, node.value
        if target and target.isupper():
            try:
                v = ast.literal_eval(value)
            except ValueError:
                continue
            out[target] = sorted(v) if isinstance(v, set) else v
    return out


flattener = module("mo2_flattener_gui.py")
f = top_level(flattener)

print(json.dumps({
    "flattener": {
        "translations": f["TRANSLATIONS"],
        "languages": f["AVAILABLE_LANGUAGES"],
        "ignoredFiles": f["IGNORED_FILES"],
        "ignoredDirs": f["IGNORED_DIRS"],
        "ignoredExtensions": f["IGNORED_EXTENSIONS"],
        "ignoredRootFileExtensions": f["IGNORED_ROOT_FILE_EXTENSIONS"],
        "ignoredDataRootDirs": f["IGNORED_DATA_ROOT_DIRS"],
    },
}, ensure_ascii=False))
