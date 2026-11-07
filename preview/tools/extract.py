#!/usr/bin/env python3
"""Donnees affichees par la preview : traductions (i18n/strings.json + i18n/ids.json, communes avec l'appli Swift),
langues et regles de filtrage (lues dans macos/Sources/FlattenCore/Flatten.swift, sans rien compiler). Sortie JSON sur stdout.
Usage : extract.py <racine du projet>"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1])
LANGS = ["fr", "en", "it", "es"]

table = json.loads((ROOT / "i18n" / "strings.json").read_text(encoding="utf-8"))
ids = json.loads((ROOT / "i18n" / "ids.json").read_text(encoding="utf-8"))
translations = {
    lang: {i: (fr if lang == "fr" else table[fr][LANGS.index(lang) - 1]) for i, fr in ids.items()} for lang in LANGS
}

rules_src = (ROOT / "macos" / "Sources" / "FlattenCore" / "Flatten.swift").read_text(encoding="utf-8")


def swift_set(name: str) -> list:
    body = re.search(r"static let " + name + r"[^=]*= \[(.*?)\]\n", rules_src, re.S).group(1)
    return sorted(re.findall(r'"((?:[^"\\]|\\.)*)"', body))


print(json.dumps({
    "flattener": {
        "translations": translations,
        "languages": [["fr", "Français", "🇫🇷"], ["en", "English", "🇬🇧"], ["it", "Italiano", "🇮🇹"], ["es", "Español", "🇪🇸"]],
        "ignoredFiles": swift_set("ignoredFiles"),
        "ignoredDirs": swift_set("ignoredDirs"),
        "ignoredExtensions": swift_set("ignoredExtensions"),
        "ignoredRootFileExtensions": swift_set("ignoredRootFileExtensions"),
        "ignoredDataRootDirs": swift_set("ignoredDataRootDirs"),
    },
}, ensure_ascii=False))
