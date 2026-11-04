"""Adaptation au Mac : textes ×4, recherche de Bottled Shaders, bouteille, bilan, et l'outil `mackit` sur un faux jeu
et une fausse bouteille (jamais sur une vraie). Les essais qui lancent `mackit` sont ignorés si l'exécutable manque
(compiler avec _tools/shared/mackit/build.sh)."""
import hashlib
import json
import os
import re
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

import mac_adapt  # noqa: E402
from mac_texts import MAC_TEXTS, MAC_UI  # noqa: E402

LANGS = ("fr", "en", "es", "it")
HAVE_MACKIT = mac_adapt.mackit_path() is not None


def placeholders(text: str):
    return sorted(re.findall(r"\{(\w+)\}", text))


class TestTexts(unittest.TestCase):
    def test_same_ui_keys_in_four_languages(self):
        for lang in LANGS:
            self.assertEqual(set(MAC_UI[lang]), set(MAC_UI["fr"]), lang)
            self.assertEqual(set(MAC_TEXTS[lang]), set(MAC_TEXTS["fr"]), lang)

    def test_same_values_to_insert_in_four_languages(self):
        for table in (MAC_UI, MAC_TEXTS):
            for key, fr in table["fr"].items():
                for lang in LANGS[1:]:
                    self.assertEqual(placeholders(table[lang][key]), placeholders(fr), f"{lang} {key}")

    def test_no_empty_text_and_no_hardcoded_fallback(self):
        for table in (MAC_UI, MAC_TEXTS):
            for lang in LANGS:
                for key, text in table[lang].items():
                    self.assertTrue(text.strip(), f"{lang} {key}")

    @unittest.skipUnless(HAVE_MACKIT, "mackit absent")
    def test_every_key_mackit_can_return_is_translated(self):
        keys = mac_adapt.run(["texts"])["keys"]
        self.assertGreater(len(keys), 30)
        for lang in LANGS:
            self.assertEqual([k for k in keys if k not in MAC_TEXTS[lang]], [], lang)


