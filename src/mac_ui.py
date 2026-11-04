"""Interface de l'adaptation au Mac : carte « 3. Adaptation au Mac » (annonce avant l'assemblage) et carte
« Bilan Mac » (après), avec leurs petits threads. Le moteur est `mackit` (mac_adapt.py) ; tous les textes passent par
`tr(clé, **valeurs)` (I18nManager.t) : les cartes se redessinent dans la langue courante à partir de leurs données.
"""
from __future__ import annotations

import html
import os
import subprocess
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

from PyQt6.QtCore import QThread, QTimer, QUrl, Qt, pyqtSignal
from PyQt6.QtGui import QDesktopServices
from PyQt6.QtWidgets import (
    QCheckBox, QComboBox, QFrame, QHBoxLayout, QLabel, QPushButton, QScrollArea, QVBoxLayout, QWidget,
)

import mac_adapt
import socle_qt
from mo2_flattener_core import parse_modlist

Tr = Callable[..., str]
Json = Dict[str, Any]

MARGIN = 24  # Socle : 24 px de marge intérieure dans toute carte
LABEL_WIDTH = 190
TITLE_STYLE = "font-size: 12px; font-weight: bold; color: #38bdf8; letter-spacing: 0.5px;"
MONO = "font-family: Menlo, monospace; font-size: 11px;"


def esc(value: Any) -> str:
    return html.escape(str(value), quote=False)


def mackit_text(tr: Tr, obj: Optional[Json]) -> str:
    """Un texte {key, params} du moteur, dans la langue courante."""
    key, params = mac_adapt.text_of(obj)
    return tr(key, **params)


def _muted(text: str, size: int = 12) -> str:
    return f'<span style="color:{socle_qt.c("text-muted")};font-size:{size}px">{text}</span>'


def _rich_label(text: str = "", wrap: bool = True) -> QLabel:
    label = QLabel()
    label.setTextFormat(Qt.TextFormat.RichText)
    label.setWordWrap(wrap)
    label.setTextInteractionFlags(Qt.TextInteractionFlag.NoTextInteraction)
    label.setText(text)
    return label


def _row_frame() -> QFrame:
    frame = QFrame()
    frame.setObjectName("MacRow")
    frame.setStyleSheet(f"QFrame#MacRow {{ background-color: {socle_qt.c('bg-inset')}; border-radius: 5px; }}")
    return frame


def _clear(layout: QVBoxLayout) -> None:
    while layout.count():
        item = layout.takeAt(0)
        widget = item.widget()
        if widget is not None:
            widget.setParent(None)
            widget.deleteLater()


def _put(layout: QVBoxLayout, widget: QWidget) -> None:
    """Ajoute et affiche tout de suite : une ligne neuve est « cachée » pour la mise en page tant qu'elle n'est pas affichée."""
    layout.addWidget(widget)
    widget.show()


def _button(text: str, handler: Callable[[], None], width: Optional[int] = None) -> QPushButton:
    button = QPushButton(text)
    button.setObjectName("BrowseButton")
    button.setCursor(Qt.CursorShape.PointingHandCursor)
    button.setFixedHeight(34)
    if width:
        button.setMinimumWidth(width)
    button.clicked.connect(lambda _=False: handler())
    return button


# Les deux listes prennent toute la hauteur de leur contenu : c'est la page qui défile (Socle : « si elle dépasse, c'est la
# page qui défile »), pas la carte. Un plafond de 460/520 px coupait une ligne en bas et superposait deux barres de défilement.
NO_CAP = 100_000


class FitScroll(QScrollArea):
    """Zone qui prend la hauteur de son contenu jusqu'à `max_height`, puis défile : rien n'est tronqué."""

    def __init__(self, inner: QWidget, max_height: int):
        super().__init__()
        self._max = max_height
        self.setWidgetResizable(True)
        self.setFrameShape(QFrame.Shape.NoFrame)
        self.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        inner.setObjectName("MacInner")
        inner.setStyleSheet("QWidget#MacInner { background: transparent; }")
        self.setStyleSheet("QScrollArea { background: transparent; border: none; }")
        self.viewport().setAutoFillBackground(False)
        self.setWidget(inner)

    def fit(self) -> None:
        layout = self.widget().layout()
        layout.activate()
        width = self.viewport().width() or self.width()
        height = layout.totalHeightForWidth(width) if layout.hasHeightForWidth() else layout.totalSizeHint().height()
        self.setFixedHeight(max(0, min(self._max, height + 2)))

    def resizeEvent(self, event) -> None:  # noqa: N802 (Qt)
        super().resizeEvent(event)
        self.fit()


