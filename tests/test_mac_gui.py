"""L'assemblage ne dépend jamais de l'adaptation au Mac : le thread d'assemblage est joué tel quel (sans fenêtre,
QT_QPA_PLATFORM=offscreen), avec l'outil absent, en panne ou qui lève une exception."""
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

try:
    from PyQt6.QtWidgets import QApplication
except ImportError:  # pragma: no cover
    QApplication = None

import mac_adapt  # noqa: E402


@unittest.skipIf(QApplication is None, "PyQt6 absent")
class TestAssemblyWithMac(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QApplication.instance() or QApplication([])
        import mo2_flattener_gui as gui
        cls.gui = gui

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name).resolve()
        self.mo2 = base / "inst"
        (self.mo2 / "profiles" / "Default").mkdir(parents=True)
        (self.mo2 / "profiles" / "Default" / "modlist.txt").write_text("+Mod\n")
        (self.mo2 / "mods" / "Mod" / "SKSE" / "Plugins").mkdir(parents=True)
        (self.mo2 / "mods" / "Mod" / "SKSE" / "Plugins" / "SSEDisplayTweaks.ini").write_text("[Render]\nSwapEffect = auto\n")
        self.dest = base / "Game"
        state = base / "state.json"
        # aucune bouteille visible : jamais une vraie bouteille de ce Mac (exclusive + une bouteille active qui n'existe pas)
        state.write_text(json.dumps({"roots": [], "activeBottle": str(base / "aucune"), "exclusive": True}))
        self.saved = {k: os.environ.get(k) for k in ("MO2FLATTENER_MAC_STATE", "MO2FLATTENER_MDLSS_BRIDGE")}
        os.environ["MO2FLATTENER_MAC_STATE"] = str(state)
        os.environ["MO2FLATTENER_MDLSS_BRIDGE"] = str(base / "none.dll")
        self.hide = mac_adapt.mackit_path

    def tearDown(self):
        mac_adapt.mackit_path = self.hide
        for key, value in self.saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        self.tmp.cleanup()

    def assemble(self, mac_enabled=True, mac_bottle=None, mac_mode=None):
        i18n = self.gui.I18nManager()
        i18n._current_lang = "fr"  # les essais lisent le journal en français, quelle que soit la langue du Mac
        worker = self.gui.FastFlattenerWorker(
            mo2_dir=self.mo2, modlist_file=self.mo2 / "profiles" / "Default" / "modlist.txt", dest_game_root=self.dest,
            use_hardlinks=False, stop_on_error=True, copy_plugins=False, plugins_dest=None, copy_inis=False,
            inis_dest=None, i18n=i18n, mac_enabled=mac_enabled, mac_bottle=mac_bottle, mac_mode=mac_mode)
        seen = {"finished": 0, "errors": [], "reports": [], "stage": 0, "log": []}
        worker.finished_ok.connect(lambda: seen.__setitem__("finished", seen["finished"] + 1))
        worker.error_raised.connect(seen["errors"].append)
        worker.mac_report.connect(seen["reports"].append)
        worker.mac_stage.connect(lambda: seen.__setitem__("stage", seen["stage"] + 1))
        worker.log_msg.connect(seen["log"].append)
        worker.run()
        return seen

    def test_tool_missing_does_not_fail_the_assembly(self):
        mac_adapt.mackit_path = lambda: None
        seen = self.assemble(mac_bottle="/une/bouteille")
        self.assertEqual((seen["finished"], seen["errors"]), (1, []))
        self.assertTrue((self.dest / "Data" / "SKSE" / "Plugins" / "SSEDisplayTweaks.ini").is_file())
        self.assertTrue(seen["reports"][0]["unavailable"])
        self.assertEqual(seen["reports"][0]["items"], [])

    def test_engine_exception_does_not_fail_the_assembly(self):
        def boom(*args, **kwargs):
            raise RuntimeError("engine crashed")
        original = mac_adapt.finish
        mac_adapt.finish = boom
        try:
            seen = self.assemble()
        finally:
            mac_adapt.finish = original
        self.assertEqual((seen["finished"], seen["errors"]), (1, []))
        self.assertTrue(seen["reports"][0]["error"])
        self.assertTrue(any("[AVERTISSEMENT]" in line or "[WARNING]" in line for line in seen["log"]))

    def test_disabled_does_nothing_and_has_no_stage(self):
        seen = self.assemble(mac_enabled=False)
        self.assertEqual((seen["finished"], seen["reports"], seen["stage"]), (1, [], 0))
        self.assertFalse((self.dest / "_MAC_BACKUP").exists())

    def test_stock_folder_is_delivered_untouched_with_a_simple_report(self):
        seen = self.assemble(mac_mode="stock")
        self.assertEqual((seen["finished"], seen["errors"], seen["stage"]), (1, [], 0))  # pas d'étape Mac, rien à interrompre
        self.assertEqual([(r["mode"], r["items"]) for r in seen["reports"]], [("stock", [])])
        ini = (self.dest / "Data" / "SKSE" / "Plugins" / "SSEDisplayTweaks.ini").read_text()
        self.assertNotIn("flip_discard", ini)
        self.assertFalse((self.dest / "_MAC_BACKUP").exists())
        self.assertTrue(any("Dossier universel" in line for line in seen["log"]))

    @unittest.skipIf(mac_adapt.mackit_path() is None, "mackit absent")
    def test_kit_without_a_bottle_touches_nothing(self):
        seen = self.assemble(mac_mode="crossover")  # aucune bouteille visible : le kit ne fait rien
        report = seen["reports"][0]
        self.assertEqual((seen["finished"], seen["errors"]), (1, []))
        self.assertTrue(report["no_bottle"])
        self.assertEqual(report["items"], [])
        ini = (self.dest / "Data" / "SKSE" / "Plugins" / "SSEDisplayTweaks.ini").read_text()
        self.assertNotIn("flip_discard", ini)
        self.assertFalse((self.dest / "_MAC_BACKUP").exists())
        self.assertTrue(any("aucune bouteille CrossOver" in line for line in seen["log"]))

    @unittest.skipIf(mac_adapt.mackit_path() is None, "mackit absent")
    def test_bottle_holding_the_game_is_detected_when_the_assembly_ends(self):
        bottle = Path(self.tmp.name).resolve() / "bottles" / "Fake"
        for name, content in (("cxbottle.conf", '[EnvironmentVariables]\n"CX_GRAPHICS_BACKEND" = "dxvk"\n'),
                              ("system.reg", "WINE REGISTRY Version 2\n"), ("user.reg", "WINE REGISTRY Version 2\n")):
            (bottle / name).parent.mkdir(parents=True, exist_ok=True)
            (bottle / name).write_text(content)
        Path(os.environ["MO2FLATTENER_MAC_STATE"]).write_text(json.dumps({"roots": [str(bottle)], "activeBottle": str(bottle), "exclusive": True}))
        self.dest = bottle / "drive_c" / "Games" / "Skyrim"  # n'existe pas encore : la bouteille se déduit de son chemin
        seen = self.assemble(mac_bottle=None)
        self.assertEqual(seen["errors"], [])
        statuses = {i["id"]: i["status"] for i in seen["reports"][0]["items"]}
        self.assertEqual(statuses.get("engine"), "applied")
        self.assertEqual(statuses.get("displayTweaks"), "applied")
        self.assertIn("dxmt", (bottle / "cxbottle.conf").read_text().lower())
        ini = (self.dest / "Data" / "SKSE" / "Plugins" / "SSEDisplayTweaks.ini").read_text()
        self.assertIn("flip_discard", ini)
        log = "\n".join(seen["log"])
        self.assertLess(log.index("À appliquer"), log.index("appliqué"))
        # un nouvel assemblage annule d'abord l'adaptation précédente, puis la refait
        seen2 = self.assemble(mac_bottle=None)
        self.assertTrue(any("précédente annulée" in line for line in seen2["log"]))
        self.assertEqual({i["id"]: i["status"] for i in seen2["reports"][0]["items"]}.get("displayTweaks"), "applied")
        self.assertEqual((self.dest / "Data" / "SKSE" / "Plugins" / "SSEDisplayTweaks.ini").read_text().count("SwapEffect"), 1)
        # le kit demande une bouteille : sans elle, plus de demi-mesure, et le moteur graphique n'est pas touché
        mac_adapt.undo(self.dest, "all")
        self.assertIn("dxvk", (bottle / "cxbottle.conf").read_text().lower())
        seen = self.assemble(mac_bottle="")
        self.assertTrue(seen["reports"][0]["no_bottle"])
        self.assertEqual(seen["reports"][0]["items"], [])
        self.assertIn("dxvk", (bottle / "cxbottle.conf").read_text().lower())


if __name__ == "__main__":
    unittest.main()
