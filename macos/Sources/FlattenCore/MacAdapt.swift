// Adaptation au Mac (DXMT, ENB, DLSS) : pont entre mO2FLATTENER et l'outil en ligne de commande `mackit`.
// Traduction de src/mac_adapt.py (version Python, retirée).
//
// `mackit` est le moteur Mac commun de mORTEX, mABBAJACK et mO2FLATTENER (_tools/shared/mackit) : mO2FLATTENER
// l'embarque tel quel et ne fait que l'appeler (`plan`, `apply`, `undo`, `applied`, `bottles`), en JSON. Le moteur ne
// renvoie aucune phrase, seulement des clés « mackit.* » {key, params} : l'interface les traduit (T).
//
// Rien ne lève ici : une erreur de l'outil se lit dans le dictionnaire renvoyé (`ok: false`, `error`), pour qu'elle ne
// fasse jamais échouer un assemblage.
//
// Bottled Shaders : mO2FLATTENER n'a pas de clé Nexus. Il cherche l'archive (1.0.26 ou plus récente) dans les
// téléchargements de l'instance MO2 puis dans ceux de mABBAJACK ; à défaut, le bilan renvoie vers la page Nexus. Il ne
// télécharge ni n'embarque rien. Le pont mDLSS (d3d11.dll) n'est pas embarqué non plus : celui de mORTEX, s'il est installé.

import Darwin
import Foundation

public typealias Json = [String: Any]

extension Dictionary where Key == String, Value == Any {
    public func str(_ k: String) -> String? { self[k] as? String }
    public func arr(_ k: String) -> [Json] { (self[k] as? [Any])?.compactMap { $0 as? Json } ?? [] }
    public func obj(_ k: String) -> Json? { self[k] as? Json }
    public func flag(_ k: String) -> Bool { (self[k] as? Bool) ?? ((self[k] as? NSNumber)?.boolValue ?? false) }
    public func int(_ k: String) -> Int { (self[k] as? Int) ?? ((self[k] as? NSNumber)?.intValue ?? 0) }
}

public enum MacAdapt {
    public static let bottledModId = "192816"
    public static let bottledPage = "https://www.nexusmods.com/skyrimspecialedition/mods/192816"
    public static let bottledMinimum = "1.0.26"
    public static let backupDir = "_MAC_BACKUP"
    public static let manifest = "manifest.json"
    public static let fixIds = ["engine", "bridge", "displayTweaks", "duplicates", "compiler", "overrides"]
    /// correctif -> contrôle du moteur qui dit s'il est déjà en ordre
    static let okChecks: [(String, String)] = [("engine", "engine"), ("bridge", "bridge"), ("displayTweaks", "displayTweaks"), ("duplicates", "bottledDuplicates")]
    /// correctifs qui ne touchent que la bouteille (les autres lisent les fichiers du jeu)
    public static let bottleFixes = ["engine"]
    static let archiveExtensions = [".7z", ".zip", ".rar"]

    // MARK: L'outil `mackit`

    /// Fichier d'état des bouteilles de l'appli (MO2FLATTENER_MAC_STATE pour les essais).
    public static func stateFile() -> String {
        if let custom = ProcessInfo.processInfo.environment["MO2FLATTENER_MAC_STATE"], !custom.isEmpty { return custom }
        return homeDir() + "/Library/Application Support/mO2FLATTENER/bottles.json"
    }

    /// Pour les essais : remplace la recherche de l'exécutable (nil = recherche normale).
    nonisolated(unsafe) public static var mackitOverride: String??