# ==============================================================================
# BOTTLED SHADERS (archive trouvée ou à télécharger) : commun aux deux cartes
# ==============================================================================

class BottledBlock(QFrame):
    """État de Bottled Shaders. Archive trouvée : « Afficher dans le Finder » ; sinon « à télécharger » et le lien de
    la page Nexus. mO2FLATTENER ne télécharge ni n'embarque rien."""

    def __init__(self, tr: Tr):
        super().__init__()
        self._tr = tr
        self._info: Optional[Json] = None
        self._shown_states = ("stock", "outdated", "unknown")
        self.setObjectName("MacRow")
        self.setStyleSheet(f"QFrame#MacRow {{ background-color: {socle_qt.c('bg-inset')}; border-radius: 5px; }}")
        lay = QVBoxLayout(self)
        lay.setContentsMargins(14, 12, 14, 12)
        lay.setSpacing(8)
        self.text = _rich_label()
        self.text.setAlignment(Qt.AlignmentFlag.AlignHCenter)
        lay.addWidget(self.text)
        self.hint = _rich_label()
        self.hint.setAlignment(Qt.AlignmentFlag.AlignHCenter)
        lay.addWidget(self.hint)
        buttons = QHBoxLayout()
        buttons.addStretch()
        self.btn = _button("", self._open)
        buttons.addWidget(self.btn)
        buttons.addStretch()
        lay.addLayout(buttons)
        self.hide()

    def set_info(self, info: Optional[Json], shown_states=("stock", "outdated", "unknown")) -> None:
        self._info = info
        self._shown_states = shown_states
        self.render()

    def render(self) -> None:
        info, tr = self._info, self._tr
        if not info or info.get("state") not in self._shown_states:
            self.hide()
            return
        archive = info.get("archive")
        head = f'<b style="color:{socle_qt.c("text-strong")}">{esc(tr("mac_bottled"))}</b><br>{_muted(esc(mackit_text(tr, info.get("text"))))}'
        action = info.get("state") in ("stock", "outdated", "unknown")  # « à jour » ne demande rien
        body = ""
        if not action:
            self.hint.hide()
            self.btn.hide()
        elif archive:
            body = tr("mac_bottled_found", name=archive["name"], folder=archive["folder"])
            self.hint.setText(_muted(esc(tr("mac_bottled_hint_found")), 11))
            self.hint.show()
            self.btn.setText(tr("mac_bottled_show"))
            self.btn.show()
        else:
            body = tr("mac_bottled_todo", minimum=info.get("minimum", mac_adapt.BOTTLED_MINIMUM))
            self.hint.setText(_muted(esc(tr("mac_bottled_hint")), 11))
            self.hint.show()
            self.btn.setText(tr("mac_bottled_open"))
            self.btn.show()
        self.text.setText(head + (f'<br><span style="font-size:12px">{esc(body)}</span>' if body else ""))
        self.show()

    def _open(self) -> None:
        info = self._info or {}
        archive = info.get("archive")
        if archive:
            subprocess.Popen(["open", "-R", archive["path"]])  # geste de l'utilisateur : Finder au premier plan
        else:
            QDesktopServices.openUrl(QUrl(info.get("page") or mac_adapt.BOTTLED_PAGE))


# ==============================================================================
# CARTE « 3. ADAPTATION AU MAC » (annonce)
# ==============================================================================

