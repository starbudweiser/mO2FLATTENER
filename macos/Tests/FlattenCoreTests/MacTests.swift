// Adaptation au Mac : textes ×4, Bottled Shaders, bouteille, bilan, outil `mackit` sur un faux jeu et une fausse bouteille
// (jamais une vraie), assemblage indépendant de l'outil (port de tests/test_mac.py et test_mac_gui.py).
import XCTest
@testable import FlattenCore

let hasMackit = MacAdapt.mackitPath() != nil

class TmpCase: XCTestCase {
    var base = ""
    override func setUp() {
        let t = realPath(NSTemporaryDirectory())
        base = t + "/mo2f_" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        I18n.setLang("fr")
    }
    override func tearDown() { try? FileManager.default.removeItem(atPath: base) }
    @discardableResult func put(_ path: String, _ content: String = "x") -> String {
        try? FileManager.default.createDirectory(atPath: pyParent(path), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: content.data(using: .utf8))
        return path
    }
    func read(_ p: String) -> String { (try? String(contentsOfFile: p, encoding: .utf8)) ?? "" }
    /// noms relatifs -> SHA-256 (empreinte rapide : taille + contenu hexadécimal)
    func tree(_ root: String) -> [String: Data] {
        var out: [String: Data] = [:]
        walkTree(root) { r, rel, _, files in
            for f in files { out[(rel + [f]).joined(separator: "/")] = FileManager.default.contents(atPath: r + "/" + f) }
            return true
        }
        return out
    }
}

final class TextTests: XCTestCase {
    func placeholders(_ s: String) -> [String] {
        let re = try! NSRegularExpression(pattern: #"\{(\w+)\}"#)
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }.sorted()
    }

    func testEveryTextHasFourLanguagesWithSamePlaceholders() {
        for (fr, tr) in translations {
            XCTAssertEqual(tr.count, 3, fr)
            for (i, t) in tr.enumerated() {
                XCTAssertFalse(t.trimmingCharacters(in: .whitespaces).isEmpty, "\(fr) [\(i)]")
                XCTAssertEqual(placeholders(t), placeholders(fr), "\(fr) → \(t)")
            }
        }
    }

    func testEveryIdPointsToATranslatedText() {
        for (id, fr) in textIds { XCTAssertNotNil(translations[fr], id) }
        for lang in ["fr", "en", "it", "es"] {
            I18n.setLang(lang)
            for id in textIds.keys { XCTAssertNotEqual(T(id), id, "\(lang) \(id)") }
        }
        I18n.setLang("fr")
    }

    func testEnglishDiffersFromFrenchForInterfaceTexts() {
        I18n.setLang("en")
        XCTAssertEqual(T("btn_browse"), "Browse")
        XCTAssertEqual(T("log_analyzing", ["name": "m.txt"]), "[*] Analyzing priority order: m.txt")
        I18n.setLang("fr")
    }

    func testLanguageChoice() {
        XCTAssertEqual(LangChoice.resolve("auto", preferred: ["it-IT"]), "it")
        XCTAssertEqual(LangChoice.resolve("auto", preferred: ["de-DE"]), "en")  // langue inconnue : anglais
        XCTAssertEqual(LangChoice.resolve("es", preferred: ["fr"]), "es")
        XCTAssertEqual(LangChoice.normalize("xx"), "auto")
    }

    func testEveryKeyMackitCanReturnIsTranslated() throws {
        try XCTSkipUnless(hasMackit, "mackit absent")
        let keys = (MacAdapt.run(["texts"])["keys"] as? [String]) ?? []
        XCTAssertGreaterThan(keys.count, 30)
        for k in keys { XCTAssertNotNil(textIds[k], k) }
    }
}

