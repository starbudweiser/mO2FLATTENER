// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mO2FLATTENER",
    platforms: [.macOS(.v15)],
    targets: [
        // Lecture de modlist.txt, fichiers des mods, copies, pont vers mackit et traductions, sans interface (testable seul)
        .target(name: "FlattenCore"),
        // Petit exécutable de comparaison avec la version Python : liste des tâches, aplatissement, arbres
        .executableTarget(name: "flatten-parity", dependencies: ["FlattenCore"]),
        .executableTarget(name: "mO2FLATTENER", dependencies: ["FlattenCore"]),
        .testTarget(name: "FlattenCoreTests", dependencies: ["FlattenCore"]),
    ],
    swiftLanguageModes: [.v5]
)