class MacAnnounceCard(QFrame):
    """Case cochée par défaut, bouteille CrossOver (détectée, modifiable) et ce que `mackit plan` annonce."""

    changed = pyqtSignal()  # l'utilisateur a coché la case ou choisi une autre bouteille

    def __init__(self, tr: Tr):
        super().__init__()
        self.setObjectName("CardFrame")
        self._tr = tr
        self._state: Json = {"kind": "loading"}
        self._bottles: List[Json] = []
        self._how: Optional[str] = None
        self.manual = False
        self.manual_choice: Optional[str] = None  # None : automatique ; "" : aucune bouteille ; sinon chemin

        lay = QVBoxLayout(self)
        lay.setContentsMargins(MARGIN, 20, MARGIN, 20)
        lay.setSpacing(12)

        self.title = QLabel()
        self.title.setStyleSheet(TITLE_STYLE)
        lay.addWidget(self.title)

        self.chk = QCheckBox()
        self.chk.setChecked(True)  # cochée par défaut, non mémorisée
        self.chk.toggled.connect(self._on_toggled)
        lay.addWidget(self.chk)

        self.intro = _rich_label()
        lay.addWidget(self.intro)

        self.bottle_box = QWidget()
        bl = QVBoxLayout(self.bottle_box)
        bl.setContentsMargins(0, 0, 0, 0)
        bl.setSpacing(4)
        row = QHBoxLayout()  # même grille que les lignes de la carte 1 : étiquette de 190 px, puis le champ
        self.lbl_bottle = QLabel()
        self.lbl_bottle.setFixedWidth(LABEL_WIDTH)
        self.lbl_bottle.setStyleSheet("font-size: 13px; font-weight: 500;")
        self.combo = QComboBox()
        self.combo.activated.connect(self._on_activated)
        row.addWidget(self.lbl_bottle)
        row.addWidget(self.combo, 1)
        bl.addLayout(row)
        hint_row = QHBoxLayout()
        gap = row.spacing() if row.spacing() >= 0 else self.style().pixelMetric(self.style().PixelMetric.PM_LayoutHorizontalSpacing)
        hint_row.setSpacing(0)
        hint_row.setContentsMargins(0, 0, 0, 0)
        hint_row.addSpacing(LABEL_WIDTH + gap)
        self.hint = _rich_label()
        hint_row.addWidget(self.hint, 1)
        bl.addLayout(hint_row)
        lay.addWidget(self.bottle_box)

        inner = QWidget()
        self.list_lay = QVBoxLayout(inner)
        self.list_lay.setContentsMargins(0, 0, 0, 0)
        self.list_lay.setSpacing(8)
        self.scroll = FitScroll(inner, NO_CAP)
        lay.addWidget(self.scroll)

        self.bottled = BottledBlock(tr)
        lay.addWidget(self.bottled)

        self.footer = _rich_label()
        lay.addWidget(self.footer)
        self.render()

    # --- accès pour la fenêtre -----------------------------------------------------
    def enabled(self) -> bool:
        return self.chk.isChecked()

    def selected_bottle(self) -> Optional[str]:
        data = self.combo.currentData()
        return data if data else None

    def set_bottles(self, bottles: List[Json], selected: Optional[str], how: Optional[str]) -> None:
        """Remplit la liste ; `selected` est la bouteille retenue (détectée ou choisie), `how` : detected/first/manual."""
        self._bottles, self._how = bottles, how
        self.combo.blockSignals(True)
        self.combo.clear()
        for bottle in bottles:
            self.combo.addItem(bottle["name"], bottle["path"])
        self.combo.addItem(self._tr("mac_bottle_none"), None)
        index = next((i for i, b in enumerate(bottles) if b["path"] == selected), len(bottles))
        self.combo.setCurrentIndex(index)
        self.combo.setEnabled(bool(bottles))
        self.combo.blockSignals(False)
        self._render_hint()

    def show_state(self, state: Json) -> None:
        self._state = state
        self.render()

    # --- événements ---------------------------------------------------------------
    def _on_toggled(self, _checked: bool) -> None:
        self.render()
        self.changed.emit()

    def _on_activated(self, _index: int) -> None:
        self.manual = True
        self.manual_choice = self.combo.currentData() or ""
        self._how = "manual"
        self._render_hint()
        self.changed.emit()

    # --- rendu --------------------------------------------------------------------
    def retranslate(self) -> None:
        none_index = self.combo.count() - 1
        if none_index >= 0 and self.combo.itemData(none_index) is None:
            self.combo.setItemText(none_index, self._tr("mac_bottle_none"))
        self.render()

    def _render_hint(self) -> None:
        tr = self._tr
        if not self._bottles:
            text = tr("mac_bottle_absent")
        else:
            text = {"detected": tr("mac_bottle_detected"), "first": tr("mac_bottle_first"),
                    "manual": tr("mac_bottle_manual")}.get(self._how or "", "")
        self.hint.setText(_muted(esc(text), 11))

    def _add_note(self, text: str, color: Optional[str] = None) -> None:
        label = _rich_label(f'<span style="color:{color or socle_qt.c("text-muted")}">{esc(text)}</span>')
        _put(self.list_lay, label)

    def _add_header(self, text: str) -> None:
        label = QLabel(text.upper())
        label.setIndent(0)
        label.setStyleSheet(f"font-size: 11px; font-weight: bold; color: {socle_qt.c('text-subtle')}; letter-spacing: 0.5px; padding-top: 4px;")
        _put(self.list_lay, label)

    def _add_fix(self, fix: Json) -> None:
        tr = self._tr
        frame = _row_frame()
        fl = QVBoxLayout(frame)
        fl.setContentsMargins(14, 10, 14, 10)
        fl.setSpacing(4)
        parts = [f'<b style="color:{socle_qt.c("text-strong")}">{esc(mackit_text(tr, fix["title"]))}</b>',
                 _muted(esc(mackit_text(tr, fix["detail"])))]
        files = [Path(f).name for f in fix.get("files", [])]
        if files:
            parts.append(_muted(f'{esc(tr("mac_files"))} : {esc(", ".join(files))}', 11))
        lines = [c.get("newLine") for c in (fix.get("changes") or []) if c.get("newLine")]
        if lines:
            parts.append(f'<span style="{MONO}color:{socle_qt.c("success-soft")}">' + "<br>".join(esc(l) for l in lines) + "</span>")
        fl.addWidget(_rich_label("<br>".join(parts)))
        _put(self.list_lay, frame)

    def _add_skipped(self, skip: Json) -> None:
        tr = self._tr
        title = mackit_text(tr, {"key": f"mackit.fix.{skip['id']}.title"})
        self._add_note(f"{title} — {mackit_text(tr, skip['reason'])}")

    def render(self) -> None:
        tr = self._tr
        self.title.setText(tr("card3_title"))
        self.chk.setText(tr("chk_mac"))
        self.intro.setText(_muted(esc(tr("mac_intro")), 12))
        self.lbl_bottle.setText(tr("lbl_bottle"))
        on = self.enabled()
        self.bottle_box.setVisible(on and self._state.get("kind") != "unavailable")
        self._render_hint()
        _clear(self.list_lay)
        kind = self._state.get("kind")
        show_bottled = False
        if not on:
            pass
        elif kind == "loading":
            self._add_note(tr("mac_loading"))
        elif kind == "unavailable":
            self._add_note(tr("mac_unavailable"), socle_qt.c("warning"))
        elif kind == "nodest":
            self._add_note(tr("mac_nodest"))
        elif kind == "error":
            self._add_note(tr("mac_plan_error", reason=mackit_text(tr, self._state.get("error"))), socle_qt.c("warning"))
        elif kind == "plan":
            plan = self._state["plan"]
            fixes, skipped, discarded = plan["fixes"], plan["skipped"], plan["discarded"]
            if self._state.get("previous"):
                self._add_note(tr("mac_previous", n=self._state["previous"]))
            if self._state.get("future"):
                self._add_note(tr("mac_future"))
            elif not fixes and not skipped and not discarded:
                self._add_note(tr("mac_nothing"))
            if fixes:
                self._add_header(tr("mac_will_do"))
                for fix in fixes:
                    self._add_fix(fix)
            if discarded:
                self._add_header(tr("mac_discarded_title"))
                for item in discarded:
                    self._add_note(f"{Path(item['file']).name} — {mackit_text(tr, item['reason'])}")
            if skipped:
                self._add_header(tr("mac_skipped_title"))
                for skip in skipped:
                    self._add_skipped(skip)
            show_bottled = True
        self.scroll.setVisible(self.list_lay.count() > 0)
        self.bottled.set_info(self._state.get("bottled") if show_bottled else None)
        if not on:
            self.footer.setText(_muted(esc(tr("mac_off")), 12))
        elif kind in ("plan", "nodest"):
            self.footer.setText(_muted(esc(tr("mac_promise")), 12))
        else:
            self.footer.setText("")
        self.footer.setVisible(bool(self.footer.text()))
        QTimer.singleShot(0, self.scroll.fit)  # les lignes neuves ne comptent qu'une fois affichées


