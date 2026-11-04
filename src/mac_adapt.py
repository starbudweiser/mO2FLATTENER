"""Adaptation au Mac (DXMT, ENB, DLSS) : pont entre mO2FLATTENER et l'outil en ligne de commande `mackit`.

`mackit` est le moteur Mac commun de mORTEX, mABBAJACK et mO2FLATTENER (_tools/shared/mackit) : mO2FLATTENER
l'embarque tel quel et ne fait que l'appeler (`plan`, `apply`, `undo`, `applied`, `bottles`), en JSON. Le moteur ne
renvoie aucune phrase, seulement des clés « mackit.* » {key, params} : l'interface les traduit (mac_texts.py).

Sans interface ici, et rien ne lève : une erreur de l'outil se lit dans le dictionnaire renvoyé (`ok: False`,
`error`), pour qu'elle ne fasse jamais échouer un assemblage.

Bottled Shaders : mO2FLATTENER n'a pas de clé Nexus. Il cherche l'archive (1.0.26 ou plus récente) dans les
téléchargements de l'instance MO2 puis dans ceux de mABBAJACK ; à défaut, le bilan renvoie vers la page Nexus. Il ne
télécharge ni n'embarque rien. Le pont mDLSS (d3d11.dll) n'est pas embarqué non plus : celui de mORTEX, s'il est installé.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple

BOTTLED_MOD_ID = "192816"
BOTTLED_PAGE = "https://www.nexusmods.com/skyrimspecialedition/mods/192816"
BOTTLED_MINIMUM = "1.0.26"
BACKUP_DIR = "_MAC_BACKUP"
MANIFEST = "manifest.json"
FIX_IDS = ("engine", "bridge", "displayTweaks", "duplicates", "compiler", "overrides")
# correctif -> contrôle du moteur qui dit s'il est déjà en ordre
OK_CHECKS = {"engine": "engine", "bridge": "bridge", "displayTweaks": "displayTweaks", "duplicates": "bottledDuplicates"}
# correctifs qui ne touchent que la bouteille (les autres lisent les fichiers du jeu)
BOTTLE_FIXES = ("engine",)
ARCHIVE_EXTENSIONS = (".7z", ".zip", ".rar")

Json = Dict[str, Any]


# ==============================================================================
# L'OUTIL `mackit`
# ==============================================================================

def state_file() -> Path:
    """Fichier d'état des bouteilles de l'appli (MO2FLATTENER_MAC_STATE pour les essais)."""
    custom = os.environ.get("MO2FLATTENER_MAC_STATE")
    return Path(custom) if custom else Path.home() / "Library" / "Application Support" / "mO2FLATTENER" / "bottles.json"


def mackit_path() -> Optional[Path]:
    """L'exécutable `mackit` : MACKIT_BIN, celui de l'.app (compilée par PyInstaller), sinon celui de _tools (développement)."""
    candidates: List[Path] = []
    if os.environ.get("MACKIT_BIN"):
        candidates.append(Path(os.environ["MACKIT_BIN"]))
    if getattr(sys, "frozen", False):
        exe_dir = Path(sys.executable).resolve().parent
        meipass = getattr(sys, "_MEIPASS", None)
        if meipass:
            candidates.append(Path(meipass) / "mackit")
        candidates += [exe_dir / "mackit", exe_dir.parent / "Frameworks" / "mackit", exe_dir.parent / "Resources" / "mackit"]
    candidates.append(Path(__file__).resolve().parents[2] / "_tools" / "shared" / "mackit" / "dist" / "mackit")
    for candidate in candidates:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate
    return None


def _failure(key: str = "mackit.cli.error", detail: str = "", unavailable: bool = False) -> Json:
    out: Json = {"ok": False, "error": {"text": {"key": key}, "detail": detail}}
    if unavailable:
        out["unavailable"] = True
    return out


def run(args: List[str], stdin: Optional[str] = None, timeout: int = 300) -> Json:
    """Lance `mackit <args> --json` et renvoie son JSON (code 0 ou 1) ; ne lève jamais. Un outil qui ne répond plus
    est arrêté au bout de `timeout` secondes : l'assemblage n'attend jamais indéfiniment."""
    exe = mackit_path()
    if exe is None:
        return _failure(detail="mackit not found", unavailable=True)
    cmd = [str(exe), *args, "--json", "--state", str(state_file())]
    try:
        done = subprocess.run(cmd, input=stdin, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError) as err:
        return _failure(detail=str(err))
    lines = [line for line in done.stdout.splitlines() if line.strip()]
    try:
        data = json.loads(lines[-1])
    except (IndexError, ValueError):
        return _failure(detail=(done.stderr or done.stdout or f"exit {done.returncode}")[:300])
    if not isinstance(data, dict):
        return _failure(detail="unexpected output")
    if done.returncode not in (0, 1):  # 2 = appel mal formé : un défaut de l'appli, pas du jeu
        data["ok"] = False
    return data


def text_of(obj: Optional[Json]) -> Tuple[str, Json]:
    """(clé, valeurs à insérer) d'un texte du moteur."""
    if not isinstance(obj, dict):
        return "mackit.cli.error", {}
    return str(obj.get("key", "mackit.cli.error")), dict(obj.get("params") or {})


