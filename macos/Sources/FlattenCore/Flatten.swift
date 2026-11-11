// Moteur de mO2FLATTENER, sans interface : lecture de modlist.txt, résolution des conflits, copie.
// Traduction ligne à ligne de src/mo2_flattener_core.py (version Python, retirée).
//
// Règles MO2 (modorganizer, profile.cpp) : modlist.txt va de la priorité la plus HAUTE à la plus basse ;
// « + » actif, « - » désactivé, « * » DLC ou Creation Club (pas un dossier de mod). Le dossier overwrite a
// toujours la priorité maximale. Les mods « Root Builder » rangent les fichiers de la racine du jeu dans Root/.
// Les noms sont comparés sans tenir compte de la casse (comme Windows), mais copiés avec leur casse d'origine.

import Darwin
import Foundation

public enum Rules {
    public static let ignoredFiles: Set<String> = ["meta.ini"]
    public static let ignoredDirs: Set<String> = [".git", ".svn", "__pycache__", "__macosx"]
    public static let ignoredExtensions: Set<String> = [".pdb", ".mohidden"]

    /// Extensions parasites à ignorer directement à la racine de Data
    public static let ignoredRootFileExtensions: Set<String> = [".txt", ".md", ".html", ".modgroups", ".ds_store"]

    /// Dossiers parasites inertes à ignorer dans Data
    public static let ignoredDataRootDirs: Set<String> = [
        "fomod", "docs", "documentation", "readme", "readmes", "hashtags", "3dnpc-amm", "dip", "oathvein racemenu dip",
        "headpartwhitelist", "optional", "source", "merge", "echizen spear remastered readme", "ax_readmefiles",
        "amidianborn optional plugins", ".esp", ".esp version", "esl", "esp",
    ]
}

/// Une tâche : fichier source -> chemin de destination.
public struct FlatTask: Equatable, Sendable {
    public let src: String
    public let dst: String
    public init(src: String, dst: String) { self.src = src; self.dst = dst }
}

/// Fichiers que macOS dépose tout seul, jamais des fichiers de mod : `.DS_Store`, et `._nom`, où macOS range les
/// attributs étendus de « nom » sur un disque qui n'en a pas (exFAT, FAT, partage réseau). Copié dans Data, Wine le
/// voit comme un vrai fichier : SKSE essayait de charger « ._EngineFixes.dll » et le jeu plantait (constaté par
/// SkyrimMT, ticket GitHub #16). Ignorés partout, pas seulement à la racine de Data.
public func isMacMetadataFile(_ filename: String) -> Bool {
    filename.hasPrefix("._") || filename.lowercased() == ".ds_store"
}

/// Le volume garde-t-il les attributs étendus dans le système de fichiers (APFS, HFS+) ? Sinon, écrire un attribut
/// crée un fichier « ._nom » visible à côté du fichier.
public func hasNativeAttributes(_ path: String) -> Bool {
    var s = statfs()
    guard statfs(path, &s) == 0 else { return true }
    let type = withUnsafePointer(to: &s.f_fstypename) {
        $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) { String(cString: $0) }
    }
    return type == "apfs" || type == "hfs"
}

public func isIgnoredFile(_ filename: String, isDataRoot: Bool = false) -> Bool {
    if Rules.ignoredFiles.contains(filename) || isMacMetadataFile(filename) { return true }
    let lower = filename.lowercased()
    if lower.hasSuffix(".mohidden") { return true }
    let ext = pySplitExt(lower).ext
    if Rules.ignoredExtensions.contains(ext) { return true }
    if isDataRoot && Rules.ignoredRootFileExtensions.contains(ext) { return true }
    return false
}

public func isIgnoredDir(_ dirname: String) -> Bool {
    let lower = dirname.lowercased()
    if Rules.ignoredDirs.contains(lower) || Rules.ignoredDataRootDirs.contains(lower) { return true }
    return lower.hasSuffix(".mohidden")
}

func filterDirsInPlace(_ dirs: inout [String]) { dirs = dirs.filter { !isIgnoredDir($0) } }

public struct ModlistError: Error, CustomStringConvertible, LocalizedError {
    public let path: String
    public var description: String { "'utf-8' codec can't decode modlist.txt: \(path)" }
    public var errorDescription: String? { description }
}