# ==============================================================================
# CARTE « BILAN MAC » (après l'assemblage)
# ==============================================================================

class MacReportCard(QFrame):
    """Ce que l'adaptation a fait : état de chaque correctif, « Annuler » par ligne et « Tout annuler »."""

    undo_requested = pyqtSignal(str)  # identifiant du correctif, ou « all »

    def __init__(self, tr: Tr):
        super().__init__()
        self.setObjectName("CardFrame")
        self._tr = tr
        self._report: Optional[Json] = None
        self._busy = False
        lay = QVBoxLayout(self)
        lay.setContentsMargins(MARGIN, 20, MARGIN, 20)
        lay.setSpacing(12)
        self.title = QLabel()
        self.title.setStyleSheet(TITLE_STYLE)
        lay.addWidget(self.title)
        self.summary = _rich_label()
        lay.addWidget(self.summary)
        inner = QWidget()
        self.rows = QVBoxLayout(inner)
        self.rows.setContentsMargins(0, 0, 0, 0)
        self.rows.setSpacing(8)
        self.scroll = FitScroll(inner, NO_CAP)
        lay.addWidget(self.scroll)
        self.bottled = BottledBlock(tr)
        lay.addWidget(self.bottled)
        undo_row = QHBoxLayout()
        undo_row.addStretch()
        self.btn_all = _button("", lambda: self._request("all"), 160)
        undo_row.addWidget(self.btn_all)
        undo_row.addStretch()
        lay.addLayout(undo_row)
        self.note = _rich_label()
        self.note.setAlignment(Qt.AlignmentFlag.AlignHCenter)
        lay.addWidget(self.note)
        self._buttons: List[QPushButton] = []
        self.hide()

    def report(self) -> Optional[Json]:
        return self._report

    def show_report(self, report: Json) -> None:
        self._report = report
        self._busy = False
        self.render()
        self.show()

    def set_busy(self, busy: bool) -> None:
        self._busy = busy
        self.render()

    def retranslate(self) -> None:
        if self._report is not None:
            self.render()

    def _request(self, target: str) -> None:
        if not self._busy:
            self.undo_requested.emit(target)

    def _status_style(self, status: str) -> str:
        color = {"applied": "success", "failed": "danger", "skipped": "warning"}[status]
        return f"font-size: 12px; font-weight: bold; color: {socle_qt.c(color)};"

    def _add_item(self, item: Json) -> None:
        tr = self._tr
        frame = _row_frame()
        row = QHBoxLayout(frame)
        row.setContentsMargins(14, 10, 14, 10)
        row.setSpacing(14)
        chip = QLabel(tr({"applied": "rep_applied", "failed": "rep_failed", "skipped": "rep_skipped"}[item["status"]]))
        chip.setFixedWidth(84)
        chip.setAlignment(Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignTop)
        chip.setStyleSheet(self._status_style(item["status"]))
        row.addWidget(chip)
        parts = [f'<b style="color:{socle_qt.c("text-strong")}">{esc(mackit_text(tr, item["title"]))}</b>']
        if item["status"] == "skipped":
            parts.append(_muted(esc(mackit_text(tr, item.get("reason")))))
        elif item["status"] == "failed":
            if item.get("text"):
                parts.append(f'<span style="color:{socle_qt.c("danger-soft")};font-size:12px">{esc(mackit_text(tr, item["text"]))}</span>')
            parts.append(_muted(esc(mackit_text(tr, item.get("detail")))))
        else:
            parts.append(_muted(esc(mackit_text(tr, item.get("detail")))))
        files = [Path(f).name for f in item.get("files", [])]
        if files:
            parts.append(_muted(f'{esc(tr("mac_files"))} : {esc(", ".join(files))}', 11))
        if item.get("refusal"):
            parts.append(f'<span style="color:{socle_qt.c("warning")};font-size:12px">{esc(tr("rep_refused"))} : {esc(mackit_text(tr, item["refusal"]))}</span>')
        text = _rich_label("<br>".join(parts))
        row.addWidget(text, 1)
        if item.get("undoable"):
            button = _button(tr("rep_undo"), lambda i=item["id"]: self._request(i), 100)
            button.setEnabled(not self._busy)
            self._buttons.append(button)
            row.addWidget(button, 0, Qt.AlignmentFlag.AlignTop)
        _put(self.rows, frame)

    def render(self) -> None:
        report, tr = self._report, self._tr
        self.title.setText(tr("rep_title"))
        if report is None:
            return
        _clear(self.rows)
        self._buttons = []
        items = report.get("items", [])
        for item in items:
            self._add_item(item)
        self.scroll.setVisible(bool(items))
        applied_left = any(i["status"] == "applied" for i in items)
        undoable = any(i.get("undoable") for i in items)
        if self._busy:
            summary, color = tr("rep_undoing"), "text-muted"
        elif report.get("error"):
            summary, color = tr("rep_error"), "danger-soft"
        elif report.get("unavailable"):
            summary, color = tr("mac_unavailable"), "warning"
        elif report.get("undone") and not applied_left:
            summary, color = tr("rep_all_undone"), "success-soft"
        elif not items:
            summary, color = tr("rep_nothing"), "text-muted"
        else:
            summary, color = tr("rep_done"), "text"
        self.summary.setText(f'<span style="color:{socle_qt.c(color)}">{esc(summary)}</span>')
        self.bottled.set_info(report.get("bottled"), ("stock", "outdated", "unknown", "ok"))
        self.btn_all.setText(tr("rep_undo_all"))
        self.btn_all.setVisible(undoable)
        self.btn_all.setEnabled(not self._busy)
        notes = []
        if report.get("undone") and applied_left:
            notes.append(tr("rep_undone", n=report["undone"]))
        if applied_left:
            notes.append(tr("rep_backup_note"))
        self.note.setText(_muted(esc(" ".join(notes)), 11))
        self.note.setVisible(bool(notes))
        QTimer.singleShot(0, self.scroll.fit)  # les lignes neuves ne comptent qu'une fois affichées