def error_text(result: Json) -> Json:
    """Le texte de l'erreur d'un résultat en échec."""
    err = result.get("error") or {}
    return err.get("text") or {"key": "mackit.cli.error"}


# ==============================================================================
# BOUTEILLES, PONT mDLSS
# ==============================================================================

def list_bottles() -> List[Json]:
    result = run(["bottles"])
    return list(result.get("bottles") or []) if result.get("ok") else []


def _inside(child: str, parent: str) -> bool:
    child, parent = os.path.realpath(child), os.path.realpath(parent)
    return child == parent or child.startswith(parent.rstrip(os.sep) + os.sep)


def detect_bottle(bottles: List[Json], game_dir: Optional[str]) -> Tuple[Optional[Json], Optional[str]]:
    """La bouteille qui contient le dossier du jeu (« detected »), sinon la première bouteille CrossOver (« first »)."""
    if game_dir:
        for bottle in bottles:
            if _inside(game_dir, bottle["path"]):
                return bottle, "detected"
    for bottle in bottles:
        if bottle.get("kind") == "crossover":
            return bottle, "first"
    return None, None


def find_bridge() -> Optional[str]:
    """Le pont mDLSS (d3d11.dll) de mORTEX, s'il est installé sur ce Mac ; jamais embarqué ici."""
    env = os.environ.get("MO2FLATTENER_MDLSS_BRIDGE")
    if env:
        return env if os.path.isfile(env) else None
    tail = Path("mORTEX.app") / "Contents" / "Resources" / "app.asar.unpacked" / "assets" / "mdlss" / "d3d11.dll"
    for base in (Path.home() / "Applications" / "Skyrim Tools", Path("/Applications")):
        if (base / tail).is_file():
            return str(base / tail)
    return None


# ==============================================================================
# BOTTLED SHADERS : ARCHIVE DÉJÀ TÉLÉCHARGÉE
# ==============================================================================

def version_tuple(version: str) -> Tuple[int, ...]:
    """« 1.0.26 » -> (1, 0, 26) ; une version illisible est la plus ancienne."""
    parts = re.findall(r"\d+", version or "")
    return tuple(int(p) for p in parts) if parts else (0,)


def version_at_least(version: str, minimum: str) -> bool:
    a, b = version_tuple(version), version_tuple(minimum)
    size = max(len(a), len(b))
    return a + (0,) * (size - len(a)) >= b + (0,) * (size - len(b))


def _ini_value(ini: Path, key: str) -> Optional[str]:
    """Valeur d'une clé d'un .ini de MO2 (sans tenir compte de la casse ni de la section)."""
    try:
        with open(ini, "r", encoding="utf-8-sig", errors="replace") as f:
            for line in f:
                name, sep, value = line.partition("=")
                if sep and name.strip().lower() == key.lower():
                    return value.strip()
    except OSError:
        pass
    return None


