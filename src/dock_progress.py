"""Jauge de progression dans l'icône du Dock (macOS) pour les applis PyQt6.

Pendant un travail long, l'icône de l'appli reçoit une barre de progression et un pourcentage ;
`clear()` rend l'icône d'origine. Ailleurs que sur macOS, ne fait rien.
"""

import sys
from pathlib import Path

from PyQt6.QtCore import Qt, QRectF
from PyQt6.QtGui import QColor, QFont, QIcon, QPainter, QPixmap

SIZE = 512
FILL = "#e5483a"  # couleur du logo


def _base_icon() -> QIcon:
    """Icône de l'appli : celle du paquet .app compilé, sinon assets/icon.png du projet."""
    if getattr(sys, "frozen", False):
        resources = Path(sys.executable).resolve().parent.parent / "Resources"
        for icns in sorted(resources.glob("*.icns")):
            return QIcon(str(icns))
    png = Path(__file__).resolve().parent.parent / "assets" / "icon.png"
    return QIcon(str(png)) if png.exists() else QIcon()


class DockProgress:
    def __init__(self, app, fill: str = FILL):
        self._app = app
        self._fill = QColor(fill)
        self._base = _base_icon()
        self._last = None
        self._enabled = sys.platform == "darwin" and not self._base.isNull()

    def set(self, percent: int):
        percent = max(0, min(100, int(percent)))
        if not self._enabled or percent == self._last:
            return
        self._last = percent
        pm = self._base.pixmap(SIZE, SIZE)
        p = QPainter(pm)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)

        # Pastille du pourcentage, en haut à droite
        p.setPen(Qt.PenStyle.NoPen)
        p.setBrush(QColor(0, 0, 0, 200))
        badge = QRectF(SIZE * 0.42, SIZE * 0.04, SIZE * 0.56, SIZE * 0.26)
        p.drawRoundedRect(badge, badge.height() / 2, badge.height() / 2)
        font = QFont()
        font.setPixelSize(int(SIZE * 0.17))
        font.setBold(True)
        p.setFont(font)
        p.setPen(QColor("#ffffff"))
        p.drawText(badge, Qt.AlignmentFlag.AlignCenter, f"{percent} %")

        # Barre de progression, en bas
        track = QRectF(SIZE * 0.08, SIZE * 0.82, SIZE * 0.84, SIZE * 0.11)
        radius = track.height() / 2
        p.setPen(Qt.PenStyle.NoPen)
        p.setBrush(QColor(0, 0, 0, 200))
        p.drawRoundedRect(track, radius, radius)
        inner = track.adjusted(6, 6, -6, -6)
        if percent > 0:
            done = QRectF(inner.left(), inner.top(), max(inner.height(), inner.width() * percent / 100), inner.height())
            p.setBrush(self._fill)
            p.drawRoundedRect(done, inner.height() / 2, inner.height() / 2)
        p.end()
        self._app.setWindowIcon(QIcon(pm))

    def clear(self):
        if self._enabled and self._last is not None:
            self._last = None
            self._app.setWindowIcon(self._base)
