// Interface : en-tête, cartes 1 (instance), 2 (configurations), 3 (adaptation au Mac), actions, progression, journal, bilan Mac.

import AppKit
import FlattenCore
import SwiftUI

let WINDOW_SIZE = CGSize(width: 1180, height: 900)

private func fname(_ path: Any?) -> String { pyName((path as? String) ?? "") }

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        let _ = model.tick
        VStack(spacing: Socle.M.space4) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: Socle.M.space4) {
                        card1
                        card2
                        MacAnnounceCard(model: model)
                        actions
                        ProgressView(value: Double(model.progress), total: 100)
                            .progressViewStyle(.linear).tint(Socle.C.action)
                        logCard
                        if model.report != nil { MacReportCard(model: model) }
                        Color.clear.frame(height: 1).id("end")
                    }
                }
                .scrollIndicators(.automatic)
                .onChange(of: model.scrollToEnd) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
                }
            }
        }
        .padding(.horizontal, Socle.M.space4).padding(.vertical, Socle.M.space3)
        .frame(minWidth: 1100, minHeight: 640)
        .background(Socle.C.bg)
    }

    // MARK: En-tête

    private var header: some View {
        HStack(spacing: Socle.M.space3) {
            Text("⚡").font(.system(size: 22, weight: .bold)).foregroundStyle(Socle.C.action)
            Text(branded: T("app_title")).socle(Socle.T.display).foregroundStyle(Socle.C.textStrong).lineLimit(1)
            Spacer(minLength: 0)
            Text(model.statusText).socle(Socle.T.label).foregroundStyle(Socle.C.textMuted).lineLimit(1)
        }
        .padding(.horizontal, 18).frame(height: 56)
        .background(Socle.C.surface, in: RoundedRectangle(cornerRadius: Socle.M.radiusMd))
    }

    // MARK: Cartes 1 et 2

    private var card1: some View {
        Card {
            CardTitle(T("card1_title"))
            FieldRow(label: T("lbl_mo2"), text: $model.mo2Path, placeholder: T("ph_mo2"), browse: model.browseMO2)
                .onSubmit { model.scanProfiles(model.mo2Path) }
            HStack(spacing: Socle.M.space2) {
                Text(T("lbl_prof")).socle(Socle.T.label).frame(width: 190, alignment: .leading)
                Picker("", selection: $model.profile) {
                    ForEach(model.profiles, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
            }
            FieldRow(label: T("lbl_modl"), text: $model.modlistPath, placeholder: "", browse: model.browseModlist)
            FieldRow(label: T("lbl_dest"), text: $model.destPath, placeholder: T("ph_dest"), browse: { model.chooseFolder("lbl_dest") { model.destPath = $0 } })
            Toggle(T("chk_hardlinks"), isOn: $model.useHardlinks).toggleStyle(.checkbox).socle(Socle.T.body)
            Toggle(T("chk_stop_on_error"), isOn: $model.stopOnError).toggleStyle(.checkbox).socle(Socle.T.body)
        }
        .disabled(model.isRunning)
    }

    private var card2: some View {
        Card {
            CardTitle(T("card2_title"))
            HStack(spacing: Socle.M.space2) {
                Toggle(T("chk_plugins"), isOn: $model.copyPlugins).toggleStyle(.checkbox).socle(Socle.T.label).frame(width: 240, alignment: .leading)
                TextField("", text: $model.pluginsDest).socleField().disabled(!model.copyPlugins)
                BrowseButton(action: { model.chooseFolder("chk_plugins") { model.pluginsDest = $0 } }).disabled(!model.copyPlugins)
            }
            HStack(spacing: Socle.M.space2) {
                Toggle(T("chk_inis"), isOn: $model.copyInis).toggleStyle(.checkbox).socle(Socle.T.label).frame(width: 240, alignment: .leading)
                TextField("", text: $model.inisDest).socleField().disabled(!model.copyInis)
                BrowseButton(action: { model.chooseFolder("chk_inis") { model.inisDest = $0 } }).disabled(!model.copyInis)
            }
        }
        .disabled(model.isRunning)
    }

    // MARK: Actions, journal

    private var actions: some View {
        HStack(spacing: Socle.M.space3) {
            Spacer()
            Button(T("btn_run")) { model.start() }
                .buttonStyle(SocleButtonStyle(.action)).fixedSize().disabled(model.isRunning)
            Button(T("btn_stop")) { model.stop() }
                .buttonStyle(SocleButtonStyle(.secondary)).fixedSize().disabled(model.run != .running)
            Spacer()
        }
    }

    private var logCard: some View {
        Card(padding: 16) {
            Text(T("log_title")).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textMuted)
            ScrollView {
                Text(model.log).socle(Socle.T.mono).foregroundStyle(Socle.C.text)
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding(10)
            }
            .frame(minHeight: 170, maxHeight: 260)
            .background(Socle.C.bg, in: RoundedRectangle(cornerRadius: Socle.M.radius))
            .defaultScrollAnchor(.bottom)
        }
    }
}