# ==============================================================================
# THREADS (l'outil `mackit` est lancé hors du fil de l'interface)
# ==============================================================================

class MacPlanWorker(QThread):
    """Annonce : bouteilles, bouteille retenue et `mackit plan` sur le jeu cible."""

    done = pyqtSignal(object)

    def __init__(self, seq: int, dest: str, mo2_dir: str, modlist: str, choice: Optional[str], parent=None):
        super().__init__(parent)
        self.seq, self.dest, self.mo2_dir, self.modlist, self.choice = seq, dest.strip(), mo2_dir.strip(), modlist.strip(), choice

    def run(self) -> None:
        out: Json = {"seq": self.seq, "bottles": [], "bottle": None, "how": None, "state": {"kind": "unavailable"}}
        try:
            if mac_adapt.mackit_path() is None:
                self.done.emit(out)
                return
            bottles = mac_adapt.list_bottles()
            if self.choice is None:
                bottle, how = mac_adapt.detect_bottle(bottles, self.dest or None)
            elif self.choice == "":
                bottle, how = None, "manual"
            else:
                bottle = next((b for b in bottles if b["path"] == self.choice), None)
                how = "manual"
                if bottle is None:
                    bottle, how = mac_adapt.detect_bottle(bottles, self.dest or None)
            out.update(bottles=bottles, bottle=bottle["path"] if bottle else None, how=how)
            if not self.dest:
                out["state"] = {"kind": "nodest"}
            else:
                mods: List[str] = []
                mo2 = Path(self.mo2_dir) if self.mo2_dir else None
                if mo2 and mo2.is_dir() and self.modlist and Path(self.modlist).is_file():
                    mods = parse_modlist(Path(self.modlist))
                out["state"] = mac_adapt.preview(Path(self.dest), out["bottle"], mo2 if mo2 and mo2.is_dir() else None, mods)
        except Exception as err:  # l'annonce n'est jamais bloquante
            out["state"] = {"kind": "error", "error": {"key": "mackit.cli.error"}, "detail": str(err)}
        self.done.emit(out)


class MacUndoWorker(QThread):
    """`mackit undo <id|all>` sur le jeu assemblé."""

    done = pyqtSignal(object)

    def __init__(self, game: str, target: str, parent=None):
        super().__init__(parent)
        self.game, self.target = game, target

    def run(self) -> None:
        try:
            result = mac_adapt.undo(Path(self.game), self.target)
        except Exception as err:
            result = {"ok": False, "error": {"text": {"key": "mackit.cli.error"}, "detail": str(err)}}
        self.done.emit(result)
