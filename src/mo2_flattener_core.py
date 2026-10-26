"""Moteur de mO2FLATTENER, sans interface : lecture de modlist.txt, résolution des conflits, copie.

Règles MO2 (modorganizer, profile.cpp) : modlist.txt va de la priorité la plus HAUTE à la plus basse ;
« + » actif, « - » désactivé, « * » DLC ou Creation Club (pas un dossier de mod). Le dossier overwrite a
toujours la priorité maximale. Les mods « Root Builder » rangent les fichiers de la racine du jeu dans Root/.
Les noms sont comparés sans tenir compte de la casse (comme Windows), mais copiés avec leur casse d'origine.
"""
import ctypes
import ctypes.util
import os
import shutil
from pathlib import Path
from typing import Callable, Dict, List, Tuple

IGNORED_FILES = {"meta.ini"}
IGNORED_DIRS = {".git", ".svn", "__pycache__"}
IGNORED_EXTENSIONS = {".pdb", ".mohidden"}

# Extensions parasites à ignorer directement à la racine de Data
IGNORED_ROOT_FILE_EXTENSIONS = {".txt", ".md", ".html", ".modgroups", ".ds_store"}

# Dossiers parasites inertes à ignorer dans Data
IGNORED_DATA_ROOT_DIRS = {
    "fomod",
    "docs",
    "documentation",
    "readme",
    "readmes",
    "hashtags",
    "3dnpc-amm",
    "dip",
    "oathvein racemenu dip",
    "headpartwhitelist",
    "optional",
    "source",
    "merge",
    "echizen spear remastered readme",
    "ax_readmefiles",
    "amidianborn optional plugins",
    ".esp",
    ".esp version",
    "esl",
    "esp",
}

# Une tâche : (fichier source, chemin de destination)
Task = Tuple[Path, Path]


def is_ignored_file(filename: str, is_data_root: bool = False) -> bool:
    """Vérifie si un fichier doit être ignoré."""
    if filename in IGNORED_FILES:
        return True
    lower_name = filename.lower()
    if lower_name.endswith(".mohidden"):
        return True
    ext = os.path.splitext(lower_name)[1]
    if ext in IGNORED_EXTENSIONS:
        return True
    if is_data_root and ext in IGNORED_ROOT_FILE_EXTENSIONS:
        return True
    return False


def is_ignored_dir(dirname: str) -> bool:
    """Vérifie si un dossier doit être ignoré."""
    lower = dirname.lower()
    if lower in IGNORED_DIRS or lower in IGNORED_DATA_ROOT_DIRS:
        return True
    return lower.endswith(".mohidden")


def filter_dirs_in_place(dirs: List[str]) -> None:
    dirs[:] = [d for d in dirs if not is_ignored_dir(d)]


def parse_modlist(modlist_path: Path) -> List[str]:
    """Mods actifs, de la priorité la plus basse à la plus haute (ordre d'application)."""
    with open(modlist_path, "r", encoding="utf-8-sig") as f:
        lines = [line.strip() for line in f if line.strip()]
    active_mods = []
    for line in reversed(lines):
        if line.startswith("+"):
            m = line[1:].strip()
            if m and not m.endswith("_separator"):
                active_mods.append(m)
    return active_mods


def find_stock_game(mo2_dir: Path) -> Path | None:
    for candidate in (mo2_dir.parent / "STOCK GAME", mo2_dir / "STOCK GAME"):
        if candidate.is_dir():
            return candidate
    return None


class _FileMap:
    """Chemins relatifs indexés sans casse ; le dernier ajouté gagne, sa casse est conservée."""

    def __init__(self):
        self.files: Dict[str, Tuple[Path, Path]] = {}

    def add(self, rel: Path, src: Path) -> None:
        self.files[str(rel).lower()] = (rel, src)

    def tasks(self, dest: Path) -> List[Task]:
        return [(src, dest / rel) for rel, src in self.files.values()]