// MARK: Briques

struct Card<Content: View>: View {
    var padding: CGFloat = 24
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: Socle.M.space3) { content }
            .padding(.horizontal, padding).padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Socle.C.surface, in: RoundedRectangle(cornerRadius: Socle.M.radiusMd))
    }
}

struct CardTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.accentText) }
}

struct BrowseButton: View {
    let action: () -> Void
    var body: some View {
        Button(T("btn_browse"), action: action).buttonStyle(SocleButtonStyle(.tertiary)).frame(width: 110)
    }
}

struct FieldRow: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    let browse: () -> Void
    var body: some View {
        HStack(spacing: Socle.M.space2) {
            Text(label).socle(Socle.T.label).frame(width: 190, alignment: .leading)
            TextField(placeholder, text: $text).socleField()
            BrowseButton(action: browse)
        }
    }
}

func muted(_ s: String, _ style: Socle.TextStyle = Socle.T.body) -> some View {
    Text(branded: s).socle(style).foregroundStyle(Socle.C.textMuted).fixedSize(horizontal: false, vertical: true)
}

func eyebrow(_ s: String) -> some View {
    Text(s.uppercased()).socle(Socle.T.meta).fontWeight(.bold).tracking(0.5).foregroundStyle(Socle.C.textSubtle)
}

struct Row<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Socle.C.bgInset, in: RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: Carte 3 : adaptation au Mac (annonce)

struct ModeOption: View {
    let title: String
    let lead: String
    let rows: [(String, String)]
    var notice = ""
    let selected: Bool
    let enabled: Bool
    let choose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: selected ? "circle.inset.filled" : "circle")
                    .foregroundStyle(selected ? Socle.C.accent : Socle.C.borderControl)
                Text(title).socle(Socle.T.label).fontWeight(.semibold).foregroundStyle(Socle.C.textStrong)
            }
            VStack(alignment: .leading, spacing: 8) {
                muted(lead)
                Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 6) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                        GridRow {
                            eyebrow(r.0).frame(width: 160, alignment: .leading)
                            muted(r.1)
                        }
                    }
                }
                if !notice.isEmpty {
                    Text("⚠ " + notice).socle(Socle.T.body).foregroundStyle(Socle.C.warning).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(.leading, 26)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Socle.C.bgInset, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Socle.C.accent : Socle.C.borderSubtle, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { if enabled { choose() } }
        .opacity(enabled ? 1 : 0.9)
    }
}

struct MacAnnounceCard: View {
    @Bindable var model: AppModel

    var body: some View {
        let kind = model.macState.str("kind") ?? "loading"
        let kitOff = !model.kitAvailable()
        let on = model.macMode() == "crossover"
        let rowIds = [("mac_row_folder", "folder"), ("mac_row_bottle", "bottle"), ("mac_row_after", "after"), ("mac_row_undo", "undo")]
        Card {
            CardTitle(T("card3_title"))
            muted(T("mac_mode_choose"), Socle.T.body)
            ModeOption(title: T("mac_mode_stock"), lead: T("mac_mode_stock_lead"),
                       rows: rowIds.map { (T($0.0), T("mac_mode_stock_\($0.1)")) }, selected: !on, enabled: true) { model.setKit(false) }
            ModeOption(title: T("mac_mode_kit"), lead: T("mac_mode_kit_lead"),
                       rows: rowIds.map { (T($0.0), T("mac_mode_kit_\($0.1)")) },
                       notice: kitOff && (model.bottlesKnown || kind == "unavailable") ? T("mac_kit_unavailable") : "",
                       selected: on, enabled: !kitOff) { model.setKit(true) }
            if on && kind != "unavailable" { bottlePicker }
            if on { details(kind) }
            if on && (kind == "plan" || kind == "nodest") { muted(T("mac_promise")) }
        }
        .disabled(model.isRunning)
    }

