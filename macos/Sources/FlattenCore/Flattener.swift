// L'assemblage complet (ancien FastFlattenerWorker de la version Python) : tâches, copie parallèle, plugins.txt et INI,
// adaptation au Mac. Sans interface : les événements passent par des fonctions, l'interface les ramène sur son fil.

import Foundation

public struct FlattenOptions: Sendable {
    public var mo2Dir: String
    public var modlistFile: String
    public var destGameRoot: String
    public var useHardlinks = false
    public var stopOnError = true
    public var copyPlugins = false
    public var pluginsDest: String?
    public var copyInis = false
    public var inisDest: String?
    /// "stock" (dossier universel), "crossover" (kit DXMT) ; nil : pas d'adaptation
    public var macMode: String?
    /// nil : la bouteille qui contient le jeu, sinon la première CrossOver
    public var macBottle: String?

    public init(mo2Dir: String, modlistFile: String, destGameRoot: String) {
        self.mo2Dir = mo2Dir; self.modlistFile = modlistFile; self.destGameRoot = destGameRoot
    }
}

public enum FlattenOutcome: Sendable {
    case finished(copied: Int)
    case stopped
    case error(String)
}

public struct FlattenEvents: @unchecked Sendable {
    public var log: (String) -> Void = { _ in }
    public var progress: (Int) -> Void = { _ in }
    public var macStage: () -> Void = {}
    public var macReport: (Json) -> Void = { _ in }
    public init() {}
}

public final class Flattener: @unchecked Sendable {
    private let lock = NSLock()
    private var _stopped = false
    public init() {}