final class BottledTests: TmpCase {
    var mo2 = "", oldHome: String?
    override func setUp() {
        super.setUp()
        mo2 = base + "/inst"
        try? FileManager.default.createDirectory(atPath: mo2, withIntermediateDirectories: true)
        oldHome = ProcessInfo.processInfo.environment["HOME"]
        setenv("HOME", base + "/home", 1)
        try? FileManager.default.createDirectory(atPath: base + "/home/Downloads", withIntermediateDirectories: true)
    }
    override func tearDown() { if let h = oldHome { setenv("HOME", h, 1) }; super.tearDown() }

    func testVersions() {
        XCTAssertTrue(MacAdapt.versionAtLeast("1.0.26", "1.0.26")); XCTAssertTrue(MacAdapt.versionAtLeast("1.0.27", "1.0.26"))
        XCTAssertTrue(MacAdapt.versionAtLeast("1.1", "1.0.26")); XCTAssertTrue(MacAdapt.versionAtLeast("2.0.0", "1.0.26"))
        XCTAssertFalse(MacAdapt.versionAtLeast("1.0.25", "1.0.26")); XCTAssertFalse(MacAdapt.versionAtLeast("", "1.0.26"))
    }

    func testArchiveVersionFromNames() {
        let v = MacAdapt.archiveVersion
        XCTAssertEqual(v("Bottled Shaders-192816-1-0-26-1762131614.7z"), "1.0.26")
        XCTAssertEqual(v("Bottled Shaders 192816 1.0.26 2026-11-03T00-59Z VMSnJCbr4.7z"), "1.0.26")
        XCTAssertEqual(v("Bottled Shaders 1.0.27.zip"), "1.0.27")
        XCTAssertNil(v("Bottled Shaders.7z"))
    }

    func testArchiveVersionFromMetaFile() {
        let a = put(mo2 + "/downloads/BS.7z")
        put(mo2 + "/downloads/BS.7z.meta", "[General]\nmodID=192816\nversion=1.0.28\n")
        XCTAssertEqual(MacAdapt.archiveVersion(a), "1.0.28")
        put(mo2 + "/downloads/BS.7z.meta", "[General]\nmodID=1234\nversion=1.0.28\n")
        XCTAssertNil(MacAdapt.archiveVersion(a))
    }

    func testFindsNewestArchiveInMo2DownloadsFirst() {
        put(mo2 + "/ModOrganizer.ini", "[Settings]\ndownload_directory=%BASE_DIR%/dl\n")
        for n in ["Bottled Shaders-192816-1-0-25-1.7z", "Bottled Shaders-192816-1-0-26-2.7z", "Bottled Shaders-192816-1-0-27-3.7z",
                  "Other Mod-1-0-99.7z", "Bottled Shaders-192816-1-0-30-4.7z.part"] { put(mo2 + "/dl/" + n) }
        let f = MacAdapt.findBottledArchive(mo2)!
        XCTAssertEqual(f.str("version"), "1.0.27"); XCTAssertEqual(f.str("source"), "mo2"); XCTAssertEqual(pyParent(f.str("path")!), mo2 + "/dl")
    }

    func testNothingBelowTheMinimum() {
        put(mo2 + "/downloads/Bottled Shaders-192816-1-0-25-1.7z")
        XCTAssertNil(MacAdapt.findBottledArchive(mo2))
        XCTAssertEqual(MacAdapt.findBottledArchive(mo2, minimum: "1.0.25")?.str("version"), "1.0.25")
    }

    func testFallsBackToMabbajackFolders() {
        let p = put(base + "/DOWNLOADS/Bottled Shaders 192816 1.0.26 2026-11-03T00-59Z abc.7z")
        XCTAssertEqual(MacAdapt.findBottledArchive(mo2)?.str("source"), "mabbajack")
        try? FileManager.default.removeItem(atPath: p)
        XCTAssertNil(MacAdapt.findBottledArchive(mo2))
        put(base + "/home/Downloads/Bottled Shaders-192816-1-0-26-9.zip")
        XCTAssertEqual(MacAdapt.findBottledArchive(mo2)?.str("source"), "mabbajack")
    }