def _mo2_path(value: str, base: Path) -> Optional[Path]:
    """Chemin d'un réglage MO2 (%BASE_DIR%, Z:/…, antislashs) vers un chemin du Mac."""
    value = value.strip().strip('"').replace("\\", "/")
    if value.startswith("@ByteArray(") and value.endswith(")"):
        value = value[len("@ByteArray("):-1]
    value = value.replace("%BASE_DIR%", str(base))
    if re.match(r"^[A-Za-z]:/", value):
        if value[0].upper() != "Z":  # un autre lecteur Wine : pas de correspondance simple sur le Mac
            return None
        value = value[2:]
    return Path(value) if value.startswith("/") else None


def _named_dir(parent: Path, name: str) -> Optional[Path]:
    """Sous-dossier `name` de `parent`, sans tenir compte de la casse (DOWNLOADS, downloads…)."""
    try:
        with os.scandir(parent) as entries:
            for entry in entries:
                if entry.name.lower() == name.lower() and entry.is_dir():
                    return Path(entry.path)
    except OSError:
        pass
    return None


def download_folders(mo2_dir: Path) -> List[Tuple[Path, str]]:
    """Dossiers où chercher l'archive : téléchargements de l'instance MO2, puis ceux de mABBAJACK."""
    found: List[Tuple[Path, str]] = []

    def add(folder: Optional[Path], source: str) -> None:
        if folder and folder.is_dir() and all(folder.resolve() != known.resolve() for known, _ in found):
            found.append((folder, source))

    # la racine de l'instance : le dossier choisi, ou son parent si l'utilisateur a désigné le dossier « mods »
    for base in (mo2_dir, mo2_dir.parent):
        ini = base / "ModOrganizer.ini"
        if ini.is_file():
            value = _ini_value(ini, "download_directory")
            add(_mo2_path(value, base) if value else None, "mo2")
            add(_named_dir(base, "downloads"), "mo2")
    add(_named_dir(mo2_dir, "downloads"), "mo2")
    # mABBAJACK range les archives dans <destination>/DOWNLOADS (avec l'instance), et les liens nxm dans ~/Downloads
    if os.environ.get("MABBAJACK_DOWNLOADS"):
        add(Path(os.environ["MABBAJACK_DOWNLOADS"]), "mabbajack")
    for base in (mo2_dir.parent, mo2_dir.parent.parent):
        add(_named_dir(base, "downloads"), "mabbajack")
    add(Path.home() / "Downloads", "mabbajack")
    return found


def archive_version(path: Path) -> Optional[str]:
    """Version d'une archive de Bottled Shaders : fichier .meta de MO2, sinon le nom (Nexus : « nom-192816-1-0-26-… »)."""
    meta = path.with_name(path.name + ".meta")
    if meta.is_file():
        mod_id = _ini_value(meta, "modID")
        version = _ini_value(meta, "version")
        if (mod_id is None or mod_id == BOTTLED_MOD_ID) and version:
            return version
    stem = path.stem
    found = re.search(BOTTLED_MOD_ID + r"[\s._-]+(\d+)[\s._-](\d+)[\s._-](\d+)", stem)
    if not found:
        found = re.search(r"(?<![\d.])(\d+)\.(\d+)\.(\d+)(?![\d.])", stem)
    return ".".join(found.groups()) if found else None


def find_bottled_archive(mo2_dir: Path, minimum: str = BOTTLED_MINIMUM) -> Optional[Json]:
    """L'archive de Bottled Shaders la plus récente (au moins `minimum`) déjà téléchargée, sinon None."""
    best: Optional[Json] = None
    for folder, source in download_folders(mo2_dir):
        try:
            with os.scandir(folder) as scan:
                entries = list(scan)
        except OSError:
            continue
        for entry in entries:
            lower = entry.name.lower()
            if not lower.endswith(ARCHIVE_EXTENSIONS) or "bottled" not in lower or "shaders" not in lower:
                continue
            version = archive_version(Path(entry.path))
            if not version or not version_at_least(version, minimum):
                continue
            if best is None or version_tuple(version) > version_tuple(best["version"]):
                best = {"path": entry.path, "name": entry.name, "folder": str(folder), "version": version, "source": source}
    return best