    private var bottlePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Socle.M.space2) {
                Text(T("lbl_bottle")).socle(Socle.T.label).frame(width: 190, alignment: .leading)
                Picker("", selection: Binding(get: { model.selectedBottle ?? "" }, set: { model.chooseBottle($0) })) {
                    ForEach(Array(model.bottles.enumerated()), id: \.offset) { _, b in Text(b.str("name") ?? "").tag(b.str("path") ?? "") }
                }.labelsHidden().disabled(model.bottles.count <= 1).frame(maxWidth: .infinity, alignment: .leading)
            }
            let hint = model.bottles.isEmpty ? "" : ["detected": T("mac_bottle_detected"), "first": T("mac_bottle_first"), "manual": T("mac_bottle_manual")][model.bottleHow ?? ""] ?? ""
            if !hint.isEmpty { muted(hint, Socle.T.meta).padding(.leading, 190 + Socle.M.space2) }
        }
    }

    @ViewBuilder private func details(_ kind: String) -> some View {
        switch kind {
        case "loading": note(T("mac_loading"))
        case "unavailable": note(T("mac_unavailable"), Socle.C.warning)
        case "nobottle": note(T("mac_kit_unavailable"), Socle.C.warning)
        case "nodest": note(T("mac_nodest"))
        case "error": note(T("mac_plan_error", ["reason": MacAdapt.text(model.macState["error"])]), Socle.C.warning)
        case "plan": planView
        default: EmptyView()
        }
    }

    private func note(_ s: String, _ color: Color = Socle.C.textMuted) -> some View {
        Text(branded: s).socle(Socle.T.body).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var planView: some View {
        let plan = model.macState.obj("plan") ?? [:]
        let fixes = plan.arr("fixes"), skipped = plan.arr("skipped"), discarded = plan.arr("discarded")
        let okIds = (plan["ok"] as? [String]) ?? []
        let previous = model.macState.int("previous")
        if previous > 0 { note(T("mac_previous", ["n": previous])) }
        if model.macState.flag("future") { note(T("mac_future")) }
        else if fixes.isEmpty && skipped.isEmpty && discarded.isEmpty && previous == 0 { note(T("mac_nothing")) }
        if !fixes.isEmpty {
            eyebrow(T("mac_will_do"))
            ForEach(Array(fixes.enumerated()), id: \.offset) { _, f in fixView(f) }
        }
        if !discarded.isEmpty {
            eyebrow(T("mac_discarded_title"))
            ForEach(Array(discarded.enumerated()), id: \.offset) { _, d in note("\(fname(d["file"])) — \(MacAdapt.text(d["reason"]))") }
        }
        if !skipped.isEmpty {
            eyebrow(T("mac_skipped_title"))
            ForEach(Array(skipped.enumerated()), id: \.offset) { _, s in
                note("\(T("mackit.fix.\(s.str("id") ?? "").title")) — \(MacAdapt.text(s["reason"]))")
            }
        }
        if !okIds.isEmpty {
            eyebrow(T("mac_ok_title"))
            ForEach(okIds, id: \.self) { id in
                HStack(spacing: 6) { Text("✓").foregroundStyle(Socle.C.successSoft); Text(T("mac_ok_\(id)")).foregroundStyle(Socle.C.textMuted) }.socle(Socle.T.body)
            }
        }
        BottledBlock(info: model.macState.obj("bottled"), shown: ["stock", "outdated", "unknown"])
    }

    private func fixView(_ fix: Json) -> some View {
        Row {
            VStack(alignment: .leading, spacing: 4) {
                Text(MacAdapt.text(fix["title"])).socle(Socle.T.body).fontWeight(.bold).foregroundStyle(Socle.C.textStrong)
                muted(MacAdapt.text(fix["detail"]))
                let files = ((fix["files"] as? [Any]) ?? []).map { fname($0) }
                if !files.isEmpty { muted("\(T("mac_files")) : \(files.joined(separator: ", "))", Socle.T.meta) }
                let lines = fix.arr("changes").compactMap { $0.str("newLine") }.filter { !$0.isEmpty }
                if !lines.isEmpty {
                    Text(lines.joined(separator: "\n")).socle(Socle.T.monoSm).foregroundStyle(Socle.C.successSoft)
                }
            }
        }
    }
}

// MARK: Bottled Shaders (archive trouvée ou à télécharger)

struct BottledBlock: View {
    let info: Json?
    let shown: [String]

