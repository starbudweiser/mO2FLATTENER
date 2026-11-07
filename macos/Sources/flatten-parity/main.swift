// Comparaison avec la version Python (essais, sans interface) :
//   flatten-parity tasks <mo2> <modlist> <dest>        -> « source<TAB>destination » triés, une ligne par tâche
//   flatten-parity flatten <mo2> <modlist> <dest> [--hardlinks]  -> aplatit vers <dest> (jamais un vrai dossier de jeu)
import FlattenCore
import Foundation

let a = CommandLine.arguments
func die(_ m: String) -> Never { FileHandle.standardError.write(Data((m + "\n").utf8)); exit(2) }
guard a.count >= 4 else { die("usage: flatten-parity tasks|flatten <mo2> <modlist> <dest>") }
switch a[1] {
case "tasks":
    let t = try buildTasks(mo2Dir: a[2], modlistFile: a[3], destGameRoot: a[4])
    for l in t.map({ "\($0.src)\t\($0.dst)" }).sorted() { print(l) }
case "flatten":
    var o = FlattenOptions(mo2Dir: a[2], modlistFile: a[3], destGameRoot: a[4])
    o.useHardlinks = a.contains("--hardlinks")
    var ev = FlattenEvents()
    ev.log = { print($0) }
    switch Flattener().run(o, ev) {
    case .finished(let n): print("OK \(n)")
    case .stopped: print("STOPPED")
    case .error(let e): print("ERROR \(e)"); exit(1)
    }
case "mac":  // flatten-parity mac <jeu> <bouteille> -> finish puis JSON du bilan (sur un faux jeu d'essai)
    let r = MacAdapt.finish(a[2], bottle: a[3])
    print(String(decoding: try JSONSerialization.data(withJSONObject: r, options: [.sortedKeys]), as: UTF8.self))
default: die("commande inconnue")
}