    func testMo2FolderWinsOverMabbajack() {
        put(mo2 + "/downloads/Bottled Shaders-192816-1-0-26-1.7z"); put(base + "/DOWNLOADS/Bottled Shaders-192816-1-0-26-2.7z")
        XCTAssertEqual(MacAdapt.findBottledArchive(mo2)?.str("source"), "mo2")
    }

    func testMo2Paths() {
        XCTAssertEqual(MacAdapt.mo2Path("%BASE_DIR%/downloads", base: "/x/inst"), "/x/inst/downloads")
        XCTAssertEqual(MacAdapt.mo2Path("Z:\\Volumes\\Big\\dl", base: "/x/inst"), "/Volumes/Big/dl")
        XCTAssertNil(MacAdapt.mo2Path("C:/Users/me/dl", base: "/x/inst"))
    }

    func testInstalledVersionFromModMetadata() {
        put(mo2 + "/mods/Bottled/meta.ini", "[General]\nmodid=192816\nversion=1.0.26\n")
        put(mo2 + "/mods/Other/meta.ini", "[General]\nmodid=5\nversion=9.9.9\n")
        XCTAssertEqual(MacAdapt.installedBottledVersion(mo2, mods: ["Other", "Bottled", "Missing"]), "1.0.26")
        XCTAssertNil(MacAdapt.installedBottledVersion(mo2, mods: ["Other"]))
    }

    func testBottledInfoOnlyLooksForAnArchiveWhenNeeded() {
        put(mo2 + "/downloads/Bottled Shaders-192816-1-0-26-1.7z")
        XCTAssertTrue(MacAdapt.bottledInfo(["state": "ok", "minimum": "1.0.26"], mo2Dir: mo2)["archive"] is NSNull)
        let stale = MacAdapt.bottledInfo(["state": "outdated", "minimum": "1.0.26"], mo2Dir: mo2)
        XCTAssertEqual(stale.obj("archive")?.str("version"), "1.0.26")
        XCTAssertEqual(stale.str("page"), "https://www.nexusmods.com/skyrimspecialedition/mods/192816")
        XCTAssertTrue(MacAdapt.bottledInfo(["state": "stock", "minimum": "1.0.99"], mo2Dir: mo2)["archive"] is NSNull)
    }
}

final class BottleTests: XCTestCase {
    let bottles: [Json] = [["path": "/b/One", "name": "One", "kind": "wine"], ["path": "/b/Two", "name": "Two", "kind": "crossover"],
                           ["path": "/b/Three", "name": "Three", "kind": "crossover"]]
    func testDetectedWhenTheGameIsInside() {
        let (b, how) = MacAdapt.detectBottle(bottles, gameDir: "/b/Three/drive_c/Games/Skyrim")
        XCTAssertEqual(b?.str("name"), "Three"); XCTAssertEqual(how, "detected")
    }
    func testFirstCrossoverBottleOtherwise() {
        let (b, how) = MacAdapt.detectBottle(bottles, gameDir: "/Volumes/Games/Skyrim")
        XCTAssertEqual(b?.str("name"), "Two"); XCTAssertEqual(how, "first")
        XCTAssertEqual(MacAdapt.detectBottle(bottles, gameDir: nil).how, "first")
    }
    func testNoBottle() {
        XCTAssertNil(MacAdapt.detectBottle([], gameDir: "/x").bottle)
        XCTAssertNil(MacAdapt.detectBottle([bottles[0]], gameDir: "/x").bottle)
    }
    func testSiblingFolderIsNotInside() { XCTAssertEqual(MacAdapt.detectBottle(bottles, gameDir: "/b/TwoExtra/x").how, "first") }
}