class TestBottled(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name).resolve()
        self.mo2 = self.base / "inst"
        self.mo2.mkdir()
        self.old_home = os.environ.get("HOME")
        os.environ["HOME"] = str(self.base / "home")  # ~/Downloads de l'essai
        (self.base / "home" / "Downloads").mkdir(parents=True)

    def tearDown(self):
        os.environ["HOME"] = self.old_home
        self.tmp.cleanup()

    def put(self, path: Path, content: str = "x") -> Path:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def test_versions(self):
        self.assertTrue(mac_adapt.version_at_least("1.0.26", "1.0.26"))
        self.assertTrue(mac_adapt.version_at_least("1.0.27", "1.0.26"))
        self.assertTrue(mac_adapt.version_at_least("1.1", "1.0.26"))
        self.assertTrue(mac_adapt.version_at_least("2.0.0", "1.0.26"))
        self.assertFalse(mac_adapt.version_at_least("1.0.25", "1.0.26"))
        self.assertFalse(mac_adapt.version_at_least("", "1.0.26"))

    def test_archive_version_from_names(self):
        v = lambda name: mac_adapt.archive_version(Path(name))  # noqa: E731
        self.assertEqual(v("Bottled Shaders-192816-1-0-26-1762131614.7z"), "1.0.26")  # nom MO2 / Nexus
        self.assertEqual(v("Bottled Shaders 192816 1.0.26 2026-11-03T00-59Z VMSnJCbr4.7z"), "1.0.26")  # nom mABBAJACK
        self.assertEqual(v("Bottled Shaders 1.0.27.zip"), "1.0.27")
        self.assertIsNone(v("Bottled Shaders.7z"))

    def test_archive_version_from_meta_file(self):
        archive = self.put(self.mo2 / "downloads" / "BS.7z")
        self.put(self.mo2 / "downloads" / "BS.7z.meta", "[General]\nmodID=192816\nversion=1.0.28\n")
        self.assertEqual(mac_adapt.archive_version(archive), "1.0.28")
        self.put(self.mo2 / "downloads" / "BS.7z.meta", "[General]\nmodID=1234\nversion=1.0.28\n")  # un autre mod
        self.assertIsNone(mac_adapt.archive_version(archive))

    def test_finds_newest_archive_in_mo2_downloads_first(self):
        self.put(self.mo2 / "ModOrganizer.ini", "[Settings]\ndownload_directory=%BASE_DIR%/dl\n")
        for name in ("Bottled Shaders-192816-1-0-25-1.7z", "Bottled Shaders-192816-1-0-26-2.7z",
                     "Bottled Shaders-192816-1-0-27-3.7z", "Other Mod-1-0-99.7z", "Bottled Shaders-192816-1-0-30-4.7z.part"):
            self.put(self.mo2 / "dl" / name)
        found = mac_adapt.find_bottled_archive(self.mo2)
        self.assertEqual(found["version"], "1.0.27")
        self.assertEqual(found["source"], "mo2")
        self.assertEqual(Path(found["path"]).parent, self.mo2 / "dl")

    def test_nothing_below_the_minimum(self):
        self.put(self.mo2 / "downloads" / "Bottled Shaders-192816-1-0-25-1.7z")
        self.assertIsNone(mac_adapt.find_bottled_archive(self.mo2))
        self.assertEqual(mac_adapt.find_bottled_archive(self.mo2, "1.0.25")["version"], "1.0.25")

    def test_falls_back_to_mabbajack_folders(self):
        # <destination>/DOWNLOADS à côté de l'instance, puis ~/Downloads
        self.put(self.base / "DOWNLOADS" / "Bottled Shaders 192816 1.0.26 2026-11-03T00-59Z abc.7z")
        found = mac_adapt.find_bottled_archive(self.mo2)
        self.assertEqual(found["source"], "mabbajack")
        (self.base / "DOWNLOADS" / "Bottled Shaders 192816 1.0.26 2026-11-03T00-59Z abc.7z").unlink()
        self.assertIsNone(mac_adapt.find_bottled_archive(self.mo2))
        self.put(self.base / "home" / "Downloads" / "Bottled Shaders-192816-1-0-26-9.zip")
        self.assertEqual(mac_adapt.find_bottled_archive(self.mo2)["source"], "mabbajack")

    def test_mo2_folder_wins_over_mabbajack(self):
        self.put(self.mo2 / "downloads" / "Bottled Shaders-192816-1-0-26-1.7z")
        self.put(self.base / "DOWNLOADS" / "Bottled Shaders-192816-1-0-26-2.7z")
        self.assertEqual(mac_adapt.find_bottled_archive(self.mo2)["source"], "mo2")

    def test_mo2_paths(self):
        base = Path("/x/inst")
        self.assertEqual(mac_adapt._mo2_path("%BASE_DIR%/downloads", base), Path("/x/inst/downloads"))
        self.assertEqual(mac_adapt._mo2_path("Z:\\Volumes\\Big\\dl", base), Path("/Volumes/Big/dl"))
        self.assertIsNone(mac_adapt._mo2_path("C:/Users/me/dl", base))  # un autre lecteur Wine

    def test_installed_version_from_mod_metadata(self):
        self.put(self.mo2 / "mods" / "Bottled" / "meta.ini", "[General]\nmodid=192816\nversion=1.0.26\n")
        self.put(self.mo2 / "mods" / "Other" / "meta.ini", "[General]\nmodid=5\nversion=9.9.9\n")
        self.assertEqual(mac_adapt.installed_bottled_version(self.mo2, ["Other", "Bottled", "Missing"]), "1.0.26")
        self.assertIsNone(mac_adapt.installed_bottled_version(self.mo2, ["Other"]))

    def test_bottled_info_only_looks_for_an_archive_when_needed(self):
        self.put(self.mo2 / "downloads" / "Bottled Shaders-192816-1-0-26-1.7z")
        ok = mac_adapt.bottled_info({"state": "ok", "minimum": "1.0.26"}, self.mo2)
        self.assertIsNone(ok["archive"])
        stale = mac_adapt.bottled_info({"state": "outdated", "minimum": "1.0.26"}, self.mo2)
        self.assertEqual(stale["archive"]["version"], "1.0.26")
        self.assertEqual(stale["page"], "https://www.nexusmods.com/skyrimspecialedition/mods/192816")
        none = mac_adapt.bottled_info({"state": "stock", "minimum": "1.0.99"}, self.mo2)
        self.assertIsNone(none["archive"])  # « à télécharger » : la page Nexus