def installed_bottled_version(mo2_dir: Path, mods: List[str]) -> Optional[str]:
    """Version de Bottled Shaders d'après le meta.ini des mods actifs de l'instance (plus sûr que la DLL)."""
    best: Optional[str] = None
    for name in mods:
        meta = mo2_dir / "mods" / name / "meta.ini"
        if not meta.is_file() or _ini_value(meta, "modid") != BOTTLED_MOD_ID:
            continue
        version = _ini_value(meta, "version")
        if version and (best is None or version_tuple(version) > version_tuple(best)):
            best = version
    return best


def bottled_info(plan_bottled: Optional[Json], mo2_dir: Optional[Path]) -> Json:
    """État de Bottled Shaders du plan + archive trouvée (jamais téléchargée) et page Nexus."""
    info: Json = dict(plan_bottled or {"state": "absent", "minimum": BOTTLED_MINIMUM})
    info["page"] = BOTTLED_PAGE
    info["archive"] = None
    if info.get("state") in ("stock", "outdated", "unknown") and mo2_dir is not None:
        info["archive"] = find_bottled_archive(mo2_dir, info.get("minimum") or BOTTLED_MINIMUM)
    return info


# ==============================================================================
# SIMULATION, APPLICATION, ANNULATION
# ==============================================================================

def has_manifest(game: Path) -> bool:
    return (game / BACKUP_DIR / MANIFEST).is_file()


def plan(game: Path, bottle: Optional[str] = None, bridge: Optional[str] = None,
         bottled_version: Optional[str] = None) -> Json:
    """`mackit plan` : ce que l'adaptation ferait, sans rien écrire."""
    args = ["plan", "--game", str(game)]
    if bottle:
        args += ["--bottle", bottle]
    if bridge:
        args += ["--bridge", bridge]
    if bottled_version:
        args += ["--bottled-version", bottled_version]
    return run(args)


def apply(plan_obj: Json, only: Optional[List[str]] = None) -> Json:
    """`mackit apply` : exécute le plan tel quel (l'empreinte des fichiers protège d'un état qui a bougé)."""
    args = ["apply", "--plan", "-"]
    if only:
        args += ["--only", ",".join(only)]
    return run(args, stdin=json.dumps(plan_obj))


def undo(game: Path, target: str) -> Json:
    """`mackit undo <id|all>` : remet les fichiers d'origine depuis <jeu>/_MAC_BACKUP."""
    return run(["undo", "--game", str(game), target])


def applied(game: Path) -> List[Json]:
    """Ce que le manifeste dit appliqué (carte « Bilan Mac »)."""
    result = run(["applied", "--game", str(game)])
    return list(result.get("applied") or []) if result.get("ok") else []


def summarize_plan(plan_obj: Json) -> Json:
    """Le plan sans ce qui sert seulement à l'appliquer (opérations, empreintes) : de quoi l'annoncer."""
    return {
        "gamePath": plan_obj.get("gamePath"),
        "fixes": [{"id": f["id"], "title": f["title"], "detail": f["detail"], "files": f.get("files", []),
                   "changes": f.get("changes")} for f in plan_obj.get("fixes", [])],
        "skipped": plan_obj.get("skipped", []),
        "discarded": plan_obj.get("discarded", []),
        "bottled": plan_obj.get("bottled"),
        "ok": already_ok(plan_obj),
    }


def already_ok(plan_obj: Json) -> List[str]:
    """Les points que le moteur a contrôlés et trouvés « ok » (ni à faire ni écartés) : seuls ceux-là sont annoncés « déjà en
    ordre ». Un contrôle « na » (pas de Bottled Shaders, pas de SSE Display Tweaks…) ne dit rien : on ne l'annonce pas."""
    statuses = {c.get("id"): c.get("status") for c in plan_obj.get("checks", [])}
    decided = {f["id"] for f in plan_obj.get("fixes", [])} | {s["id"] for s in plan_obj.get("skipped", [])}
    return [fix for fix, check in OK_CHECKS.items() if fix not in decided and statuses.get(check) == "ok"]