final class ReportTests: XCTestCase {
    func report() -> Json {
        ["game": "/g", "undone": 0, "applied": [["id": "engine"], ["id": "duplicates"]], "items": [
            ["id": "engine", "status": "applied", "undoable": true, "title": ["key": "mackit.fix.engine.title"], "files": []],
            ["id": "duplicates", "status": "applied", "undoable": true, "title": ["key": "mackit.fix.duplicates.title"], "files": []],
            ["id": "bridge", "status": "skipped", "undoable": false, "title": ["key": "mackit.fix.bridge.title"], "files": []]]]
    }
    func ids(_ r: Json) -> [String] { r.arr("items").compactMap { $0.str("id") } }

    func testUndoneFixDisappears() {
        let r: Json = ["ok": true, "fixes": [["id": "engine", "status": "restored"]], "applied": [["id": "duplicates"]]]
        let out = MacAdapt.reportAfterUndo(report(), r)
        XCTAssertEqual(ids(out), ["duplicates", "bridge"]); XCTAssertEqual(out.int("undone"), 1)
        XCTAssertTrue(out.arr("items")[0].flag("undoable"))
    }
    func testRefusalStaysWithItsReason() {
        let r: Json = ["ok": false, "fixes": [["id": "engine", "status": "refused", "text": ["key": "mackit.undo.changed", "params": ["file": "x"]]]],
                       "applied": [["id": "engine"], ["id": "duplicates"]]]
        let out = MacAdapt.reportAfterUndo(report(), r)
        XCTAssertEqual(out.arr("items")[0].obj("refusal")?.str("key"), "mackit.undo.changed"); XCTAssertEqual(out.int("undone"), 0)
    }
    func testUndoAllLeavesOnlyWhatWasNeverApplied() {
        let r: Json = ["ok": true, "fixes": [["id": "engine", "status": "restored"], ["id": "duplicates", "status": "restored"]], "applied": [Json]()]
        let out = MacAdapt.reportAfterUndo(report(), r)
        XCTAssertEqual(ids(out), ["bridge"]); XCTAssertEqual(out.arr("applied").count, 0)
    }
    func testToolFailureLeavesTheReportUntouched() {
        let out = MacAdapt.reportAfterUndo(report(), ["ok": false, "error": ["text": ["key": "mackit.cli.error"]]])
        XCTAssertEqual(out.arr("items").count, 3); XCTAssertEqual(out.int("undone"), 0)
    }
}

/// L'outil sur un faux jeu dans une fausse bouteille (jamais une vraie, jamais wine).
final class MackitTests: TmpCase {
    var bottle = "", game = ""
    var events: [String] = []
    var saved: [String: String?] = [:]

    override func setUpWithError() throws {
        try XCTSkipUnless(hasMackit, "mackit absent")
    }
    override func setUp() {
        super.setUp()
        guard hasMackit else { return }
        bottle = base + "/bottles/Fake"; game = bottle + "/drive_c/Games/Skyrim Special Edition"
        let plugins = game + "/Data/SKSE/Plugins"
        put(bottle + "/cxbottle.conf", "[EnvironmentVariables]\n\"CX_GRAPHICS_BACKEND\" = \"dxvk\"\n")
        put(bottle + "/system.reg", "WINE REGISTRY Version 2\n"); put(bottle + "/user.reg", "WINE REGISTRY Version 2\n")
        put(game + "/SkyrimSE.exe", "exe"); put(plugins + "/EVLaS.dll", "evlas"); put(plugins + "/SSEDisplayTweaks.ini", "[Render]\nSwapEffect = auto\n")
        let dll = Data("MZ...Bottled...".utf8) + "FileVersion".data(using: .utf16LittleEndian)! + "\0\0 1.0.25.0".data(using: .utf16LittleEndian)!
        try? FileManager.default.createDirectory(atPath: plugins, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: plugins + "/CommunityShaders.dll", contents: dll)
        let state = base + "/state/bottles.json"
        put(state, "{\"roots\": [\"\(bottle)\"], \"activeBottle\": \"\(bottle)\", \"exclusive\": true}")
        for (k, v) in [("MO2FLATTENER_MAC_STATE", state), ("MO2FLATTENER_MDLSS_BRIDGE", base + "/none.dll")] {
            saved[k] = ProcessInfo.processInfo.environment[k]; setenv(k, v, 1)
        }
        unsetenv("MACKIT_BIN")
        original = tree(base)
    }
    var original: [String: Data] = [:]
    override func tearDown() {
        for (k, v) in saved { if let v { setenv(k, v, 1) } else { unsetenv(k) } }
        MacAdapt.mackitOverride = nil
        super.tearDown()
    }
    func notify(_ e: String, _: Json) { events.append(e) }