    /// L'exécutable `mackit` : MACKIT_BIN, celui de l'.app (Resources, MacOS), sinon celui de _tools (développement).
    public static func mackitPath() -> String? {
        if let o = mackitOverride { return o }
        var candidates: [String] = []
        if let env = ProcessInfo.processInfo.environment["MACKIT_BIN"], !env.isEmpty { candidates.append(env) }
        if let res = Bundle.main.resourcePath { candidates.append(res + "/mackit") }
        if let exe = Bundle.main.executablePath { candidates.append(pyParent(exe) + "/mackit") }
        // développement : .../MAC/mO2FLATTENER/macos/Sources/FlattenCore/MacAdapt.swift -> .../MAC/_tools/shared/mackit/dist/mackit
        var dev = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { dev.deleteLastPathComponent() }
        candidates.append(dev.appendingPathComponent("_tools/shared/mackit/dist/mackit").path)
        for c in candidates {
            var st = stat()
            if stat(c, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, access(c, X_OK) == 0 { return c }
        }
        return nil
    }

    static func failure(_ key: String = "mackit.cli.error", detail: String = "", unavailable: Bool = false) -> Json {
        var out: Json = ["ok": false, "error": ["text": ["key": key], "detail": detail] as Json]
        if unavailable { out["unavailable"] = true }
        return out
    }

    /// Lance `mackit <args> --json --state <fichier>` et renvoie son JSON (code 0 ou 1) ; ne lève jamais. Un outil qui ne
    /// répond plus est arrêté au bout de `timeout` secondes : l'assemblage n'attend jamais indéfiniment.
    public static func run(_ args: [String], stdin: String? = nil, timeout: TimeInterval = 300) -> Json {
        guard let exe = mackitPath() else { return failure(detail: "mackit not found", unavailable: true) }
        let argv = args + ["--json", "--state", stateFile()]
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: exe)
        proc.arguments = argv
        let outPipe = Pipe(), errPipe = Pipe(), inPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        proc.standardInput = stdin != nil ? inPipe : FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        proc.terminationHandler = { _ in finished.signal() }
        do { try proc.run() } catch { return failure(detail: error.localizedDescription) }

        let group = DispatchGroup()
        nonisolated(unsafe) var outData = Data(), errData = Data()
        group.enter()
        DispatchQueue.global().async { outData = outPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { errData = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        if let stdin {
            DispatchQueue.global().async {
                try? inPipe.fileHandleForWriting.write(contentsOf: Data(stdin.utf8))
                try? inPipe.fileHandleForWriting.close()
            }
        }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            proc.terminate()
            _ = finished.wait(timeout: .now() + 5)
            if proc.isRunning { kill(proc.processIdentifier, SIGKILL) }
            return failure(detail: "Command '\(([exe] + argv).joined(separator: " "))' timed out after \(Int(timeout)) seconds")
        }
        group.wait()
        let stdout = String(decoding: outData, as: UTF8.self)
        let stderr = String(decoding: errData, as: UTF8.self)
        let lines = stdout.split(whereSeparator: \.isNewline).map(String.init).filter { !pyStrip($0).isEmpty }
        guard let last = lines.last, let data = last.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) else {
            let detail = !stderr.isEmpty ? stderr : (!stdout.isEmpty ? stdout : "exit \(proc.terminationStatus)")
            return failure(detail: String(detail.prefix(300)))
        }
        guard var dict = parsed as? Json else { return failure(detail: "unexpected output") }
        let code = proc.terminationStatus
        if code != 0 && code != 1 { dict["ok"] = false }  // 2 = appel mal formé : un défaut de l'appli, pas du jeu
        return dict
    }

    /// (clé, valeurs à insérer) d'un texte du moteur.
    public static func textOf(_ obj: Any?) -> (key: String, params: Json) {
        guard let d = obj as? Json else { return ("mackit.cli.error", [:]) }
        return (d.str("key") ?? "mackit.cli.error", d.obj("params") ?? [:])
    }

    /// Le texte {key, params} du moteur, dans la langue courante.
    public static func text(_ obj: Any?) -> String {
        let (key, params) = textOf(obj)
        return T(key, params)
    }

    /// Le texte de l'erreur d'un résultat en échec.
    public static func errorText(_ result: Json) -> Json {
        let err = result.obj("error") ?? [:]
        return err.obj("text") ?? ["key": "mackit.cli.error"]
    }

    // MARK: Bouteilles, pont mDLSS

    public static func listBottles() -> [Json] {
        let result = run(["bottles"])
        return result.flag("ok") ? result.arr("bottles") : []
    }

    static func inside(_ child: String, _ parent: String) -> Bool {
        let c = realPath(child), p = realPath(parent)
        var prefix = p
        while prefix.hasSuffix("/") && prefix.count > 1 { prefix.removeLast() }
        return c == p || c.hasPrefix(prefix == "/" ? "/" : prefix + "/")
    }