class TestBottles(unittest.TestCase):
    BOTTLES = [
        {"path": "/b/One", "name": "One", "kind": "wine"},
        {"path": "/b/Two", "name": "Two", "kind": "crossover"},
        {"path": "/b/Three", "name": "Three", "kind": "crossover"},
    ]

    def test_detected_when_the_game_is_inside(self):
        bottle, how = mac_adapt.detect_bottle(self.BOTTLES, "/b/Three/drive_c/Games/Skyrim")
        self.assertEqual((bottle["name"], how), ("Three", "detected"))

    def test_first_crossover_bottle_otherwise(self):
        bottle, how = mac_adapt.detect_bottle(self.BOTTLES, "/Volumes/Games/Skyrim")
        self.assertEqual((bottle["name"], how), ("Two", "first"))
        self.assertEqual(mac_adapt.detect_bottle(self.BOTTLES, None)[1], "first")

    def test_no_bottle(self):
        self.assertEqual(mac_adapt.detect_bottle([], "/x"), (None, None))
        self.assertEqual(mac_adapt.detect_bottle([self.BOTTLES[0]], "/x"), (None, None))  # pas de CrossOver

    def test_sibling_folder_is_not_inside(self):
        self.assertEqual(mac_adapt.detect_bottle(self.BOTTLES, "/b/TwoExtra/x")[1], "first")


class TestReport(unittest.TestCase):
    def report(self):
        return {"game": "/g", "undone": 0, "applied": [{"id": "engine"}, {"id": "duplicates"}], "items": [
            {"id": "engine", "status": "applied", "undoable": True, "title": {"key": "mackit.fix.engine.title"}, "files": []},
            {"id": "duplicates", "status": "applied", "undoable": True, "title": {"key": "mackit.fix.duplicates.title"}, "files": []},
            {"id": "bridge", "status": "skipped", "undoable": False, "title": {"key": "mackit.fix.bridge.title"}, "files": []},
        ]}

    def test_undone_fix_disappears(self):
        result = {"ok": True, "fixes": [{"id": "engine", "status": "restored", "text": {"key": "mackit.undo.ok"}}],
                  "applied": [{"id": "duplicates"}]}
        out = mac_adapt.report_after_undo(self.report(), result)
        self.assertEqual([i["id"] for i in out["items"]], ["duplicates", "bridge"])
        self.assertEqual(out["undone"], 1)
        self.assertTrue(out["items"][0]["undoable"])

    def test_refusal_stays_with_its_reason(self):
        result = {"ok": False, "fixes": [{"id": "engine", "status": "refused", "text": {"key": "mackit.undo.changed", "params": {"file": "x"}}}],
                  "applied": [{"id": "engine"}, {"id": "duplicates"}]}
        out = mac_adapt.report_after_undo(self.report(), result)
        self.assertEqual(out["items"][0]["refusal"]["key"], "mackit.undo.changed")
        self.assertEqual(out["undone"], 0)

    def test_undo_all_leaves_only_what_was_never_applied(self):
        result = {"ok": True, "fixes": [{"id": "engine", "status": "restored"}, {"id": "duplicates", "status": "restored"}], "applied": []}
        out = mac_adapt.report_after_undo(self.report(), result)
        self.assertEqual([i["id"] for i in out["items"]], ["bridge"])
        self.assertEqual(out["applied"], [])

    def test_tool_failure_leaves_the_report_untouched(self):
        out = mac_adapt.report_after_undo(self.report(), {"ok": False, "error": {"text": {"key": "mackit.cli.error"}}})
        self.assertEqual(len(out["items"]), 3)
        self.assertEqual(out["undone"], 0)


