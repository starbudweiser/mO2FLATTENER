// État de l'appli : champs de la fenêtre, assemblage en arrière-plan, carte « Adaptation au Mac » et bilan.

import AppKit
import FlattenCore
import Observation
import SwiftUI

enum RunState { case idle, running, macStage }

@MainActor @Observable
final class AppModel {
    // Carte 1
    var mo2Path = "" { didSet { scheduleMac() } }
    var profiles: [String] = []
    var profile = "" { didSet { if oldValue != profile { profileSelected() } } }
    var modlistPath = "" { didSet { scheduleMac() } }
    var destPath = "" { didSet { scheduleMac() } }
    var useHardlinks = false
    var stopOnError = true
    // Carte 2
    var copyPlugins = true
    var pluginsDest = ""
    var copyInis = true
    var inisDest = ""
    // État
    var statusKey = "header_status_idle"
    var statusProfile: String?
    var log = ""
    var progress = 0
    var run: RunState = .idle
    var tick = 0  // change à chaque retraduction
    var logTick = 0
    var scrollToEnd = 0

    // Carte 3 : adaptation au Mac
    var kitSelected = false  // Stock présélectionné, non mémorisé
    var macState: Json = ["kind": "loading"]
    var bottles: [Json] = []
    var bottlesKnown = false
    var bottleHow: String?
    var selectedBottle: String?
    var manualChoice: String?  // nil : automatique
    // Bilan
    var report: Json?
    var undoBusy = false

    @ObservationIgnored private var flattener: Flattener?
    @ObservationIgnored private var macSeq = 0
    @ObservationIgnored private var macTimer: Timer?
    @ObservationIgnored private let dock = DockProgress()
    weak var window: NSWindow?

    var isRunning: Bool { run != .idle }

    // MARK: Textes

    var statusText: String {
        if let p = statusProfile, run == .idle, statusKey == "header_status_idle" { return "Skyrim SE/AE • \(p)" }
        return T(statusKey)
    }

    func retranslate() { tick += 1 }

    func appendLog(_ s: String) {
        log += (log.isEmpty ? "" : "\n") + s
        logTick += 1
    }

    // MARK: Dossiers

    func chooseFolder(_ titleId: String, set: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.title = T(titleId)
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { set(url.path) }
    }

    func browseMO2() {
        chooseFolder("lbl_mo2") { [self] in mo2Path = $0; scanProfiles($0) }
    }