    /// La bouteille qui contient le dossier du jeu (« detected »), sinon la première bouteille CrossOver (« first »).
    public static func detectBottle(_ bottles: [Json], gameDir: String?) -> (bottle: Json?, how: String?) {
        if let gameDir, !gameDir.isEmpty {
            for b in bottles where inside(gameDir, b.str("path") ?? "\u{0}") { return (b, "detected") }
        }
        for b in bottles where b.str("kind") == "crossover" { return (b, "first") }
        return (nil, nil)
    }

    /// Le pont mDLSS (d3d11.dll) de mORTEX, s'il est installé sur ce Mac ; jamais embarqué ici.
    public static func findBridge() -> String? {
        if let env = ProcessInfo.processInfo.environment["MO2FLATTENER_MDLSS_BRIDGE"], !env.isEmpty {
            return isFile(env) ? env : nil
        }
        let tail = "mORTEX.app/Contents/Resources/app.asar.unpacked/assets/mdlss/d3d11.dll"
        for base in [homeDir() + "/Applications/Skyrim Tools", "/Applications"] where isFile(base + "/" + tail) {
            return base + "/" + tail
        }
        return nil
    }

    // MARK: Bottled Shaders : archive déjà téléchargée

    /// « 1.0.26 » -> [1, 0, 26] ; une version illisible est la plus ancienne.
    public static func versionTuple(_ version: String) -> [Int] {
        let parts = matches(#"\d+"#, in: version).compactMap { Int($0) }
        return parts.isEmpty ? [0] : parts
    }

    /// Comparaison de tuples comme Python : élément par élément, le plus court d'abord à préfixe égal.
    static func tupleLess(_ a: [Int], _ b: [Int]) -> Bool {
        for (x, y) in zip(a, b) where x != y { return x < y }
        return a.count < b.count
    }

    public static func versionAtLeast(_ version: String, _ minimum: String) -> Bool {
        var a = versionTuple(version), b = versionTuple(minimum)
        let size = max(a.count, b.count)
        a += Array(repeating: 0, count: size - a.count)
        b += Array(repeating: 0, count: size - b.count)
        return !tupleLess(a, b)
    }

    static func matches(_ pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    static func groups(_ pattern: String, in text: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (1..<m.numberOfRanges).map { ns.substring(with: m.range(at: $0)) }
    }

    /// Valeur d'une clé d'un .ini de MO2 (sans tenir compte de la casse ni de la section).
    static func iniValue(_ ini: String, _ key: String) -> String? {
        guard let data = FileManager.default.contents(atPath: ini) else { return nil }
        var bytes = data[...]
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        let text = String(decoding: bytes, as: UTF8.self)  // errors="replace"
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            guard let eq = line.firstIndex(of: "=") else { continue }
            let name = pyStrip(String(line[..<eq]))
            if name.lowercased() == key.lowercased() { return pyStrip(String(line[line.index(after: eq)...])) }
        }
        return nil
    }

    /// Chemin d'un réglage MO2 (%BASE_DIR%, Z:/…, antislashs) vers un chemin du Mac.
    public static func mo2Path(_ value: String, base: String) -> String? {
        var v = pyStrip(value)
        v = v.trimmingCharacters(in: CharacterSet(charactersIn: "\"")).replacingOccurrences(of: "\\", with: "/")
        if v.hasPrefix("@ByteArray(") && v.hasSuffix(")") { v = String(v.dropFirst("@ByteArray(".count).dropLast()) }
        v = v.replacingOccurrences(of: "%BASE_DIR%", with: base)
        if groups(#"^([A-Za-z]):/"#, in: v) != nil {
            if v.first!.uppercased() != "Z" { return nil }  // un autre lecteur Wine : pas de correspondance simple sur le Mac
            v = String(v.dropFirst(2))
        }
        return v.hasPrefix("/") ? pyPath(v) : nil
    }

    /// Sous-dossier `name` de `parent`, sans tenir compte de la casse (DOWNLOADS, downloads…).
    static func namedDir(_ parent: String, _ name: String) -> String? {
        for e in scanDir(parent) ?? [] where e.name.lowercased() == name.lowercased() && e.isDir { return parent + "/" + e.name }
        return nil
    }

    /// Dossiers où chercher l'archive : téléchargements de l'instance MO2, puis ceux de mABBAJACK.
    public static func downloadFolders(_ mo2Dir: String) -> [(path: String, source: String)] {
        var found: [(path: String, source: String)] = []
        func add(_ folder: String?, _ source: String) {
            guard let folder, isDir(folder) else { return }
            let real = realPath(folder)
            if found.allSatisfy({ realPath($0.path) != real }) { found.append((folder, source)) }
        }
        let mo2 = pyPath(mo2Dir)
        // la racine de l'instance : le dossier choisi, ou son parent si l'utilisateur a désigné le dossier « mods »
        for base in [mo2, pyParent(mo2)] {
            let ini = base + "/ModOrganizer.ini"
            if isFile(ini) {
                let value = iniValue(ini, "download_directory")
                add(value.flatMap { $0.isEmpty ? nil : mo2Path($0, base: base) }, "mo2")
                add(namedDir(base, "downloads"), "mo2")
            }
        }
        add(namedDir(mo2, "downloads"), "mo2")
        // mABBAJACK range les archives dans <destination>/DOWNLOADS (avec l'instance), et les liens nxm dans ~/Downloads
        if let env = ProcessInfo.processInfo.environment["MABBAJACK_DOWNLOADS"], !env.isEmpty { add(pyPath(env), "mabbajack") }
        for base in [pyParent(mo2), pyParent(pyParent(mo2))] { add(namedDir(base, "downloads"), "mabbajack") }
        add(homeDir() + "/Downloads", "mabbajack")
        return found
    }

    /// Version d'une archive de Bottled Shaders : fichier .meta de MO2, sinon le nom (Nexus : « nom-192816-1-0-26-… »).
    public static func archiveVersion(_ path: String) -> String? {
        let meta = path + ".meta"
        if isFile(meta) {
            let modId = iniValue(meta, "modID"), version = iniValue(meta, "version")
            if (modId == nil || modId == bottledModId), let version, !version.isEmpty { return version }
        }
        let stem = pyStem(path)
        let g = groups(bottledModId + #"[\s._-]+(\d+)[\s._-](\d+)[\s._-](\d+)"#, in: stem)
            ?? groups(#"(?<![\d.])(\d+)\.(\d+)\.(\d+)(?![\d.])"#, in: stem)
        return g?.joined(separator: ".")
    }

    /// L'archive de Bottled Shaders la plus récente (au moins `minimum`) déjà téléchargée, sinon nil.
    public static func findBottledArchive(_ mo2Dir: String, minimum: String = bottledMinimum) -> Json? {
        var best: Json?
        for (folder, source) in downloadFolders(mo2Dir) {
            guard let entries = scanDir(folder) else { continue }
            for entry in entries {
                let lower = entry.name.lowercased()
                guard archiveExtensions.contains(where: { lower.hasSuffix($0) }), lower.contains("bottled"), lower.contains("shaders") else { continue }
                let path = folder + "/" + entry.name
                guard let version = archiveVersion(path), versionAtLeast(version, minimum) else { continue }
                if best == nil || tupleLess(versionTuple(best!.str("version")!), versionTuple(version)) {
                    best = ["path": path, "name": entry.name, "folder": folder, "version": version, "source": source]
                }
            }
        }
        return best
    }

    /// Version de Bottled Shaders d'après le meta.ini des mods actifs de l'instance (plus sûr que la DLL).
    public static func installedBottledVersion(_ mo2Dir: String, mods: [String]) -> String? {
        var best: String?
        for name in mods {
            let meta = pyJoin(pyJoin(pyJoin(mo2Dir, "mods"), name), "meta.ini")
            guard isFile(meta), iniValue(meta, "modid") == bottledModId else { continue }
            if let version = iniValue(meta, "version"), !version.isEmpty, best == nil || tupleLess(versionTuple(best!), versionTuple(version)) {
                best = version
            }
        }
        return best
    }

    /// État de Bottled Shaders du plan + archive trouvée (jamais téléchargée) et page Nexus.
    public static func bottledInfo(_ planBottled: Json?, mo2Dir: String?) -> Json {
        var info: Json = planBottled ?? ["state": "absent", "minimum": bottledMinimum]
        info["page"] = bottledPage
        info["archive"] = NSNull()
        if ["stock", "outdated", "unknown"].contains(info.str("state") ?? ""), let mo2Dir {
            let minimum = (info.str("minimum")).flatMap { $0.isEmpty ? nil : $0 } ?? bottledMinimum
            if let a = findBottledArchive(mo2Dir, minimum: minimum) { info["archive"] = a }
        }
        return info
    }

    // MARK: Simulation, application, annulation

    public static func hasManifest(_ game: String) -> Bool { isFile(pyJoin(pyJoin(game, backupDir), manifest)) }

    /// `mackit plan` : ce que l'adaptation ferait, sans rien écrire.
    public static func plan(_ game: String, bottle: String? = nil, bridge: String? = nil, bottledVersion: String? = nil) -> Json {
        var args = ["plan", "--game", game]
        if let bottle, !bottle.isEmpty { args += ["--bottle", bottle] }
        if let bridge, !bridge.isEmpty { args += ["--bridge", bridge] }
        if let bottledVersion, !bottledVersion.isEmpty { args += ["--bottled-version", bottledVersion] }
        return run(args)
    }

    /// `mackit apply` : exécute le plan tel quel (l'empreinte des fichiers protège d'un état qui a bougé).
    public static func apply(_ planObj: Json, only: [String]? = nil) -> Json {
        var args = ["apply", "--plan", "-"]
        if let only, !only.isEmpty { args += ["--only", only.joined(separator: ",")] }
        guard let data = try? JSONSerialization.data(withJSONObject: planObj, options: [.withoutEscapingSlashes]) else {
            return failure(detail: "plan not serializable")
        }
        return run(args, stdin: String(decoding: data, as: UTF8.self))
    }

    /// `mackit undo <id|all>` : remet les fichiers d'origine depuis <jeu>/_MAC_BACKUP.
    public static func undo(_ game: String, _ target: String) -> Json { run(["undo", "--game", game, target]) }

    /// Ce que le manifeste dit appliqué (carte « Bilan Mac »).
    public static func applied(_ game: String) -> [Json] {
        let result = run(["applied", "--game", game])
        return result.flag("ok") ? result.arr("applied") : []
    }

    /// Le plan sans ce qui sert seulement à l'appliquer (opérations, empreintes) : de quoi l'annoncer.
    public static func summarizePlan(_ planObj: Json) -> Json {
        var out: Json = [:]
        out["gamePath"] = planObj["gamePath"] ?? NSNull()
        out["fixes"] = planObj.arr("fixes").map { f -> Json in
            ["id": f["id"] ?? NSNull(), "title": f["title"] ?? NSNull(), "detail": f["detail"] ?? NSNull(),
             "files": f["files"] ?? [Any](), "changes": f["changes"] ?? NSNull()]
        }
        out["skipped"] = (planObj["skipped"] as? [Any]) ?? []
        out["discarded"] = (planObj["discarded"] as? [Any]) ?? []
        out["bottled"] = planObj["bottled"] ?? NSNull()
        out["ok"] = alreadyOk(planObj)
        return out
    }

    /// Les points que le moteur a contrôlés et trouvés « ok » (ni à faire ni écartés) : seuls ceux-là sont annoncés « déjà en
    /// ordre ». Un contrôle « na » (pas de Bottled Shaders, pas de SSE Display Tweaks…) ne dit rien : on ne l'annonce pas.
    public static func alreadyOk(_ planObj: Json) -> [String] {
        var statuses: [String: String] = [:]
        for c in planObj.arr("checks") { if let id = c.str("id") { statuses[id] = c.str("status") ?? "" } }
        let decided = Set(planObj.arr("fixes").compactMap { $0.str("id") } + planObj.arr("skipped").compactMap { $0.str("id") })
        return okChecks.filter { !decided.contains($0.0) && statuses[$0.1] == "ok" }.map(\.0)
    }

    /// Annonce du kit DXMT, avant l'assemblage. Un jeu cible qui n'existe pas encore est simulé sur un dossier vide : seuls
    /// les correctifs de la bouteille ressortent, le reste sera examiné à la fin de l'assemblage (`future`).
    /// Le kit est pour une bouteille CrossOver : sans bouteille, rien n'est annoncé (`nobottle`), jamais de demi-mesure.
    public static func preview(_ game: String, bottle: String?, mo2Dir: String? = nil, mods: [String] = []) -> Json {
        guard let bottle, !bottle.isEmpty else { return ["kind": "nobottle"] }
        let future = !isDir(pyJoin(game, "Data"))
        let version = (mo2Dir != nil && !mods.isEmpty) ? installedBottledVersion(mo2Dir!, mods: mods) : nil
        let emptyDir = NSTemporaryDirectory() + "mo2flattener_mac_" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: emptyDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: emptyDir) }
        let result = plan(isDir(game) ? game : emptyDir, bottle: bottle, bridge: findBridge(), bottledVersion: version)
        if result.flag("unavailable") { return ["kind": "unavailable"] }
        if !result.flag("ok") { return ["kind": "error", "error": errorText(result)] }
        guard let planObj = result.obj("plan") else { return ["kind": "error", "error": ["key": "mackit.cli.error"] as Json] }
        let previous = hasManifest(game) ? applied(game) : []
        var summary = summarizePlan(planObj)
        if !previous.isEmpty {
            summary["ok"] = [String]()  // l'adaptation précédente sera annulée puis refaite : rien n'est « déjà en ordre »
        } else if future {
            summary["ok"] = ((summary["ok"] as? [String]) ?? []).filter { bottleFixes.contains($0) }  // le reste dépend de fichiers du jeu, pas encore là
        }
        return ["kind": "plan", "future": future, "plan": summary,
                "bottled": bottledInfo(planObj.obj("bottled"), mo2Dir: mo2Dir), "previous": previous.count]
    }

    public typealias Notify = (String, Json) -> Void

    /// Un nouvel assemblage écrase les fichiers que l'adaptation précédente avait changés : on l'annule d'abord (le
    /// manifeste reste ainsi juste). Renvoie le nombre de correctifs annulés ; ne lève jamais.
    @discardableResult
    public static func undoPrevious(_ game: String, notify: Notify? = nil) -> Int {
        guard hasManifest(game) else { return 0 }
        if applied(game).isEmpty { return 0 }
        let result = undo(game, "all")
        let fixes = result.arr("fixes")
        let restored = fixes.filter { $0.str("status") == "restored" }.count
        if restored > 0 { notify?("previous_undone", ["n": restored]) }
        if fixes.contains(where: { $0.str("status") == "refused" }) || (!result.flag("ok") && fixes.isEmpty) {
            notify?("previous_refused", [:])
        }
        return restored
    }

    /// Dossier universel (Stock) : rien n'est copié ni modifié, `mackit` n'est même pas lancé. Bilan simple.
    public static func finishStock(_ game: String, notify: Notify? = nil) -> Json {
        notify?("stock", [:])
        return ["mode": "stock", "game": game, "bottle": NSNull(), "items": [Any](), "discarded": [Any](), "bottled": NSNull(),
                "applied": [Any](), "error": NSNull(), "unavailable": false, "undone": 0]
    }

    /// Fin d'assemblage, kit DXMT pour une bouteille CrossOver : `plan` puis `apply` sur le jeu assemblé, et le bilan.
    /// Sans bouteille, rien n'est touché (`no_bottle`). Ne lève jamais.
    ///
    /// `notify(événement, données)` annonce chaque étape (start, fix, skip, applied, failed, none, done) pour le journal.
    /// Bilan : { game, bottle, items: [{ id, status: applied|failed|skipped, undoable, title, detail?, text?, reason?,
    /// files, changes? }], discarded, bottled, applied, error?, unavailable? }.
    public static func finish(_ game: String, bottle: String?, mo2Dir: String? = nil, mods: [String] = [], notify: Notify? = nil) -> Json {
        let notify: Notify = notify ?? { _, _ in }
        var report: Json = ["mode": "crossover", "game": game, "bottle": NSNull(), "items": [Json](), "discarded": [Any](), "bottled": NSNull(),
                            "applied": [Any](), "error": NSNull(), "unavailable": false, "undone": 0]
        guard let bottle, !bottle.isEmpty else {  // le kit est pour une bouteille CrossOver : sans bouteille, aucune demi-mesure
            report["no_bottle"] = true
            notify("no_bottle", [:])
            return report
        }
        notify("start", [:])
        let bottles = listBottles()
        report["bottle"] = bottles.first { $0.str("path") == bottle } ?? NSNull()
        let version = (mo2Dir != nil && !mods.isEmpty) ? installedBottledVersion(mo2Dir!, mods: mods) : nil
        let result = plan(game, bottle: bottle, bridge: findBridge(), bottledVersion: version)
        if result.flag("unavailable") {
            report["unavailable"] = true
            report["error"] = errorText(result)
            return report
        }
        guard result.flag("ok"), let planObj = result.obj("plan") else {
            report["error"] = errorText(result)
            notify("error", ["text": report["error"] ?? NSNull(), "detail": result.obj("error")?.str("detail") ?? ""])
            return report
        }
        report["bottled"] = bottledInfo(planObj.obj("bottled"), mo2Dir: mo2Dir)
        report["discarded"] = (planObj["discarded"] as? [Any]) ?? []
        let fixes = planObj.arr("fixes"), skipped = planObj.arr("skipped")
        for fix in fixes { notify("fix", ["id": fix["id"] ?? "", "title": fix["title"] ?? NSNull()]) }
        for skip in skipped { notify("skip", ["id": skip["id"] ?? "", "title": ["key": "mackit.fix.\(skip.str("id") ?? "").title"] as Json]) }

        var outcomes: [Json] = []
        var appliedNow: [Json] = []
        if !fixes.isEmpty {
            let done = apply(planObj)
            outcomes = done.arr("outcomes")
            appliedNow = done.arr("applied")
            if outcomes.isEmpty {  // l'outil a refusé le plan en bloc : chaque correctif est noté échoué avec la raison
                let reason = errorText(done)
                outcomes = fixes.map { ["id": $0["id"] ?? "", "status": "failed", "text": reason] }
            }
        }
        var byId: [String: Json] = [:]
        for o in outcomes { if let id = o.str("id") { byId[id] = o } }
        var items: [Json] = []
        for fix in fixes {
            let outcome = byId[fix.str("id") ?? ""]
            let ok = outcome?.str("status") == "applied"
            items.append(["id": fix["id"] ?? "", "status": ok ? "applied" : "failed", "undoable": false, "title": fix["title"] ?? NSNull(),
                          "detail": fix["detail"] ?? NSNull(), "text": outcome?["text"] ?? NSNull(),
                          "files": fix["files"] ?? [Any](), "changes": fix["changes"] ?? NSNull()])
            notify(ok ? "applied" : "failed", ["id": fix["id"] ?? "", "title": fix["title"] ?? NSNull()])
        }
        for skip in skipped {
            items.append(["id": skip["id"] ?? "", "status": "skipped", "undoable": false,
                          "title": ["key": "mackit.fix.\(skip.str("id") ?? "").title"] as Json, "reason": skip["reason"] ?? NSNull(), "files": [Any]()])
        }
        let appliedList = !appliedNow.isEmpty ? appliedNow : (hasManifest(game) ? applied(game) : [])
        report["applied"] = appliedList
        let registered = Set(appliedList.compactMap { $0.str("id") })
        for i in items.indices {  // seuls les correctifs inscrits au manifeste s'annulent
            items[i]["undoable"] = items[i].str("status") == "applied" && registered.contains(items[i].str("id") ?? "")
        }
        report["items"] = items
        if items.isEmpty { notify("none", [:]) }
        notify("done", [
            "applied": items.filter { $0.str("status") == "applied" }.count,
            "failed": items.filter { $0.str("status") == "failed" }.count,
            "skipped": items.filter { $0.str("status") == "skipped" }.count,
        ])
        return report
    }

    /// Le bilan après une annulation : un correctif annulé en disparaît, un refus est dit sous sa ligne.
    public static func reportAfterUndo(_ report: Json, _ result: Json) -> Json {
        var updated = report
        let fixes = result.arr("fixes")
        let restored = Set(fixes.filter { $0.str("status") == "restored" }.compactMap { $0.str("id") })
        var refused: [String: Json] = [:]
        for f in fixes where f.str("status") == "refused" { if let id = f.str("id") { refused[id] = f } }
        let hasApplied = result["applied"] != nil
        let still: Set<String>? = hasApplied ? Set(result.arr("applied").compactMap { $0.str("id") }) : nil
        var items: [Json] = []
        for var item in report.arr("items") {
            let id = item.str("id") ?? ""
            if item.str("status") == "applied" && restored.contains(id) { continue }
            if let still, item.str("status") == "applied" { item["undoable"] = still.contains(id) }
            if let r = refused[id] { item["refusal"] = r["text"] ?? NSNull() } else { item.removeValue(forKey: "refusal") }
            items.append(item)
        }
        updated["items"] = items
        updated["applied"] = hasApplied ? result.arr("applied") : (report["applied"] ?? [Any]())
        updated["undone"] = report.int("undone") + restored.count
        return updated
    }
}