def preview(game: Path, bottle: Optional[str], mo2_dir: Optional[Path] = None, mods: Optional[List[str]] = None) -> Json:
    """Annonce du kit DXMT, avant l'assemblage. Un jeu cible qui n'existe pas encore est simulé sur un dossier vide : seuls
    les correctifs de la bouteille ressortent, le reste sera examiné à la fin de l'assemblage (`future`).
    Le kit est pour une bouteille CrossOver : sans bouteille, rien n'est annoncé (`nobottle`), jamais de demi-mesure."""
    if not bottle:
        return {"kind": "nobottle"}
    future = not (game / "Data").is_dir()
    version = installed_bottled_version(mo2_dir, mods or []) if mo2_dir and mods else None
    with tempfile.TemporaryDirectory(prefix="mo2flattener_mac_") as empty:
        result = plan(Path(empty) if not game.is_dir() else game, bottle, find_bridge(), version)
    if result.get("unavailable"):
        return {"kind": "unavailable"}
    if not result.get("ok"):
        return {"kind": "error", "error": error_text(result)}
    plan_obj = result["plan"]
    previous = applied(game) if has_manifest(game) else []
    summary = summarize_plan(plan_obj)
    if previous:
        summary["ok"] = []  # l'adaptation précédente sera annulée puis refaite : rien n'est « déjà en ordre »
    elif future:
        summary["ok"] = [i for i in summary["ok"] if i in BOTTLE_FIXES]  # le reste dépend de fichiers du jeu, pas encore là
    return {"kind": "plan", "future": future, "plan": summary,
            "bottled": bottled_info(plan_obj.get("bottled"), mo2_dir), "previous": len(previous)}


Notify = Callable[[str, Json], None]


def undo_previous(game: Path, notify: Optional[Notify] = None) -> int:
    """Un nouvel assemblage écrase les fichiers que l'adaptation précédente avait changés : on l'annule d'abord (le
    manifeste reste ainsi juste). Renvoie le nombre de correctifs annulés ; ne lève jamais."""
    notify = notify or (lambda event, payload: None)
    try:
        if not has_manifest(game):
            return 0
        before = applied(game)
        if not before:
            return 0
        result = undo(game, "all")
        fixes = result.get("fixes") or []
        restored = sum(1 for f in fixes if f.get("status") == "restored")
        if restored:
            notify("previous_undone", {"n": restored})
        if any(f.get("status") == "refused" for f in fixes) or (not result.get("ok") and not fixes):
            notify("previous_refused", {})
        return restored
    except Exception:  # un défaut de l'adaptation ne doit jamais arrêter l'assemblage
        return 0


def finish_stock(game: Path, notify: Optional[Notify] = None) -> Json:
    """Dossier universel (Stock) : rien n'est copié ni modifié, `mackit` n'est même pas lancé. Bilan simple."""
    notify = notify or (lambda event, payload: None)
    notify("stock", {})
    return {"mode": "stock", "game": str(game), "bottle": None, "items": [], "discarded": [], "bottled": None,
            "applied": [], "error": None, "unavailable": False, "undone": 0}