    func browseModlist() {
        let panel = NSOpenPanel()
        panel.title = T("lbl_modl")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText]
        panel.allowsOtherFileTypes = true
        if panel.runModal() == .OK, let url = panel.url { modlistPath = url.path }
    }

    func scanProfiles(_ base: String) {
        var dir = pyJoin(base, "profiles")
        if !isDir(dir) && isDir(pyJoin(pyParent(base), "profiles")) { dir = pyJoin(pyParent(base), "profiles") }
        profiles = []
        profile = ""
        guard isDir(dir) else {
            appendLog("\(T("warn_no_profiles")) \(base)")
            return
        }
        profiles = (scanDir(dir) ?? []).filter(\.isDir).map(\.name)  // ordre du disque, comme iterdir()
        if let first = profiles.first { profile = first; profileSelected(force: true) }
    }

    func profileSelected(force: Bool = false) {
        let mo2 = mo2Path.trimmingCharacters(in: .whitespaces), prof = profile.trimmingCharacters(in: .whitespaces)
        guard !mo2.isEmpty, !prof.isEmpty else { return }
        var target = pyJoin(pyJoin(pyJoin(mo2, "profiles"), prof), "modlist.txt")
        let alt = pyJoin(pyJoin(pyJoin(pyParent(mo2), "profiles"), prof), "modlist.txt")
        if !isFile(target) && isFile(alt) { target = alt }
        if isFile(target) {
            modlistPath = target
            statusProfile = prof
        }
    }

    // MARK: Adaptation au Mac

    func kitAvailable() -> Bool {
        if macState.str("kind") == "unavailable" { return false }
        return !bottles.isEmpty || !bottlesKnown
    }

    func macMode() -> String { kitSelected && kitAvailable() ? "crossover" : "stock" }

    func setKit(_ on: Bool) {
        guard kitSelected != on else { return }
        kitSelected = on
        scheduleMac(now: true)
    }

    func chooseBottle(_ path: String) {
        manualChoice = path
        selectedBottle = path
        bottleHow = "manual"
        scheduleMac(now: true)
    }

    func scheduleMac(now: Bool = false) {
        macTimer?.invalidate()
        macTimer = Timer.scheduledTimer(withTimeInterval: now ? 0.01 : 0.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshMac() }
        }
    }

    /// Annonce de ce que l'adaptation ferait (mackit plan) sur le jeu cible, sans rien écrire.
    func refreshMac() {
        if isRunning { return }
        macSeq += 1
        let kit = macMode() == "crossover"
        if kit && macState.str("kind") != "plan" { macState = ["kind": "loading"] }
        else if !kit { macState = ["kind": "off"] }
        let seq = macSeq
        let dest = destPath.trimmingCharacters(in: .whitespaces), mo2 = mo2Path.trimmingCharacters(in: .whitespaces)
        let modlist = modlistPath.trimmingCharacters(in: .whitespaces), choice = manualChoice
        // les bouteilles sont cherchées même en dossier universel : sans bouteille CrossOver, le kit n'est pas proposé
        Thread.detachNewThread { [weak self] in
            let out = AppModel.planWork(dest: dest, mo2: mo2, modlist: modlist, choice: choice, kit: kit)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.macSeq == seq else { return }  // une analyse plus récente est en route
                    self.applyPlan(out)
                }
            }
        }
    }

    nonisolated static func planWork(dest: String, mo2: String, modlist: String, choice: String?, kit: Bool) -> Json {
        var out: Json = ["bottles": [Json](), "bottle": NSNull(), "how": NSNull(), "state": ["kind": "unavailable"] as Json]
        if MacAdapt.mackitPath() == nil { return out }
        let bottles = MacAdapt.listBottles()
        var (bottle, how) = (nil as Json?, nil as String?)
        if let choice {
            bottle = bottles.first { $0.str("path") == choice }
            how = "manual"
            if bottle == nil { (bottle, how) = MacAdapt.detectBottle(bottles, gameDir: dest.isEmpty ? nil : dest) }
        } else {
            (bottle, how) = MacAdapt.detectBottle(bottles, gameDir: dest.isEmpty ? nil : dest)
        }
        out["bottles"] = bottles
        out["bottle"] = bottle?.str("path") ?? NSNull()
        out["how"] = how ?? NSNull()
        if !kit {
            out["state"] = ["kind": "off"] as Json  // dossier universel : rien à annoncer
        } else if dest.isEmpty {
            out["state"] = ["kind": "nodest"] as Json
        } else {
            var mods: [String] = []
            let mo2ok = !mo2.isEmpty && isDir(mo2)
            if mo2ok && !modlist.isEmpty && isFile(modlist) { mods = (try? parseModlist(modlist)) ?? [] }
            out["state"] = MacAdapt.preview(pyPath(dest), bottle: bottle?.str("path"), mo2Dir: mo2ok ? pyPath(mo2) : nil, mods: mods)
        }
        return out
    }

    private func applyPlan(_ out: Json) {
        bottles = out.arr("bottles")
        bottlesKnown = true
        selectedBottle = out.str("bottle")
        bottleHow = out.str("how")
        if bottles.isEmpty && kitSelected { kitSelected = false }  // plus de bouteille : retour au dossier universel
        macState = out.obj("state") ?? ["kind": "off"]
    }

    // MARK: Assemblage

    private func alert(_ style: NSAlert.Style, _ title: String, _ message: String) {
        // Essais en arrière-plan (MO2FLATTENER_QUIET) : aucune fenêtre modale, le message va au journal
        if ProcessInfo.processInfo.environment["MO2FLATTENER_QUIET"] != nil { appendLog("[\(title)] \(message)"); return }
        let a = NSAlert()
        a.alertStyle = style
        a.messageText = title
        a.informativeText = message
        a.runModal()
    }

    func start() {
        if isRunning { return }
        let mo2 = mo2Path.trimmingCharacters(in: .whitespaces), modlist = modlistPath.trimmingCharacters(in: .whitespaces)
        let dest = destPath.trimmingCharacters(in: .whitespaces)
        let plugins = pluginsDest.trimmingCharacters(in: .whitespaces), inis = inisDest.trimmingCharacters(in: .whitespaces)
        let err = T("err_title")
        if !isDir(pyPath(mo2)) { return alert(.critical, err, T("err_mo2_invalid")) }
        if !isFile(pyPath(modlist)) { return alert(.critical, err, T("err_modlist_invalid")) }
        if pyName(dest).isEmpty { return alert(.critical, err, T("err_dest_empty")) }
        if copyPlugins && pyPath(plugins) == "." { return alert(.critical, err, T("err_plugins_dest")) }
        if copyInis && pyPath(inis) == "." { return alert(.critical, err, T("err_inis_dest")) }

        var o = FlattenOptions(mo2Dir: pyPath(mo2), modlistFile: pyPath(modlist), destGameRoot: pyPath(dest))
        o.useHardlinks = useHardlinks
        o.stopOnError = stopOnError
        o.copyPlugins = copyPlugins
        o.pluginsDest = copyPlugins ? pyPath(plugins) : nil
        o.copyInis = copyInis
        o.inisDest = copyInis ? pyPath(inis) : nil
        o.macMode = macMode()
        o.macBottle = manualChoice

        run = .running
        progress = 0
        statusKey = "header_status_running"
        report = nil  // le bilan d'un précédent assemblage ne dit plus vrai
        let f = Flattener()
        flattener = f
        var ev = FlattenEvents()
        ev.log = { s in DispatchQueue.main.async { MainActor.assumeIsolated { self.appendLog(s) } } }
        ev.progress = { p in DispatchQueue.main.async { MainActor.assumeIsolated { self.progress = p; self.dock.set(p) } } }
        ev.macStage = { DispatchQueue.main.async { MainActor.assumeIsolated { self.run = .macStage; self.statusKey = "header_status_mac" } } }
        ev.macReport = { r in DispatchQueue.main.async { MainActor.assumeIsolated { self.report = r; self.scrollToEnd += 1 } } }
        Thread.detachNewThread { [weak self] in
            let outcome = f.run(o, ev)
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.finished(outcome) } }
        }
    }

    func stop() {
        guard run == .running, let f = flattener else { return }  // les correctifs sont tout ou rien : on ne les interrompt pas
        statusKey = "header_status_stopped"
        appendLog(T("log_interrupt_requested"))
        f.requestStop()
    }

    private func finished(_ outcome: FlattenOutcome) {
        defer { if let t = ProcessInfo.processInfo.environment["MO2FLATTENER_UNDO"], report != nil { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { MainActor.assumeIsolated { self.undo(t) } } } }
        dock.clear()
        run = .idle
        flattener = nil
        scheduleMac(now: true)  // le jeu cible a changé : l'annonce redit vrai
        switch outcome {
        case .finished:
            statusKey = "header_status_done"
            alert(.informational, T("success_title"), T("success_msg"))
        case .stopped:
            statusKey = "header_status_stopped"
            alert(.warning, T("err_title"), T("stop_msg"))
        case .error(let msg):
            statusKey = "header_status_error"
            appendLog(T("log_critical", ["err": msg]))
            alert(.critical, T("err_title"), msg)
        }
    }

    // MARK: Annulation

    func undo(_ target: String) {
        guard let rep = report, !isRunning, !undoBusy, let game = rep.str("game") else { return }
        undoBusy = true
        Thread.detachNewThread { [weak self] in
            let result = MacAdapt.undo(game, target)
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.undone(rep, result) } }
        }
    }

    private func undone(_ rep: Json, _ result: Json) {
        let fixes = result.arr("fixes")
        for fix in fixes {
            let title = T("mackit.fix.\(fix.str("id") ?? "").title")
            appendLog(fix.str("status") == "restored" ? T("log_mac_undone", ["title": title]) : T("log_mac_refused", ["title": title]))
        }
        if fixes.isEmpty { appendLog(T("log_mac_error", ["reason": MacAdapt.text(result.obj("error")?["text"])])) }
        report = MacAdapt.reportAfterUndo(rep, result)
        undoBusy = false
        if let next = ProcessInfo.processInfo.environment["MO2FLATTENER_UNDO2"], report?.arr("items").contains(where: { $0.flag("undoable") }) == true { undo(next) }
        scheduleMac(now: true)  // l'annonce redit vrai : ce qui vient d'être annulé redevient à faire
    }

    /// Fermeture : l'adaptation n'est pas interrompue ; la copie s'arrête proprement.
    func stopForQuit() { flattener?.requestStop() }
}