def _walk_data(base: Path, data_map: _FileMap, skip_root_dir: bool = False) -> None:
    for root, dirs, files in os.walk(base):
        filter_dirs_in_place(dirs)
        if skip_root_dir and Path(root) == base:
            dirs[:] = [d for d in dirs if d != "Root"]
        for f in files:
            full_p = Path(root) / f
            rel_p = full_p.relative_to(base)
            if is_ignored_file(f, is_data_root=len(rel_p.parts) == 1):
                continue
            if rel_p.parts and rel_p.parts[0].lower() in IGNORED_DATA_ROOT_DIRS:
                continue
            data_map.add(rel_p, full_p)


def build_tasks(mo2_dir: Path, modlist_file: Path, dest_game_root: Path,
                stopped: Callable[[], bool] = lambda: False) -> List[Task]:
    """Liste des copies à faire, conflits déjà résolus : STOCK GAME, puis les mods par priorité, puis overwrite."""
    data_map, root_map = _FileMap(), _FileMap()

    stock_game_dir = find_stock_game(mo2_dir)
    if stock_game_dir:
        for root, dirs, files in os.walk(stock_game_dir):
            if stopped():
                return []
            filter_dirs_in_place(dirs)
            for f in files:
                full_p = Path(root) / f
                rel_p = full_p.relative_to(stock_game_dir)
                parts = rel_p.parts
                is_data = bool(parts and parts[0].lower() == "data")
                if is_ignored_file(f, is_data_root=is_data and len(parts) == 2):
                    continue
                if is_data:
                    sub_parts = parts[1:]
                    if sub_parts and sub_parts[0].lower() in IGNORED_DATA_ROOT_DIRS:
                        continue
                    data_map.add(Path(*sub_parts), full_p)
                else:
                    root_map.add(rel_p, full_p)

    mods_dir = mo2_dir / "mods"
    for mod_name in parse_modlist(modlist_file):
        if stopped():
            return []
        mod_path = mods_dir / mod_name
        if not mod_path.is_dir() or is_ignored_dir(mod_name):
            continue

        root_builder_dir = mod_path / "Root"
        if root_builder_dir.is_dir():
            for root, dirs, files in os.walk(root_builder_dir):
                filter_dirs_in_place(dirs)
                for f in files:
                    if not is_ignored_file(f):
                        full_p = Path(root) / f
                        root_map.add(full_p.relative_to(root_builder_dir), full_p)

        nested_data = mod_path / "Data"
        if nested_data.is_dir() and not (mod_path / "textures").is_dir() and not (mod_path / "meshes").is_dir():
            _walk_data(nested_data, data_map)
        else:
            _walk_data(mod_path, data_map, skip_root_dir=True)

    overwrite_dir = mo2_dir / "overwrite"
    if overwrite_dir.is_dir():
        _walk_data(overwrite_dir, data_map)

    return root_map.tasks(dest_game_root) + data_map.tasks(dest_game_root / "Data")


# clonefile(2) : copie APFS instantanée qui partage les blocs de données (aucune place en plus) tout en restant
# un fichier indépendant, contrairement à un lien physique. Échoue entre deux volumes ou hors APFS.
_libc = ctypes.CDLL(ctypes.util.find_library("c"), use_errno=True)
_clonefile = getattr(_libc, "clonefile", None)
if _clonefile is not None:
    _clonefile.argtypes = (ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint32)
    _clonefile.restype = ctypes.c_int


def clone_file(src: Path, dst: Path) -> bool:
    if _clonefile is None:
        return False
    return _clonefile(os.fsencode(src), os.fsencode(dst), 0) == 0


def optimized_copy_file(src: Path, dst: Path, use_hardlinks: bool) -> str:
    """Copie APFS si possible, sinon lien physique (si demandé), sinon copie complète. Renvoie la méthode."""
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists() or dst.is_symlink():
        try:
            dst.unlink()
        except OSError:
            pass

    if clone_file(src, dst):
        return "clone"
    if use_hardlinks:
        try:
            os.link(src, dst)
            return "link"
        except OSError:
            pass

    with open(src, "rb") as fsrc, open(dst, "wb") as fdst:
        shutil.copyfileobj(fsrc, fdst, length=1024 * 1024)
    shutil.copystat(src, dst)
    return "copy"
