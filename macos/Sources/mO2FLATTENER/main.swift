// Point d'entrée : fenêtre AppKit unique (1180 × 900, redimensionnable) qui héberge l'interface SwiftUI.

import AppKit
import FlattenCore
import SwiftUI

func windowTitle() -> String { "mO2FLATTENER" }

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    let model = AppModel()
    let settings = AppSettings(suite: ProcessInfo.processInfo.environment["MO2FLATTENER_SUITE"])

    func applicationDidFinishLaunching(_ notification: Notification) {
        Socle.apply()
        // « m » dans le rouge du logo
        Socle.brand("mO2FLATTENER", color: Color(red: 0xe5 / 255, green: 0x48 / 255, blue: 0x3a / 255))
        buildMenu()

        let host = NSHostingView(rootView: ContentView(model: model))
        window = NSWindow(contentRect: NSRect(origin: .zero, size: WINDOW_SIZE),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = windowTitle()
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.backgroundColor = NSColor(Socle.C.bg)
        window.contentMinSize = NSSize(width: 1100, height: 640)
        let avail = NSScreen.main?.visibleFrame.height ?? 1080
        window.setContentSize(NSSize(width: WINDOW_SIZE.width, height: min(WINDOW_SIZE.height, max(640, avail - 60))))
        window.socleCenter()
        model.window = window
        // Essais en arrière-plan : MO2FLATTENER_QUIET=1 lance l'appli sans prendre le focus
        let env = ProcessInfo.processInfo.environment
        if env["MO2FLATTENER_QUIET"] != nil {
            window.orderBack(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
        model.scheduleMac(now: true)  // l'annonce suit le jeu cible et l'instance

        if env["MO2FLATTENER_NOUPDATE"] == nil {
            UpdateEngine.shared.configure(repo: "mO2FLATTENER", lang: { I18n.lang })
            UpdateEngine.shared.canInstall = { [weak self] in !(self?.model.isRunning ?? false) }  // jamais pendant un aplatissement
            UpdateEngine.shared.start()  // nouvelle version ? (au plus une fois par jour)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { UpdateEngine.shared.installAppMenuItem() }
        }

        // Essais : MO2FLATTENER_MO2 / _MODLIST / _DEST préremplissent les champs ; MO2FLATTENER_KIT=1 choisit le kit DXMT, MO2FLATTENER_RUN=1 lance l'assemblage, MO2FLATTENER_UNDO=<id|all> annule ensuite.
        if let v = env["MO2FLATTENER_MO2"] { model.mo2Path = v; model.scanProfiles(v) }
        if let v = env["MO2FLATTENER_MODLIST"] { model.modlistPath = v }
        if let v = env["MO2FLATTENER_DEST"] { model.destPath = v }
        if let v = env["MO2FLATTENER_PLUGINS_DEST"] { model.pluginsDest = v }
        if let v = env["MO2FLATTENER_INIS_DEST"] { model.inisDest = v }
        if env["MO2FLATTENER_KIT"] != nil { model.kitSelected = true }
        if env["MO2FLATTENER_RUN"] != nil { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.model.start() } }
        // Vérification visuelle (développement) : MO2FLATTENER_SNAPSHOT=<fichier.png> enregistre la fenêtre après MO2FLATTENER_DELAY s (2 par défaut) et quitte.
        if let out = env["MO2FLATTENER_SNAPSHOT"] {
            let delay = Double(env["MO2FLATTENER_DELAY"] ?? "") ?? 2
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
                if let dump = env["MO2FLATTENER_DUMP"] {  // journal, statut et bilan (essais)
                    var text = model.log + "\n--- statut: " + model.statusText + "\n"
                    for i in model.report?.arr("items") ?? [] { text += "item \(i.str("id") ?? "") \(i.str("status") ?? "") undoable=\(i.flag("undoable"))\n" }
                    text += "mode=\(model.report?.str("mode") ?? "-") undone=\(model.report?.int("undone") ?? 0)\n"
                    try? text.write(toFile: dump, atomically: true, encoding: .utf8)
                }
                let view = window.contentView!
                if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
                }
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Fermer pendant la copie : arrêt propre du moteur.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.stopForQuit()
        return .terminateNow
    }

    // MARK: Langue

    @objc func chooseLanguage(_ sender: NSMenuItem) {
        let choice = LangChoice.normalize(sender.representedObject as? String)
        settings.set("language", choice)
        I18n.setLang(LangChoice.resolve(choice))
        window.title = windowTitle()
        model.retranslate()
        buildMenu()
        UpdateEngine.shared.insertMenuItem()
    }

    @objc func showAbout(_ sender: Any?) { About.show() }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        // Pas de couleur dans les menus : le nom de l'appli y est en texte normal
        let about = appMenu.addItem(withTitle: L("À propos de mO2FLATTENER"), action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("Masquer mO2FLATTENER"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = appMenu.addItem(withTitle: L("Masquer les autres"),
                                     action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: L("Tout afficher"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("Quitter mO2FLATTENER"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: L("Édition"))
        editMenu.addItem(withTitle: L("Couper"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L("Copier"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L("Coller"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L("Tout sélectionner"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        // Menu « Langue » : Automatique + 4 langues, coche sur le choix courant
        let langItem = NSMenuItem()
        let langMenu = NSMenu(title: L("Langue"))
        let current = LangChoice.normalize(settings.string("language", LangChoice.auto))
        func add(_ title: String, _ code: String) {
            let item = langMenu.addItem(withTitle: title, action: #selector(chooseLanguage), keyEquivalent: "")
            item.target = self
            item.representedObject = code
            item.state = code == current ? .on : .off
        }
        add(L("Automatique (système)"), LangChoice.auto)
        langMenu.addItem(.separator())
        for (code, label) in LangChoice.menuLangs { add(label, code) }
        langItem.submenu = langMenu
        main.addItem(langItem)

        let winItem = NSMenuItem()
        let winMenu = NSMenu(title: L("Fenêtre"))
        winMenu.addItem(withTitle: L("Réduire"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winItem.submenu = winMenu
        main.addItem(winItem)
        NSApp.mainMenu = main
        NSApp.windowsMenu = winMenu
    }
}

I18n.setLang(LangChoice.resolve(AppSettings(suite: ProcessInfo.processInfo.environment["MO2FLATTENER_SUITE"]).string("language", LangChoice.auto)))

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