    func testBottleIsFoundByTheGameFolder() {
        let b = MacAdapt.listBottles()
        XCTAssertEqual(b.compactMap { $0.str("name") }, ["Fake"])
        XCTAssertEqual(MacAdapt.detectBottle(b, gameDir: game).how, "detected")
    }

    func testPreviewWritesNothing() {
        let out = MacAdapt.preview(game, bottle: bottle)
        XCTAssertEqual(out.str("kind"), "plan")
        XCTAssertEqual(Set(out.obj("plan")!.arr("fixes").compactMap { $0.str("id") }), ["engine", "displayTweaks", "duplicates"])
        XCTAssertEqual((out.obj("plan")!["ok"] as? [String]) ?? ["?"], [])
        XCTAssertEqual(tree(base), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: game + "/_MAC_BACKUP"))
    }

    func testPreviewOfAGameThatDoesNotExistYet() {
        let out = MacAdapt.preview(base + "/Later", bottle: bottle)
        XCTAssertTrue(out.flag("future"))
        XCTAssertEqual(out.obj("plan")!.arr("fixes").compactMap { $0.str("id") }, ["engine"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: base + "/Later"))
    }

    func testFinishThenUndoAllGivesBackTheOriginal() {
        let report = MacAdapt.finish(game, bottle: bottle, notify: notify)
        XCTAssertTrue(report["error"] is NSNull)
        var st: [String: String] = [:]
        for i in report.arr("items") { st[i.str("id")!] = i.str("status") }
        XCTAssertEqual(st, ["engine": "applied", "displayTweaks": "applied", "duplicates": "applied", "bridge": "skipped"])
        XCTAssertTrue(report.arr("items").filter { $0.str("status") == "applied" }.allSatisfy { $0.flag("undoable") })
        XCTAssertEqual(report.obj("bottled")?.str("state"), "outdated")
        XCTAssertEqual(events.first, "start")
        XCTAssertLessThan(events.firstIndex(of: "fix")!, events.firstIndex(of: "applied")!)
        XCTAssertTrue(read(bottle + "/cxbottle.conf").lowercased().contains("dxmt"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: game + "/Data/SKSE/Plugins/EVLaS.dll"))
        XCTAssertNotEqual(tree(base), original)
        XCTAssertTrue(MacAdapt.undo(game, "all").flag("ok"))
        XCTAssertEqual(tree(base), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: game + "/_MAC_BACKUP"))
    }

    func testUndoOneFixRemovesItFromTheReport() {
        let report = MacAdapt.finish(game, bottle: bottle)
        let out = MacAdapt.reportAfterUndo(report, MacAdapt.undo(game, "duplicates"))
        XCTAssertFalse(out.arr("items").contains { $0.str("id") == "duplicates" })
        XCTAssertTrue(FileManager.default.fileExists(atPath: game + "/Data/SKSE/Plugins/EVLaS.dll"))
        XCTAssertEqual(Set(MacAdapt.applied(game).compactMap { $0.str("id") }), ["engine", "displayTweaks"])
    }

    func testAGameAdaptedByAnotherToolListsWhatIsAlreadyInOrder() {
        _ = MacAdapt.finish(game, bottle: bottle)
        try? FileManager.default.removeItem(atPath: game + "/_MAC_BACKUP")
        let out = MacAdapt.preview(game, bottle: bottle)
        XCTAssertEqual(out.int("previous"), 0)
        XCTAssertEqual(out.obj("plan")!.arr("fixes").count, 0)
        XCTAssertEqual(out.obj("plan")!["ok"] as? [String], ["engine", "displayTweaks", "duplicates"])
    }

    func testAnAdaptedGameIsAnnouncedAsRedone() {
        _ = MacAdapt.finish(game, bottle: bottle)
        let out = MacAdapt.preview(game, bottle: bottle)
        XCTAssertEqual(out.int("previous"), 3)
        XCTAssertEqual(out.obj("plan")!["ok"] as? [String], [])
    }

    func testPreviousAdaptationIsUndoneBeforeANewAssembly() {
        _ = MacAdapt.finish(game, bottle: bottle)
        XCTAssertEqual(MacAdapt.undoPrevious(game, notify: notify), 3)
        XCTAssertTrue(events.contains("previous_undone"))
        XCTAssertEqual(tree(base), original)
        XCTAssertEqual(MacAdapt.undoPrevious(game), 0)
    }

    func testFinishNeverRaises() {
        let r = MacAdapt.finish(base + "/no/such/game", bottle: bottle)
        XCTAssertTrue(r["error"] is Json); XCTAssertEqual(r.arr("items").count, 0)
    }

    func testKitWithoutABottleTouchesNothing() {
        var ev: [String] = []
        let r = MacAdapt.finish(game, bottle: nil) { e, _ in ev.append(e) }
        XCTAssertTrue(r.flag("no_bottle")); XCTAssertEqual(r.str("mode"), "crossover"); XCTAssertEqual(r.arr("items").count, 0)
        XCTAssertEqual(ev, ["no_bottle"]); XCTAssertEqual(tree(base), original)
        XCTAssertEqual(MacAdapt.preview(game, bottle: nil).str("kind"), "nobottle")
    }

    func testStockFolderTouchesNothingAndDoesNotStartTheTool() {
        MacAdapt.mackitOverride = .some(nil)
        var ev: [String] = []
        let r = MacAdapt.finishStock(game) { e, _ in ev.append(e) }
        XCTAssertEqual(r.str("mode"), "stock"); XCTAssertEqual(r.arr("items").count, 0); XCTAssertFalse(r.flag("unavailable"))
        XCTAssertEqual(ev, ["stock"]); XCTAssertEqual(tree(base), original)
    }

    // --- assemblage complet avec l'adaptation (test_mac_gui.py)
    func assemble(mode: String?, bottle: String? = nil, destRoot: String? = nil) -> (FlattenOutcome, [Json], [String], Int) {
        let mo2 = base + "/inst"
        put(mo2 + "/profiles/Default/modlist.txt", "+Mod\n")
        put(mo2 + "/mods/Mod/SKSE/Plugins/SSEDisplayTweaks.ini", "[Render]\nSwapEffect = auto\n")
        var o = FlattenOptions(mo2Dir: mo2, modlistFile: mo2 + "/profiles/Default/modlist.txt", destGameRoot: destRoot ?? base + "/Game")
        o.macMode = mode; o.macBottle = bottle
        var reports: [Json] = [], log: [String] = [], stages = 0
        var ev = FlattenEvents(); ev.macReport = { reports.append($0) }; ev.log = { log.append($0) }; ev.macStage = { stages += 1 }
        return (Flattener().run(o, ev), reports, log, stages)
    }

    func testToolMissingDoesNotFailTheAssembly() {
        MacAdapt.mackitOverride = .some(nil)
        let (out, reports, _, _) = assemble(mode: "crossover", bottle: "/une/bouteille")
        guard case .finished = out else { return XCTFail() }
        XCTAssertTrue(FileManager.default.fileExists(atPath: base + "/Game/Data/SKSE/Plugins/SSEDisplayTweaks.ini"))
        XCTAssertTrue(reports[0].flag("unavailable")); XCTAssertEqual(reports[0].arr("items").count, 0)
    }

    func testDisabledDoesNothingAndHasNoStage() {
        let (out, reports, _, stages) = assemble(mode: nil)
        guard case .finished = out else { return XCTFail() }
        XCTAssertEqual(reports.count, 0); XCTAssertEqual(stages, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: base + "/Game/_MAC_BACKUP"))
    }

    func testStockFolderIsDeliveredUntouchedWithASimpleReport() {
        let (out, reports, log, stages) = assemble(mode: "stock")
        guard case .finished = out else { return XCTFail() }
        XCTAssertEqual(stages, 0); XCTAssertEqual(reports.map { $0.str("mode") }, ["stock"])
        XCTAssertFalse(read(base + "/Game/Data/SKSE/Plugins/SSEDisplayTweaks.ini").contains("flip_discard"))
        XCTAssertTrue(log.contains { $0.contains("Dossier universel") })
    }

    func testBottleHoldingTheGameIsDetectedWhenTheAssemblyEnds() {
        let dest = bottle + "/drive_c/Games/Skyrim"
        let (out, reports, log, _) = assemble(mode: "crossover", destRoot: dest)
        guard case .finished = out else { return XCTFail("\(out)") }
        var st: [String: String] = [:]
        for i in reports[0].arr("items") { st[i.str("id")!] = i.str("status") }
        XCTAssertEqual(st["engine"], "applied"); XCTAssertEqual(st["displayTweaks"], "applied")
        XCTAssertTrue(read(bottle + "/cxbottle.conf").lowercased().contains("dxmt"))
        XCTAssertTrue(read(dest + "/Data/SKSE/Plugins/SSEDisplayTweaks.ini").contains("flip_discard"))
        let text = log.joined(separator: "\n")
        XCTAssertLessThan(text.range(of: "À appliquer")!.lowerBound, text.range(of: "appliqué")!.lowerBound)
        // un nouvel assemblage annule d'abord l'adaptation précédente, puis la refait
        let (_, reports2, log2, _) = assemble(mode: "crossover", destRoot: dest)
        XCTAssertTrue(log2.contains { $0.contains("précédente annulée") })
        XCTAssertEqual(reports2[0].arr("items").first { $0.str("id") == "displayTweaks" }?.str("status"), "applied")
        XCTAssertEqual(read(dest + "/Data/SKSE/Plugins/SSEDisplayTweaks.ini").components(separatedBy: "SwapEffect").count - 1, 1)
        // le kit demande une bouteille : sans elle, plus de demi-mesure
        _ = MacAdapt.undo(dest, "all")
        XCTAssertTrue(read(bottle + "/cxbottle.conf").lowercased().contains("dxvk"))
        let (_, reports3, _, _) = assemble(mode: "crossover", bottle: "", destRoot: dest)
        XCTAssertTrue(reports3[0].flag("no_bottle")); XCTAssertTrue(read(bottle + "/cxbottle.conf").lowercased().contains("dxvk"))
    }
}

final class WithoutMackitTests: TmpCase {
    override func tearDown() { MacAdapt.mackitOverride = nil; super.tearDown() }
    func testMissingToolIsReportedNotRaised() {
        MacAdapt.mackitOverride = .some(nil)
        XCTAssertTrue(MacAdapt.run(["bottles"]).flag("unavailable"))
        XCTAssertEqual(MacAdapt.listBottles().count, 0)
        XCTAssertEqual(MacAdapt.preview("/nope", bottle: "/une/bouteille").str("kind"), "unavailable")
        let r = MacAdapt.finish(base, bottle: "/une/bouteille")
        XCTAssertTrue(r.flag("unavailable")); XCTAssertEqual(r.arr("items").count, 0)
        XCTAssertEqual(MacAdapt.undoPrevious(base), 0)
    }
}