    public var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return _stopped }
    public func requestStop() { lock.lock(); _stopped = true; lock.unlock() }

    /// Journal de l'adaptation au Mac : chaque correctif est annoncé avant d'être appliqué.
    public static func macLine(_ event: String, _ p: Json) -> String? {
        let title = MacAdapt.text(p["title"])
        switch event {
        case "start": return T("log_mac_start")
        case "fix": return T("log_mac_fix", ["title": title])
        case "skip": return T("log_mac_skip", ["title": title])
        case "applied": return T("log_mac_ok", ["title": title])
        case "failed": return T("log_mac_failed", ["title": title])
        case "stock": return T("log_mac_stock")
        case "no_bottle": return T("log_mac_no_bottle")
        case "none": return T("log_mac_none")
        case "done": return T("log_mac_done", p)
        case "error": return T("log_mac_error", ["reason": MacAdapt.text(p["text"])])
        case "previous_undone": return T("log_mac_prev_undone", p)
        case "previous_refused": return T("log_mac_prev_refused")
        default: return nil
        }
    }

    private func runMacStage(_ o: FlattenOptions, _ ev: FlattenEvents) {
        let notify: MacAdapt.Notify = { event, payload in
            if let line = Flattener.macLine(event, payload) { ev.log(line) }
        }
        if o.macMode == "stock" {
            ev.macReport(MacAdapt.finishStock(o.destGameRoot, notify: notify))
            return
        }
        var report: Json
        do {
            ev.macStage()
            ev.progress(97)
            let mods = isFile(o.modlistFile) ? try parseModlist(o.modlistFile) : []
            var bottle = o.macBottle.flatMap { $0.isEmpty ? nil : $0 }
            if o.macBottle == nil {  // automatique : même choix que la carte (le jeu vient d'être créé : on le refait ici)
                bottle = MacAdapt.detectBottle(MacAdapt.listBottles(), gameDir: o.destGameRoot).bottle?.str("path")
            }
            report = MacAdapt.finish(o.destGameRoot, bottle: bottle, mo2Dir: o.mo2Dir, mods: mods, notify: notify)
        } catch {
            report = ["game": o.destGameRoot, "items": [Json](), "discarded": [Any](), "bottled": NSNull(), "applied": [Any](),
                      "error": ["key": "mackit.cli.error"] as Json, "unavailable": false, "undone": 0]
            notify("error", ["text": report["error"] ?? NSNull(), "detail": "\(error)"])
        }
        ev.macReport(report)
    }

    public func run(_ o: FlattenOptions, _ ev: FlattenEvents) -> FlattenOutcome {
        do {
            ev.log(T("log_analyzing", ["name": pyName(o.modlistFile)]))
            ev.log(T("log_indexing_ram"))
            let tasks = try buildTasks(mo2Dir: o.mo2Dir, modlistFile: o.modlistFile, destGameRoot: o.destGameRoot, stopped: { self.isStopped })
            let profileDir = pyParent(o.modlistFile)
            if isStopped { return .stopped }

            let destData = pyJoin(o.destGameRoot, "Data")
            try makeDirs(pyPath(o.destGameRoot))
            try makeDirs(destData)
            // un nouvel assemblage écrase les fichiers que l'adaptation précédente avait changés : on l'annule d'abord
            MacAdapt.undoPrevious(pyPath(o.destGameRoot)) { event, payload in
                if let line = Flattener.macLine(event, payload) { ev.log(line) }
            }
            ev.log(T("log_root_dir", ["path": pyPath(o.destGameRoot)]))
            ev.log(T("log_data_dir", ["path": destData]))
            ev.log(T("log_filters"))

            let total = tasks.count
            ev.log(T("log_index_complete", ["total": total]))
            ev.log(T("log_copy_start"))

            let workers = min(32, ProcessInfo.processInfo.activeProcessorCount * 2)
            var copied = 0
            var fatal: String?
            let state = NSLock()
            let next = ManagedCounter()
            let group = DispatchGroup()
            for _ in 0..<workers {
                group.enter()
                Thread.detachNewThread {
                    defer { group.leave() }
                    while true {
                        if self.isStopped { return }
                        let i = next.take()
                        if i >= total { return }
                        let t = tasks[i]
                        do {
                            try optimizedCopyFile(t.src, t.dst, useHardlinks: o.useHardlinks)
                            state.lock()
                            copied += 1
                            if copied % 100 == 0 || copied == total {
                                ev.progress(Int(Double(copied) / Double(total) * 95))
                                if copied % 500 == 0 { ev.log(T("log_progress", ["current": copied, "total": total])) }
                            }
                            state.unlock()
                        } catch {
                            state.lock()
                            ev.log(T("log_copy_err", ["src": pyName(t.src), "dst": pyName(t.dst), "err": "\(error)"]))
                            if o.stopOnError && fatal == nil {
                                fatal = T("log_copy_abort_err", ["err": "\(error)"])
                                self.requestStop()
                            }
                            state.unlock()
                            if o.stopOnError { return }
                        }
                    }
                }
            }
            group.wait()
            if let fatal { return .error(fatal) }
            if isStopped { return .stopped }

            // Déploiement des configurations
            if o.copyPlugins, let dest = o.pluginsDest, !dest.isEmpty {
                let src = pyJoin(profileDir, "plugins.txt")
                if isFile(src) {
                    try makeDirs(pyPath(dest))
                    try copy2(src, pyJoin(dest, "plugins.txt"))
                    ev.log(T("log_plugin_deployed", ["path": pyJoin(dest, "plugins.txt")]))
                }
            }
            if o.copyInis, let dest = o.inisDest, !dest.isEmpty {
                try makeDirs(pyPath(dest))
                for iniName in ["skyrim.ini", "skyrimprefs.ini"] {
                    var srcIni = pyJoin(profileDir, iniName)
                    if !isFile(srcIni), let m = (scanDir(profileDir) ?? []).first(where: { $0.name.lowercased() == iniName }) {
                        srcIni = pyJoin(profileDir, m.name)
                    }
                    if isFile(srcIni) {
                        try copy2(srcIni, pyJoin(dest, pyName(srcIni)))
                        ev.log(T("log_ini_deployed", ["name": pyName(srcIni)]))
                    }
                }
            }

            if o.macMode != nil && !isStopped { runMacStage(o, ev) }

            ev.progress(100)
            ev.log(T("log_success", ["count": copied]))
            return .finished(copied: copied)
        } catch {
            return .error("\(error)")
        }
    }
}

final class ManagedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func take() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n - 1 }
}