    var body: some View {
        if let info, shown.contains(info.str("state") ?? "") {
            let archive = info.obj("archive")
            let action = ["stock", "outdated", "unknown"].contains(info.str("state") ?? "")
            Row {
                VStack(spacing: 8) {
                    VStack(spacing: 2) {
                        Text(T("mac_bottled")).socle(Socle.T.body).fontWeight(.bold).foregroundStyle(Socle.C.textStrong)
                        muted(MacAdapt.text(info["text"]))
                        if action {
                            let body = archive != nil
                                ? T("mac_bottled_found", ["name": archive!.str("name") ?? "", "folder": archive!.str("folder") ?? ""])
                                : T("mac_bottled_todo", ["minimum": info.str("minimum") ?? MacAdapt.bottledMinimum])
                            muted(body)
                        }
                    }.multilineTextAlignment(.center)
                    if action {
                        muted(archive != nil ? T("mac_bottled_hint_found") : T("mac_bottled_hint"), Socle.T.meta).multilineTextAlignment(.center)
                        Button(archive != nil ? T("mac_bottled_show") : T("mac_bottled_open")) {
                            if let archive, let p = archive.str("path") {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)])  // geste de l'utilisateur
                            } else if let url = URL(string: info.str("page") ?? MacAdapt.bottledPage) {
                                NSWorkspace.shared.open(url)
                            }
                        }.buttonStyle(SocleButtonStyle(.tertiary)).fixedSize()
                    }
                }.frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: Bilan Mac

struct MacReportCard: View {
    @Bindable var model: AppModel

    var body: some View {
        let report = model.report ?? [:]
        let stock = report.str("mode") == "stock"
        let items = report.arr("items")
        let appliedLeft = items.contains { $0.str("status") == "applied" }
        let undoable = items.contains { $0.flag("undoable") }
        let (summary, color): (String, Color) = {
            if stock { return (T("rep_stock_text"), Socle.C.successSoft) }
            if model.undoBusy { return (T("rep_undoing"), Socle.C.textMuted) }
            if report.flag("no_bottle") { return (T("rep_no_bottle"), Socle.C.warning) }
            if report["error"] is Json { return (T("rep_error"), Socle.C.dangerSoft) }
            if report.flag("unavailable") { return (T("mac_unavailable"), Socle.C.warning) }
            if report.int("undone") > 0 && !appliedLeft { return (T("rep_all_undone"), Socle.C.successSoft) }
            if items.isEmpty { return (T("rep_nothing"), Socle.C.textMuted) }
            return (T("rep_done"), Socle.C.text)
        }()
        Card {
            CardTitle(T(stock ? "rep_stock_title" : "rep_title"))
            Text(branded: summary).socle(Socle.T.body).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in itemRow(item) }
            BottledBlock(info: report.obj("bottled"), shown: ["stock", "outdated", "unknown", "ok"])
            if undoable {
                HStack { Spacer()
                    Button(T("rep_undo_all")) { model.undo("all") }.buttonStyle(SocleButtonStyle(.tertiary)).fixedSize().disabled(model.undoBusy)
                    Spacer() }
            }
            let notes = [report.int("undone") > 0 && appliedLeft ? T("rep_undone", ["n": report.int("undone")]) : nil,
                         appliedLeft ? T("rep_backup_note") : nil].compactMap { $0 }
            if !notes.isEmpty { muted(notes.joined(separator: " "), Socle.T.meta).frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center) }
        }
    }

    private func itemRow(_ item: Json) -> some View {
        let status = item.str("status") ?? "applied"
        let chip = ["applied": "rep_applied", "failed": "rep_failed", "skipped": "rep_skipped"][status] ?? "rep_applied"
        let chipColor = ["applied": Socle.C.success, "failed": Socle.C.danger, "skipped": Socle.C.warning][status] ?? Socle.C.success
        return Row {
            HStack(alignment: .top, spacing: 14) {
                Text(T(chip)).socle(Socle.T.body).fontWeight(.bold).foregroundStyle(chipColor).frame(width: 84, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text(MacAdapt.text(item["title"])).socle(Socle.T.body).fontWeight(.bold).foregroundStyle(Socle.C.textStrong)
                    if status == "skipped" { muted(MacAdapt.text(item["reason"])) }
                    else if status == "failed" {
                        if item["text"] is Json { Text(MacAdapt.text(item["text"])).socle(Socle.T.body).foregroundStyle(Socle.C.dangerSoft) }
                        muted(MacAdapt.text(item["detail"]))
                    } else { muted(MacAdapt.text(item["detail"])) }
                    let files = ((item["files"] as? [Any]) ?? []).map { fname($0) }
                    if !files.isEmpty { muted("\(T("mac_files")) : \(files.joined(separator: ", "))", Socle.T.meta) }
                    if item["refusal"] is Json {
                        Text("\(T("rep_refused")) : \(MacAdapt.text(item["refusal"]))").socle(Socle.T.body).foregroundStyle(Socle.C.warning)
                    }
                }
                Spacer(minLength: 0)
                if item.flag("undoable") {
                    Button(T("rep_undo")) { model.undo(item.str("id") ?? "") }
                        .buttonStyle(SocleButtonStyle(.tertiary)).fixedSize().disabled(model.undoBusy)
                }
            }
        }
    }
}