def finish(game: Path, bottle: Optional[str], mo2_dir: Optional[Path] = None, mods: Optional[List[str]] = None,
           notify: Optional[Notify] = None) -> Json:
    """Fin d'assemblage, kit DXMT pour une bouteille CrossOver : `plan` puis `apply` sur le jeu assemblé, et le bilan.
    Sans bouteille, rien n'est touché (`no_bottle`). Ne lève jamais.

    `notify(événement, données)` annonce chaque étape (start, fix, skip, applied, failed, none, done) pour le journal.
    Bilan : { game, bottle, items: [{ id, status: applied|failed|skipped, undoable, title, detail?, text?, reason?,
    files, changes? }], discarded, bottled, applied, error?, unavailable? }.
    """
    notify = notify or (lambda event, payload: None)
    report: Json = {"mode": "crossover", "game": str(game), "bottle": None, "items": [], "discarded": [], "bottled": None,
                    "applied": [], "error": None, "unavailable": False, "undone": 0}
    try:
        if not bottle:  # le kit est pour une bouteille CrossOver : sans bouteille, aucune demi-mesure
            report["no_bottle"] = True
            notify("no_bottle", {})
            return report
        notify("start", {})
        bottles = list_bottles() if bottle else []
        report["bottle"] = next((b for b in bottles if b["path"] == bottle), None)
        version = installed_bottled_version(mo2_dir, mods or []) if mo2_dir and mods else None
        result = plan(game, bottle, find_bridge(), version)
        if result.get("unavailable"):
            report["unavailable"] = True
            report["error"] = error_text(result)
            return report
        if not result.get("ok"):
            report["error"] = error_text(result)
            notify("error", {"text": report["error"], "detail": (result.get("error") or {}).get("detail", "")})
            return report
        plan_obj = result["plan"]
        report["bottled"] = bottled_info(plan_obj.get("bottled"), mo2_dir)
        report["discarded"] = plan_obj.get("discarded", [])
        fixes, skipped = plan_obj.get("fixes", []), plan_obj.get("skipped", [])
        for fix in fixes:
            notify("fix", {"id": fix["id"], "title": fix["title"]})
        for skip in skipped:
            notify("skip", {"id": skip["id"], "title": {"key": f"mackit.fix.{skip['id']}.title"}})

        outcomes: List[Json] = []
        applied_now: List[Json] = []
        if fixes:
            done = apply(plan_obj)
            outcomes = list(done.get("outcomes") or [])
            applied_now = list(done.get("applied") or [])
            if not outcomes:  # l'outil a refusé le plan en bloc : chaque correctif est noté échoué avec la raison
                reason = error_text(done)
                outcomes = [{"id": f["id"], "status": "failed", "text": reason} for f in fixes]
        by_id = {o["id"]: o for o in outcomes}
        for fix in fixes:
            outcome = by_id.get(fix["id"])
            ok = bool(outcome and outcome.get("status") == "applied")
            report["items"].append({
                "id": fix["id"], "status": "applied" if ok else "failed", "undoable": False, "title": fix["title"],
                "detail": fix["detail"], "text": outcome.get("text") if outcome else None,
                "files": fix.get("files", []), "changes": fix.get("changes"),
            })
            notify("applied" if ok else "failed", {"id": fix["id"], "title": fix["title"]})
        for skip in skipped:
            report["items"].append({"id": skip["id"], "status": "skipped", "undoable": False,
                                    "title": {"key": f"mackit.fix.{skip['id']}.title"}, "reason": skip["reason"], "files": []})
        report["applied"] = applied_now or (applied(game) if has_manifest(game) else [])
        registered = {a["id"] for a in report["applied"]}
        for item in report["items"]:  # seuls les correctifs inscrits au manifeste s'annulent
            item["undoable"] = item["status"] == "applied" and item["id"] in registered
        if not report["items"]:
            notify("none", {})
        notify("done", {
            "applied": sum(1 for i in report["items"] if i["status"] == "applied"),
            "failed": sum(1 for i in report["items"] if i["status"] == "failed"),
            "skipped": sum(1 for i in report["items"] if i["status"] == "skipped"),
        })
    except Exception as err:  # jamais fatal pour l'assemblage
        report["error"] = {"key": "mackit.cli.error"}
        notify("error", {"text": report["error"], "detail": str(err)})
    return report


def report_after_undo(report: Json, result: Json) -> Json:
    """Le bilan après une annulation : un correctif annulé en disparaît, un refus est dit sous sa ligne."""
    updated = dict(report)
    fixes = result.get("fixes") or []
    restored = {f["id"] for f in fixes if f.get("status") == "restored"}
    refused = {f["id"]: f for f in fixes if f.get("status") == "refused"}
    still = {a["id"] for a in (result.get("applied") or [])} if "applied" in result else None
    items = []
    for item in report.get("items", []):
        if item["status"] == "applied" and item["id"] in restored:
            continue
        item = dict(item)
        if still is not None and item["status"] == "applied":
            item["undoable"] = item["id"] in still
        if item["id"] in refused:
            item["refusal"] = refused[item["id"]].get("text")
        else:
            item.pop("refusal", None)
        items.append(item)
    updated["items"] = items
    updated["applied"] = list(result.get("applied") or []) if still is not None else report.get("applied", [])
    updated["undone"] = int(report.get("undone", 0)) + len(restored)
    return updated