def tree(root: Path) -> dict:
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob("*")) if p.is_file()}


def bottled_dll(version: str) -> bytes:
    return b"MZ...Bottled..." + "FileVersion".encode("utf-16le") + f"\0\0 {version}.0".encode("utf-16le")


@unittest.skipUnless(HAVE_MACKIT, "mackit absent")
class TestMackit(unittest.TestCase):
    """L'outil sur un faux jeu dans une fausse bouteille (jamais une vraie, jamais wine)."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name).resolve()
        self.bottle = base / "bottles" / "Fake"
        self.game = self.bottle / "drive_c" / "Games" / "Skyrim Special Edition"
        plugins = self.game / "Data" / "SKSE" / "Plugins"
        for path, content in (
            (self.bottle / "cxbottle.conf", '[EnvironmentVariables]\n"CX_GRAPHICS_BACKEND" = "dxvk"\n'),
            (self.bottle / "system.reg", "WINE REGISTRY Version 2\n"), (self.bottle / "user.reg", "WINE REGISTRY Version 2\n"),
            (self.game / "SkyrimSE.exe", "exe"), (plugins / "CommunityShaders.dll", bottled_dll("1.0.25")),
            (plugins / "EVLaS.dll", "evlas"), (plugins / "SSEDisplayTweaks.ini", "[Render]\nSwapEffect = auto\n"),
        ):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content if isinstance(content, bytes) else content.encode())
        state = base / "state" / "bottles.json"
        state.parent.mkdir()
        state.write_text(json.dumps({"roots": [str(self.bottle)], "activeBottle": str(self.bottle), "exclusive": True}))
        self.saved = {k: os.environ.get(k) for k in ("MO2FLATTENER_MAC_STATE", "MO2FLATTENER_MDLSS_BRIDGE", "MACKIT_BIN")}
        os.environ["MO2FLATTENER_MAC_STATE"] = str(state)
        os.environ["MO2FLATTENER_MDLSS_BRIDGE"] = str(base / "none.dll")  # pas de pont : wine n'est jamais lancé
        os.environ.pop("MACKIT_BIN", None)
        self.original = tree(base)
        self.base = base
        self.events = []

    def tearDown(self):
        for key, value in self.saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        self.tmp.cleanup()

    def notify(self, event, payload):
        self.events.append(event)

    def test_bottle_is_found_by_the_game_folder(self):
        bottles = mac_adapt.list_bottles()
        self.assertEqual([b["name"] for b in bottles], ["Fake"])
        self.assertEqual(mac_adapt.detect_bottle(bottles, str(self.game))[1], "detected")

    def test_preview_writes_nothing(self):
        out = mac_adapt.preview(self.game, str(self.bottle))
        self.assertEqual(out["kind"], "plan")
        self.assertEqual({f["id"] for f in out["plan"]["fixes"]}, {"engine", "displayTweaks", "duplicates"})
        self.assertEqual(tree(self.base), self.original)
        self.assertFalse((self.game / "_MAC_BACKUP").exists())

    def test_preview_of_a_game_that_does_not_exist_yet(self):
        out = mac_adapt.preview(self.base / "Later", str(self.bottle))
        self.assertTrue(out["future"])
        self.assertEqual([f["id"] for f in out["plan"]["fixes"]], ["engine"])  # seulement ce qui tient à la bouteille
        self.assertFalse((self.base / "Later").exists())

    def test_finish_then_undo_all_gives_back_the_original(self):
        report = mac_adapt.finish(self.game, str(self.bottle), notify=self.notify)
        self.assertIsNone(report["error"])
        self.assertEqual({i["id"]: i["status"] for i in report["items"]},
                         {"engine": "applied", "displayTweaks": "applied", "duplicates": "applied", "bridge": "skipped"})
        self.assertTrue(all(i["undoable"] for i in report["items"] if i["status"] == "applied"))
        self.assertEqual(report["bottled"]["state"], "outdated")  # 1.0.25 < 1.0.26 : à mettre à jour
        self.assertEqual(self.events[0], "start")
        self.assertLess(self.events.index("fix"), self.events.index("applied"))  # annoncé avant d'être appliqué
        self.assertIn("conf", (self.bottle / "cxbottle.conf").name)
        self.assertIn("dxmt", (self.bottle / "cxbottle.conf").read_text().lower())
        self.assertFalse((self.game / "Data" / "SKSE" / "Plugins" / "EVLaS.dll").exists())
        self.assertNotEqual(tree(self.base), self.original)
        result = mac_adapt.undo(self.game, "all")
        self.assertTrue(result["ok"])
        self.assertEqual(tree(self.base), self.original)
        self.assertFalse((self.game / "_MAC_BACKUP").exists())

    def test_undo_one_fix_removes_it_from_the_report(self):
        report = mac_adapt.finish(self.game, str(self.bottle))
        result = mac_adapt.undo(self.game, "duplicates")
        out = mac_adapt.report_after_undo(report, result)
        self.assertNotIn("duplicates", [i["id"] for i in out["items"]])
        self.assertTrue((self.game / "Data" / "SKSE" / "Plugins" / "EVLaS.dll").exists())
        self.assertEqual({a["id"] for a in mac_adapt.applied(self.game)}, {"engine", "displayTweaks"})

    def test_previous_adaptation_is_undone_before_a_new_assembly(self):
        mac_adapt.finish(self.game, str(self.bottle))
        self.assertEqual(mac_adapt.undo_previous(self.game, self.notify), 3)
        self.assertIn("previous_undone", self.events)
        self.assertEqual(tree(self.base), self.original)
        self.assertEqual(mac_adapt.undo_previous(self.game), 0)  # rien d'appliqué : rien à faire

    def test_finish_never_raises(self):
        report = mac_adapt.finish(self.base / "no" / "such" / "game", str(self.bottle))
        self.assertTrue(report["error"])
        self.assertEqual(report["items"], [])

    def test_no_bottle_applies_only_the_game_fixes(self):
        report = mac_adapt.finish(self.game, None)
        ids = {i["id"]: i["status"] for i in report["items"]}
        self.assertEqual(ids["displayTweaks"], "applied")
        self.assertEqual(ids["engine"], "skipped")
        self.assertEqual(report["items"][-1]["reason"]["key"], "mackit.skip.noBottle")
        self.assertEqual(mac_adapt.undo(self.game, "all")["ok"], True)
        self.assertEqual(tree(self.base), self.original)


class TestWithoutMackit(unittest.TestCase):
    def setUp(self):
        self.saved = os.environ.get("MACKIT_BIN")
        self.saved_frozen = getattr(sys, "frozen", None)
        os.environ["MACKIT_BIN"] = "/nonexistent/mackit"
        self.hide = mac_adapt.mackit_path
        mac_adapt.mackit_path = lambda: None

    def tearDown(self):
        mac_adapt.mackit_path = self.hide
        if self.saved is None:
            os.environ.pop("MACKIT_BIN", None)
        else:
            os.environ["MACKIT_BIN"] = self.saved

    def test_missing_tool_is_reported_not_raised(self):
        self.assertTrue(mac_adapt.run(["bottles"]).get("unavailable"))
        self.assertEqual(mac_adapt.list_bottles(), [])
        self.assertEqual(mac_adapt.preview(Path("/nope"), None), {"kind": "unavailable"})
        with tempfile.TemporaryDirectory() as tmp:
            report = mac_adapt.finish(Path(tmp), None)
            self.assertTrue(report["unavailable"])
            self.assertEqual(report["items"], [])
            self.assertEqual(mac_adapt.undo_previous(Path(tmp)), 0)


if __name__ == "__main__":
    unittest.main()