/// Lignes d'un fichier comme `open(..., "r", encoding="utf-8-sig")` : fins de ligne \n, \r\n, \r ; BOM retiré.
func readLines(_ path: String) throws -> [String] {
    guard let data = FileManager.default.contents(atPath: path) else {
        throw PyOSError(isFile(path) ? EACCES : (isDir(path) ? EISDIR : ENOENT), path)
    }
    var bytes = data[...]
    if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
    guard let text = String(data: Data(bytes), encoding: .utf8) else { throw ModlistError(path: path) }
    var lines: [String] = []
    var cur = String.UnicodeScalarView()
    var prevCR = false
    for u in text.unicodeScalars {
        if prevCR {
            prevCR = false
            if u == "\n" { continue }
        }
        if u == "\n" || u == "\r" {
            lines.append(String(cur)); cur = String.UnicodeScalarView()
            prevCR = u == "\r"
        } else {
            cur.append(u)
        }
    }
    if !cur.isEmpty { lines.append(String(cur)) }
    return lines
}

private let pyWhitespace = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{1c}\u{1d}\u{1e}\u{1f}\u{85}"))

func pyStrip(_ s: String) -> String { s.trimmingCharacters(in: pyWhitespace) }

/// Mods actifs, de la priorité la plus basse à la plus haute (ordre d'application).
public func parseModlist(_ modlistPath: String) throws -> [String] {
    let lines = try readLines(modlistPath).map(pyStrip).filter { !$0.isEmpty }
    var active: [String] = []
    for line in lines.reversed() where line.hasPrefix("+") {
        let m = pyStrip(String(line.dropFirst()))
        if !m.isEmpty && !m.hasSuffix("_separator") { active.append(m) }
    }
    return active
}

public func findStockGame(_ mo2Dir: String) -> String? {
    for candidate in [pyJoin(pyParent(mo2Dir), "STOCK GAME"), pyJoin(mo2Dir, "STOCK GAME")] where isDir(candidate) {
        return candidate
    }
    return nil
}

/// Chemins relatifs indexés sans casse ; le dernier ajouté gagne, sa casse est conservée (et sa place dans l'ordre aussi, comme un dict).
final class FileMap {
    private var index: [[UInt8]: Int] = [:]
    private var entries: [(rel: String, src: String)] = []

    func add(_ rel: String, _ src: String) {
        let key = Array(rel.lowercased().utf8)
        if let i = index[key] { entries[i] = (rel, src) } else { index[key] = entries.count; entries.append((rel, src)) }
    }

    func tasks(_ dest: String) -> [FlatTask] { entries.map { FlatTask(src: $0.src, dst: pyJoin(dest, $0.rel)) } }
}

private func relPath(_ rel: [String], _ name: String) -> String { (rel + [name]).joined(separator: "/") }

private func walkData(_ base: String, _ dataMap: FileMap, skipRootDir: Bool = false) {
    walkTree(base) { root, rel, dirs, files in
        filterDirsInPlace(&dirs)
        if skipRootDir && rel.isEmpty { dirs = dirs.filter { $0 != "Root" } }
        for f in files {
            let fullP = root + "/" + f
            let parts = rel + [f]
            if isIgnoredFile(f, isDataRoot: parts.count == 1) { continue }
            if let first = parts.first, Rules.ignoredDataRootDirs.contains(first.lowercased()) { continue }
            dataMap.add(parts.joined(separator: "/"), fullP)
        }
        return true
    }
}

/// Liste des copies à faire, conflits déjà résolus : STOCK GAME, puis les mods par priorité, puis overwrite.
/// `stopped` vrai en cours de route : liste vide (comme la version Python).
public func buildTasks(mo2Dir: String, modlistFile: String, destGameRoot: String,
                       stopped: () -> Bool = { false }) throws -> [FlatTask] {
    let dataMap = FileMap(), rootMap = FileMap()
    let mo2 = pyPath(mo2Dir)

    if let stockGameDir = findStockGame(mo2) {
        var aborted = false
        let complete = walkTree(stockGameDir) { root, rel, dirs, files in
            if stopped() { aborted = true; return false }
            filterDirsInPlace(&dirs)
            for f in files {
                let fullP = root + "/" + f
                let parts = rel + [f]
                let isData = parts[0].lowercased() == "data"
                if isIgnoredFile(f, isDataRoot: isData && parts.count == 2) { continue }
                if isData {
                    let sub = Array(parts.dropFirst())
                    if let first = sub.first, Rules.ignoredDataRootDirs.contains(first.lowercased()) { continue }
                    dataMap.add(sub.isEmpty ? "." : sub.joined(separator: "/"), fullP)
                } else {
                    rootMap.add(parts.joined(separator: "/"), fullP)
                }
            }
            return true
        }
        if aborted || !complete { return [] }
    }

    let modsDir = pyJoin(mo2, "mods")
    for modName in try parseModlist(modlistFile) {
        if stopped() { return [] }
        let modPath = pyJoin(modsDir, modName)
        if !isDir(modPath) || isIgnoredDir(modName) { continue }

        let rootBuilderDir = pyJoin(modPath, "Root")
        if isDir(rootBuilderDir) {
            walkTree(rootBuilderDir) { root, rel, dirs, files in
                filterDirsInPlace(&dirs)
                for f in files where !isIgnoredFile(f) {
                    rootMap.add(relPath(rel, f), root + "/" + f)
                }
                return true
            }
        }

        let nestedData = pyJoin(modPath, "Data")
        if isDir(nestedData) && !isDir(pyJoin(modPath, "textures")) && !isDir(pyJoin(modPath, "meshes")) {
            walkData(nestedData, dataMap)
        } else {
            walkData(modPath, dataMap, skipRootDir: true)
        }
    }

    let overwriteDir = pyJoin(mo2, "overwrite")
    if isDir(overwriteDir) { walkData(overwriteDir, dataMap) }

    return rootMap.tasks(destGameRoot) + dataMap.tasks(pyJoin(destGameRoot, "Data"))
}

// MARK: Copie

/// clonefile(2) : copie APFS instantanée qui partage les blocs de données (aucune place en plus) tout en restant
/// un fichier indépendant, contrairement à un lien physique. Échoue entre deux volumes ou hors APFS.
public func cloneFile(_ src: String, _ dst: String) -> Bool { clonefile(src, dst, 0) == 0 }

func makeDirs(_ path: String) throws {
    var st = stat()
    if stat(path, &st) == 0 {
        if (st.st_mode & S_IFMT) == S_IFDIR { return }
        throw PyOSError(EEXIST, path)
    }
    do { try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true) }
    catch { throw PyOSError(errno != 0 ? errno : EACCES, path) }
}

/// `shutil.copystat` : droits, dates, drapeaux et attributs étendus. Pas d'attributs vers un disque exFAT ou FAT :
/// macOS les écrirait dans un fichier « ._nom » que le jeu prendrait pour un fichier de mod.
func copyStat(_ src: String, _ dst: String) {
    var st = stat()
    guard stat(src, &st) == 0 else { return }
    if hasNativeAttributes(dst) { _ = copyfile(src, dst, nil, copyfile_flags_t(COPYFILE_XATTR)) }
    var times = [st.st_atimespec, st.st_mtimespec]
    _ = utimensat(AT_FDCWD, dst, &times, 0)
    _ = chmod(dst, st.st_mode & 0o7777)
    _ = chflags(dst, st.st_flags)
}

/// `shutil.copyfileobj` par blocs de 1 Mo, puis `copystat` si demandé.
func copyData(_ src: String, _ dst: String) throws {
    let inFd = open(src, O_RDONLY)
    if inFd < 0 { throw PyOSError(errno, src) }
    defer { close(inFd) }
    let outFd = open(dst, O_WRONLY | O_CREAT | O_TRUNC, 0o666)
    if outFd < 0 { throw PyOSError(errno, dst) }
    defer { close(outFd) }
    let size = 1024 * 1024
    let buf = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
    defer { buf.deallocate() }
    while true {
        let n = read(inFd, buf, size)
        if n < 0 { throw PyOSError(errno, src) }
        if n == 0 { break }
        var off = 0
        while off < n {
            let w = write(outFd, buf + off, n - off)
            if w < 0 { throw PyOSError(errno, dst) }
            off += w
        }
    }
}

/// `shutil.copy2`
public func copy2(_ src: String, _ dst: String) throws {
    var target = dst
    if isDir(dst) { target = pyJoin(dst, pyName(src)) }
    try copyData(src, target)
    copyStat(src, target)
}

/// Copie APFS si possible, sinon lien physique (si demandé), sinon copie complète. Renvoie la méthode.
@discardableResult
public func optimizedCopyFile(_ src: String, _ dst: String, useHardlinks: Bool) throws -> String {
    try makeDirs(pyParent(dst))
    var st = stat()
    if lstat(dst, &st) == 0 { _ = unlink(dst) }

    if cloneFile(src, dst) { return "clone" }
    if useHardlinks, link(src, dst) == 0 { return "link" }

    try copyData(src, dst)
    copyStat(src, dst)
    return "copy"
}
