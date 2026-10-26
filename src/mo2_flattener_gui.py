#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
================================================================================
        MO2 INSTANCE FLATTENER v1.7 - SCRIPT PYTHON AUTONOME (PyQt6)
================================================================================
Moteur haute performance optimisé :
- Grand titre d'application mis en valeur en haut à gauche (corps 20pt gras).
- Journal des opérations entièrement traduit (FR, EN, IT, ES).
- Filtre d'exclusion systématique des fichiers .pdb, .mohidden, doc et résidus.
- Résolution en RAM des conflits de mods (Two-Pass Assembly).
- Copie parallèle multi-threadée (ThreadPoolExecutor).
- Bouton d'interruption immédiate en cours de copie.
- Option d'arrêt automatique sur détection d'erreur.
- Séparation stricte : Racine du jeu (Root / STOCK GAME) vs dossier Data.
================================================================================
"""

import sys
import os
import shutil
import concurrent.futures
from pathlib import Path
from typing import List, Dict, Tuple

import socle_qt

try:
    from PyQt6.QtWidgets import (
        QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
        QLabel, QPushButton, QFrame, QFileDialog, QMessageBox, QComboBox,
        QTextEdit, QLineEdit, QCheckBox, QProgressBar
    )
    from PyQt6.QtCore import Qt, QThread, pyqtSignal, QSettings
    from PyQt6.QtGui import QFont
except ImportError as err:
    sys.stderr.write(
        f"ERREUR : Bibliothèque PyQt6 manquante ({err}).\n"
        "Installez-la dans votre environnement via : pip install PyQt6\n"
    )
    sys.exit(1)

from mo2_flattener_core import build_tasks, optimized_copy_file

# ==============================================================================
# INTERNATIONALISATION (i18n) - FR, EN, IT, ES
# ==============================================================================

AVAILABLE_LANGUAGES = [
    ("fr", "Français", "🇫🇷"),
    ("en", "English", "🇬🇧"),
    ("it", "Italiano", "🇮🇹"),
    ("es", "Español", "🇪🇸"),
]

TRANSLATIONS: Dict[str, Dict[str, str]] = {
    "fr": {
        "app_title": "mO2FLATTENER · Assembleur d'Instance Mod Organizer 2",
        "header_status_idle": "Skyrim SE/AE • En attente de configuration",
        "header_status_indexing": "Skyrim SE/AE • Analyse des priorités en RAM...",
        "header_status_running": "Skyrim SE/AE • Assemblage accéléré en cours...",
        "header_status_done": "Skyrim SE/AE • Assemblage terminé",
        "header_status_stopped": "Skyrim SE/AE • Assemblage interrompu",
        "header_status_error": "Skyrim SE/AE • Erreur rencontrée",
        "card1_title": "1. INSTANCE SOURCE & RÉPERTOIRE DU JEU (RACINE)",
        "lbl_mo2": "Dossier MO2 / MODS :",
        "ph_mo2": "Sélectionnez le dossier MODS ou la racine de MO2...",
        "lbl_prof": "Profil MO2 :",
        "lbl_modl": "Fichier modlist.txt :",
        "lbl_dest": "Racine du jeu cible :",
        "ph_dest": "Ex : /chemin/vers/Skyrim Special Edition",
        "btn_browse": "Parcourir",
        "chk_hardlinks": "Hors APFS, utiliser des liens physiques (Hardlinks) — Décoché = Copie complète. Sur APFS, copie instantanée sans place en plus.",
        "chk_stop_on_error": "Arrêter immédiatement l'assemblage en cas d'erreur de copie",
        "card2_title": "2. DÉPLOIEMENT DES CONFIGURATIONS DU JEU",
        "chk_plugins": "Copier plugins.txt (AppData) :",
        "chk_inis": "Copier INIs (Documents) :",
        "btn_run": "📦  LANCER L'ASSEMBLAGE COMPLET",
        "btn_stop": "🛑  INTERROMPRE L'ASSEMBLAGE",
        "log_title": "JOURNAL DES OPÉRATIONS",
        "warn_no_profiles": "[AVERTISSEMENT] Aucun dossier 'profiles' détecté dans",
        "err_title": "Erreur",
        "err_mo2_invalid": "Le dossier MO2 ou MODS spécifié est introuvable.",
        "err_modlist_invalid": "Le fichier modlist.txt spécifié est introuvable.",
        "err_dest_empty": "Veuillez définir le dossier racine de destination du jeu.",
        "err_plugins_dest": "Veuillez définir le dossier de destination pour plugins.txt.",
        "err_inis_dest": "Veuillez définir le dossier de destination pour les fichiers INI.",
        "success_title": "Succès",
        "success_msg": "L'assemblage complet du jeu s'est terminé avec succès !",
        "stop_msg": "L'assemblage a été interrompu par l'utilisateur.",
        # Messages de journalisation
        "log_analyzing": "[*] Analyse de l'ordre de priorité : {name}",
        "log_root_dir": "[*] Dossier racine : {path}",
        "log_data_dir": "[*] Dossier Data   : {path}",
        "log_filters": "[*] Filtres actifs : exclusion des .pdb, .mohidden et dossiers inertes",
        "log_indexing_ram": "[*] Indexation rapide en mémoire des fichiers uniques...",
        "log_indexing_stock": "    Indexation de STOCK GAME : {name}",
        "log_index_complete": "[*] Indexation terminée : {total} fichiers finaux uniques à déployer.",
        "log_copy_start": "[*] Démarrage de la copie optimisée multi-thread...",
        "log_progress": "    [{current}/{total}] fichiers déployés...",
        "log_copy_err": "[ERREUR] Échec copie {src} -> {dst} : {err}",
        "log_copy_abort_err": "Arrêt déclenché par une erreur : {err}",
        "log_plugin_deployed": "[+] plugins.txt déployé dans : {path}",
        "log_ini_deployed": "[+] Configuration {name} copiée.",
        "log_success": "\n[SUCCÈS] Assemblage terminé ({count} fichiers uniques traités).",
        "log_interrupt_requested": "\n[INTERRUPTION] Demande d'arrêt envoyée au moteur...",
    },
    "en": {
        "app_title": "mO2FLATTENER · Mod Organizer 2 Instance Flattener",
        "header_status_idle": "Skyrim SE/AE • Waiting for configuration",
        "header_status_indexing": "Skyrim SE/AE • Analyzing priorities in RAM...",
        "header_status_running": "Skyrim SE/AE • Accelerated assembly in progress...",
        "header_status_done": "Skyrim SE/AE • Assembly finished",
        "header_status_stopped": "Skyrim SE/AE • Assembly aborted",
        "header_status_error": "Skyrim SE/AE • Error encountered",
        "card1_title": "1. SOURCE INSTANCE & GAME ROOT DIRECTORY",
        "lbl_mo2": "MO2 / MODS Folder:",
        "ph_mo2": "Select the MODS directory or MO2 root folder...",
        "lbl_prof": "MO2 Profile:",
        "lbl_modl": "modlist.txt File:",
        "lbl_dest": "Target Game Root:",
        "ph_dest": "e.g. /path/to/Skyrim Special Edition",
        "btn_browse": "Browse",
        "chk_hardlinks": "Outside APFS, use hardlinks — Unchecked = Full copy. On APFS, instant copy that uses no extra space.",
        "chk_stop_on_error": "Stop assembly immediately on copy error",
        "card2_title": "2. GAME CONFIGURATION & PLUGINS DEPLOYMENT",
        "chk_plugins": "Copy plugins.txt (AppData):",
        "chk_inis": "Copy INIs (Documents):",
        "btn_run": "📦  START COMPLETE ASSEMBLY",
        "btn_stop": "🛑  ABORT ASSEMBLY",
        "log_title": "OPERATIONS LOG",
        "warn_no_profiles": "[WARNING] No 'profiles' folder found in",
        "err_title": "Error",
        "err_mo2_invalid": "The specified MO2 or MODS directory was not found.",
        "err_modlist_invalid": "The specified modlist.txt file was not found.",
        "err_dest_empty": "Please specify a target game root directory.",
        "err_plugins_dest": "Please choose a destination folder for plugins.txt.",
        "err_inis_dest": "Please choose a destination folder for INI files.",
        "success_title": "Success",
        "success_msg": "Game assembly completed successfully!",
        "stop_msg": "Assembly was stopped by user.",
        # Logging messages
        "log_analyzing": "[*] Analyzing priority order: {name}",
        "log_root_dir": "[*] Root folder: {path}",
        "log_data_dir": "[*] Data folder: {path}",
        "log_filters": "[*] Active filters: excluding .pdb, .mohidden, and junk folders",
        "log_indexing_ram": "[*] Fast RAM indexation of unique files in progress...",
        "log_indexing_stock": "    Indexing STOCK GAME: {name}",
        "log_index_complete": "[*] Indexing complete: {total} unique final files to deploy.",
        "log_copy_start": "[*] Starting optimized multi-threaded copy...",
        "log_progress": "    [{current}/{total}] files deployed...",
        "log_copy_err": "[ERROR] Failed copying {src} -> {dst}: {err}",
        "log_copy_abort_err": "Aborted due to error: {err}",
        "log_plugin_deployed": "[+] plugins.txt deployed to: {path}",
        "log_ini_deployed": "[+] Configuration {name} copied.",
        "log_success": "\n[SUCCESS] Assembly finished ({count} unique files processed).",
        "log_interrupt_requested": "\n[ABORT] Stop signal sent to worker engine...",
    },
    "it": {
        "app_title": "mO2FLATTENER · Assemblatore di Istanze Mod Organizer 2",
        "header_status_idle": "Skyrim SE/AE • In attesa di configurazione",
        "header_status_indexing": "Skyrim SE/AE • Analisi priorità in RAM...",
        "header_status_running": "Skyrim SE/AE • Assemblaggio accelerato in corso...",
        "header_status_done": "Skyrim SE/AE • Assemblaggio completato",
        "header_status_stopped": "Skyrim SE/AE • Assemblaggio interrotto",
        "header_status_error": "Skyrim SE/AE • Errore riscontrato",
        "card1_title": "1. ISTANZA DI ORIGINE E CARTELLA PRINCIPALE (ROOT)",
        "lbl_mo2": "Cartella MO2 / MODS:",
        "ph_mo2": "Seleziona la cartella MODS o la radice di MO2...",
        "lbl_prof": "Profilo MO2:",
        "lbl_modl": "File modlist.txt:",
        "lbl_dest": "Radice del gioco (Root):",
        "ph_dest": "Es: /percorso/di/Skyrim Special Edition",
        "btn_browse": "Sfoglia",
        "chk_hardlinks": "Fuori da APFS, usa collegamenti fisici (Hardlinks) — Deselezionato = Copia completa. Su APFS, copia istantanea senza spazio in più.",
        "chk_stop_on_error": "Interrompi immediatamente l'assemblaggio in caso di errore",
        "card2_title": "2. DISTRIBUZIONE CONFIGURAZIONI DEL GIOCO",
        "chk_plugins": "Copia plugins.txt (AppData):",
        "chk_inis": "Copia file INI (Documenti):",
        "btn_run": "📦  AVVIA ASSEMBLAGGIO COMPLETO",
        "btn_stop": "🛑  INTERROMPI ASSEMBLAGGIO",
        "log_title": "REGISTRO OPERAZIONI",
        "warn_no_profiles": "[AVVISO] Nessuna cartella 'profiles' trovata in",
        "err_title": "Errore",
        "err_mo2_invalid": "La cartella MO2 o MODS specificata non è stata trovata.",
        "err_modlist_invalid": "Il file modlist.txt specificato non è stato trovato.",
        "err_dest_empty": "Definisci la cartella radice di destinazione del gioco.",
        "err_plugins_dest": "Definisci la cartella di destinazione per plugins.txt.",
        "err_inis_dest": "Definisci la cartella di destinazione per i file INI.",
        "success_title": "Successo",
        "success_msg": "L'assemblaggio completo del gioco è terminato con successo!",
        "stop_msg": "L'assemblaggio è stato interrotto dall'utente.",
        # Messaggi di log
        "log_analyzing": "[*] Analisi dell'ordine di priorità: {name}",
        "log_root_dir": "[*] Cartella radice: {path}",
        "log_data_dir": "[*] Cartella Data: {path}",
        "log_filters": "[*] Filtri attivi: esclusione file .pdb, .mohidden e cartelle non necessarie",
        "log_indexing_ram": "[*] Indicizzazione rapida in RAM dei file unici in corso...",
        "log_indexing_stock": "    Indicizzazione di STOCK GAME: {name}",
        "log_index_complete": "[*] Indicizzazione completata: {total} file unici da distribuire.",
        "log_copy_start": "[*] Avvio della copia ottimizzata multi-thread...",
        "log_progress": "    [{current}/{total}] file distribuiti...",
        "log_copy_err": "[ERRORE] Copia fallita {src} -> {dst}: {err}",
        "log_copy_abort_err": "Interruzione causata da un errore: {err}",
        "log_plugin_deployed": "[+] plugins.txt distribuito in: {path}",
        "log_ini_deployed": "[+] Configurazione {name} copiata.",
        "log_success": "\n[SUCCESSO] Assemblaggio completato ({count} file unici elaborati).",
        "log_interrupt_requested": "\n[INTERRUZIONE] Segnale di arresto inviato al motore...",
    },
    "es": {
        "app_title": "mO2FLATTENER · Ensamblador de Instancias Mod Organizer 2",
        "header_status_idle": "Skyrim SE/AE • Esperando configuración",
        "header_status_indexing": "Skyrim SE/AE • Analizando prioridades en RAM...",
        "header_status_running": "Skyrim SE/AE • Ensamblaje acelerado en curso...",
        "header_status_done": "Skyrim SE/AE • Ensamblaje completado",
        "header_status_error": "Skyrim SE/AE • Error encontrado",
        "header_status_stopped": "Skyrim SE/AE • Ensamblaje interrumpido",
        "card1_title": "1. INSTANCIA DE ORIGEN Y CARPETA RAÍZ DEL JUEGO",
        "lbl_mo2": "Carpeta MO2 / MODS:",
        "ph_mo2": "Seleccione la carpeta MODS o la raíz de MO2...",
        "lbl_prof": "Perfil MO2:",
        "lbl_modl": "Archivo modlist.txt:",
        "lbl_dest": "Raíz del juego destino:",
        "ph_dest": "Ej: /ruta/hacia/Skyrim Special Edition",
        "btn_browse": "Examinar",
        "chk_hardlinks": "Fuera de APFS, usar enlaces físicos (Hardlinks) — Desmarcado = Copia completa. En APFS, copia instantánea sin espacio adicional.",
        "chk_stop_on_error": "Detener el ensamblaje de inmediato si ocurre un error",
        "card2_title": "2. DESPLIEGUE DE CONFIGURACIONES DEL JUEGO",
        "chk_plugins": "Copiar plugins.txt (AppData):",
        "chk_inis": "Copiar archivos INI (Documentos):",
        "btn_run": "📦  INICIAR ENSAMBLAJE COMPLETO",
        "btn_stop": "🛑  INTERRUMPIR ENSAMBLAJE",
        "log_title": "REGISTRO DE OPERACIONES",
        "warn_no_profiles": "[ADVERTENCIA] No se encontró la carpeta 'profiles' en",
        "err_title": "Error",
        "err_mo2_invalid": "La carpeta MO2 o MODS especificada no se encuentra.",
        "err_modlist_invalid": "El archivo modlist.txt especificado no se encuentra.",
        "err_dest_empty": "Por favor defina la carpeta raíz de destino del juego.",
        "err_plugins_dest": "Por favor defina la carpeta de destino para plugins.txt.",
        "err_inis_dest": "Por favor defina la carpeta de destino para los archivos INI.",
        "success_title": "Éxito",
        "success_msg": "¡El ensamblaje completo del juego finalizó con éxito!",
        "stop_msg": "El ensamblaje fue detenido por el usuario.",
        # Mensajes de log
        "log_analyzing": "[*] Analizando orden de prioridad: {name}",
        "log_root_dir": "[*] Carpeta raíz: {path}",
        "log_data_dir": "[*] Carpeta Data: {path}",
        "log_filters": "[*] Filtros activos: exclusión de .pdb, .mohidden y carpetas innecesarias",
        "log_indexing_ram": "[*] Indexación rápida en RAM de archivos únicos en curso...",
        "log_indexing_stock": "    Indexando STOCK GAME: {name}",
        "log_index_complete": "[*] Indexación finalizada: {total} archivos únicos para desplegar.",
        "log_copy_start": "[*] Iniciando copia optimizada multi-hilo...",
        "log_progress": "    [{current}/{total}] archivos desplegados...",
        "log_copy_err": "[ERROR] Fallo al copiar {src} -> {dst}: {err}",
        "log_copy_abort_err": "Detenido debido a un error: {err}",
        "log_plugin_deployed": "[+] plugins.txt desplegado en: {path}",
        "log_ini_deployed": "[+] Configuración {name} copiada.",
        "log_success": "\n[ÉXITO] Ensamblaje completado ({count} archivos únicos procesados).",
        "log_interrupt_requested": "\n[INTERRUPCIÓN] Señal de parada enviada al motor...",
    },
}

class I18nManager:
    _instance = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(I18nManager, cls).__new__(cls)
            cls._instance._init_settings()
        return cls._instance

    def _init_settings(self):
        try:
            self.settings = QSettings("SkyrimTools", "MO2Flattener")
            saved_lang = self.settings.value("language", "fr")
        except Exception:
            self.settings = None
            saved_lang = "fr"
        self._current_lang = saved_lang if saved_lang in TRANSLATIONS else "fr"

    @property
    def current_language(self) -> str:
        return self._current_lang

    def set_language(self, lang_code: str) -> bool:
        if lang_code in TRANSLATIONS and lang_code != self._current_lang:
            self._current_lang = lang_code
            if self.settings:
                try:
                    self.settings.setValue("language", lang_code)
                except Exception:
                    pass
            return True
        return False

    def t(self, key: str, default: str = "", **kwargs) -> str:
        lang_dict = TRANSLATIONS.get(self._current_lang, TRANSLATIONS["fr"])
        template = lang_dict.get(key, TRANSLATIONS["fr"].get(key, default or key))
        if kwargs:
            try:
                return template.format(**kwargs)
            except Exception:
                return template
        return template

# ---------------------------------------------------------------------------
# FEUILLE DE STYLE EXACTE (DARK_THEME_QSS)
# ---------------------------------------------------------------------------
DARK_THEME_QSS = """
QMainWindow {
    background-color: #181818;
    color: #dddddd;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
    font-size: 14px;
}

QDialog {
    background-color: #1e1e1e;
    color: #ffffff;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
    font-size: 14px;
    border: none;
    border-radius: 8px;
}

QLabel {
    background: transparent;
    border: none;
    font-size: 13px;
}

QFrame {
    border: none;
}

QFrame#HeaderBar {
    background-color: #222222;
    border: none;
    border-radius: 6px;
    min-height: 56px;
    max-height: 56px;
}

QFrame#CardFrame {
    background-color: #222222;
    border: none;
    border-radius: 6px;
}

QPushButton {
    background-color: #2c2c2c;
    color: #ffffff;
    border: none;
    border-radius: 5px;
    padding: 7px 16px;
    font-size: 13px;
    font-weight: 500;
}
QPushButton:hover {
    background-color: #333333;
}
QPushButton:pressed {
    background-color: #222222;
}
QPushButton:disabled {
    background-color: #222222;
    color: #666666;
    border: none;
}

QPushButton#BrowseButton {
    background-color: #333333;
    color: #ffffff;
    border: 1px solid #333333;
    border-radius: 5px;
    padding: 7px 16px;
    font-size: 13px;
    font-weight: 600;
}
QPushButton#BrowseButton:hover {
    background-color: #404040;
    border-color: #404040;
}
QPushButton#BrowseButton:pressed {
    background-color: #2a2a2a;
    border-color: #2a2a2a;
}
QPushButton#BrowseButton:disabled {
    background-color: #333333;
    color: #666666;
    border-color: #333333;
}

QPushButton#StopButton {
    background-color: #4a1c1c;
    color: #fecaca;
    font-weight: bold;
    font-size: 14px;
    border-radius: 6px;
    border: 1px solid #4a1c1c;
    padding: 0 28px;
}
QPushButton#StopButton:hover {
    background-color: #5a2222;
    border-color: #5a2222;
}
QPushButton#StopButton:pressed {
    background-color: #3a1515;
    border-color: #3a1515;
}
QPushButton#StopButton:disabled {
    background-color: #262626;
    color: #666666;
    border-color: #262626;
}

QLineEdit, QTextEdit {
    background-color: #181818;
    color: #ffffff;
    border: none;
    border-radius: 5px;
    padding: 8px 12px;
    font-size: 13px;
}
QLineEdit:focus, QTextEdit:focus {
    background-color: #1e1e1e;
}

QComboBox {
    background-color: #181818;
    color: #ffffff;
    border: none;
    border-radius: 5px;
    padding: 7px 12px;
    font-size: 13px;
}
QComboBox:hover {
    background-color: #1e1e1e;
}
QComboBox::drop-down {
    border: none;
    width: 22px;
}
QComboBox QAbstractItemView {
    background-color: #1e1e1e;
    color: #ffffff;
    selection-background-color: #0369a1;
    selection-color: #ffffff;
    border: 1px solid #262626;
    border-radius: 4px;
    padding: 6px;
    font-size: 13px;
}

QCheckBox {
    background: transparent;
    color: #dddddd;
    spacing: 10px;
    font-size: 13px;
}
QCheckBox::indicator {
    width: 18px;
    height: 18px;
    background-color: #181818;
    border: 1px solid #404040;
    border-radius: 3px;
}
QCheckBox::indicator:checked {
    background-color: #0369a1;
    border-color: #0ea5e9;
}

QProgressBar {
    background-color: #181818;
    border: none;
    border-radius: 3px;
    text-align: center;
    color: #ffffff;
    font-size: 12px;
}
QProgressBar::chunk {
    background-color: #fbbf24;
    border-radius: 3px;
}

QScrollBar:vertical {
    background-color: transparent;
    width: 6px;
    margin: 0px;
    border-radius: 3px;
}
QScrollBar::handle:vertical {
    background-color: #333333;
    min-height: 20px;
    border-radius: 3px;
}
QScrollBar::handle:vertical:hover {
    background-color: #444444;
}
QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {
    height: 0px;
}
"""

class FastFlattenerWorker(QThread):
    progress_val = pyqtSignal(int)
    log_msg = pyqtSignal(str)
    finished_ok = pyqtSignal()
    stopped_signal = pyqtSignal()
    error_raised = pyqtSignal(str)

    def __init__(
        self,
        mo2_dir: Path,
        modlist_file: Path,
        dest_game_root: Path,
        use_hardlinks: bool,
        stop_on_error: bool,
        copy_plugins: bool,
        plugins_dest: Path | None,
        copy_inis: bool,
        inis_dest: Path | None,
        i18n: I18nManager,
        parent=None,
    ):
        super().__init__(parent)
        self.mo2_dir = mo2_dir
        self.modlist_file = modlist_file
        self.dest_game_root = dest_game_root
        self.dest_data_dir = dest_game_root / "Data"
        self.use_hardlinks = use_hardlinks
        self.stop_on_error = stop_on_error
        self.copy_plugins = copy_plugins
        self.plugins_dest = plugins_dest
        self.copy_inis = copy_inis
        self.inis_dest = inis_dest
        self.i18n = i18n
        self._is_stopped = False

    def request_stop(self):
        self._is_stopped = True

    def run(self):
        t = self.i18n.t
        try:
            self.log_msg.emit(t("log_analyzing", name=self.modlist_file.name))
            self.log_msg.emit(t("log_indexing_ram"))
            tasks = build_tasks(self.mo2_dir, self.modlist_file, self.dest_game_root, lambda: self._is_stopped)
            profile_dir = self.modlist_file.parent
            if self._is_stopped:
                self.stopped_signal.emit()
                return

            self.dest_game_root.mkdir(parents=True, exist_ok=True)
            self.dest_data_dir.mkdir(parents=True, exist_ok=True)
            self.log_msg.emit(t("log_root_dir", path=str(self.dest_game_root)))
            self.log_msg.emit(t("log_data_dir", path=str(self.dest_data_dir)))
            self.log_msg.emit(t("log_filters"))

            total_files = len(tasks)
            self.log_msg.emit(t("log_index_complete", total=total_files))
            self.log_msg.emit(t("log_copy_start"))

            max_workers = min(32, (os.cpu_count() or 4) * 2)
            copied_count = 0

            with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
                futures = {}
                for src, dst in tasks:
                    if self._is_stopped:
                        break
                    f = executor.submit(optimized_copy_file, src, dst, self.use_hardlinks)
                    futures[f] = (src, dst)

                for f in concurrent.futures.as_completed(futures):
                    if self._is_stopped:
                        executor.shutdown(wait=False, cancel_futures=True)
                        self.stopped_signal.emit()
                        return

                    src, dst = futures[f]
                    try:
                        f.result()
                        copied_count += 1
                    except Exception as copy_err:
                        self.log_msg.emit(t("log_copy_err", src=src.name, dst=dst.name, err=str(copy_err)))
                        if self.stop_on_error:
                            self._is_stopped = True
                            executor.shutdown(wait=False, cancel_futures=True)
                            self.error_raised.emit(t("log_copy_abort_err", err=str(copy_err)))
                            return

                    if copied_count % 100 == 0 or copied_count == total_files:
                        percent = int((copied_count / total_files) * 95)
                        self.progress_val.emit(percent)
                        if copied_count % 500 == 0:
                            self.log_msg.emit(t("log_progress", current=copied_count, total=total_files))

            if self._is_stopped:
                self.stopped_signal.emit()
                return

            # Déploiement des configurations
            if self.copy_plugins and self.plugins_dest:
                src_plugins = profile_dir / "plugins.txt"
                if src_plugins.is_file():
                    self.plugins_dest.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(src_plugins, self.plugins_dest / "plugins.txt")
                    self.log_msg.emit(t("log_plugin_deployed", path=str(self.plugins_dest / "plugins.txt")))

            if self.copy_inis and self.inis_dest:
                self.inis_dest.mkdir(parents=True, exist_ok=True)
                for ini_name in ["skyrim.ini", "skyrimprefs.ini"]:
                    src_ini = profile_dir / ini_name
                    if not src_ini.is_file():
                        matched = [f for f in profile_dir.iterdir() if f.name.lower() == ini_name]
                        if matched:
                            src_ini = matched[0]
                    if src_ini.is_file():
                        shutil.copy2(src_ini, self.inis_dest / src_ini.name)
                        self.log_msg.emit(t("log_ini_deployed", name=src_ini.name))

            self.progress_val.emit(100)
            self.log_msg.emit(t("log_success", count=copied_count))
            self.finished_ok.emit()

        except Exception as e:
            self.error_raised.emit(str(e))

# ==============================================================================
# FENÊTRE PRINCIPALE
# ==============================================================================

class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.i18n = I18nManager()
        # textes Socle à 110 % : l'en-tête (titre + statut + langue) demande ~1 100 px
        self.resize(1180, 920)
        self.setMinimumSize(1100, 760)

        self._worker: FastFlattenerWorker | None = None
        self._init_ui()
        self._center_window()
        self.retranslate_ui()

    def _center_window(self):
        screen = QApplication.primaryScreen()
        if screen:
            screen_geom = screen.availableGeometry()
            geo = self.geometry()
            geo.moveCenter(screen_geom.center())
            self.setGeometry(geo)

    def _init_ui(self):
        central_widget = QWidget()
        central_widget.setObjectName("RootWidget")
        self.setCentralWidget(central_widget)

        root_layout = QVBoxLayout(central_widget)
        root_layout.setContentsMargins(14, 12, 14, 12)
        root_layout.setSpacing(14)

        # -------------------------------------------------------------
        # 1. EN-TÊTE SUPÉRIEUR (TITRE À 20PT EN HAUT À GAUCHE)
        # -------------------------------------------------------------
        header = QFrame()
        header.setObjectName("HeaderBar")
        header_layout = QHBoxLayout(header)
        header_layout.setContentsMargins(18, 0, 18, 0)
        header_layout.setSpacing(12)

        left_box = QHBoxLayout()
        left_box.setSpacing(10)

        bolt_icon = QLabel("⚡")
        bolt_icon.setStyleSheet("color: #fbbf24; font-size: 22px; font-weight: bold;")
        left_box.addWidget(bolt_icon)

        self.title_lbl = QLabel(self.i18n.t("app_title"))
        self.title_lbl.setStyleSheet("color: #ffffff; font-weight: 800; font-size: 20px; letter-spacing: 0.3px;")
        left_box.addWidget(self.title_lbl)
        header_layout.addLayout(left_box)

        header_layout.addStretch()

        right_box = QHBoxLayout()
        right_box.setSpacing(12)

        self.status_lbl = QLabel(self.i18n.t("header_status_idle"))
        self.status_lbl.setStyleSheet("color: #aaaaaa; font-size: 13px; font-weight: 500;")
        right_box.addWidget(self.status_lbl)

        pipe = QLabel("|")
        pipe.setStyleSheet("color: #444444;")
        right_box.addWidget(pipe)

        self.combo_lang = QComboBox()
        self.combo_lang.setFixedHeight(30)
        self.combo_lang.setCursor(Qt.CursorShape.PointingHandCursor)
        for code, label, flag in AVAILABLE_LANGUAGES:
            self.combo_lang.addItem(f"{flag} {label}", code)

        for i, (code, _, _) in enumerate(AVAILABLE_LANGUAGES):
            if code == self.i18n.current_language:
                self.combo_lang.setCurrentIndex(i)
                break

        self.combo_lang.currentIndexChanged.connect(self._on_lang_changed)
        right_box.addWidget(self.combo_lang)

        header_layout.addLayout(right_box)
        root_layout.addWidget(header)

        # -------------------------------------------------------------
        # 2. CONTENU PRINCIPAL
        # -------------------------------------------------------------
        card1 = QFrame()
        card1.setObjectName("CardFrame")
        c1_layout = QVBoxLayout(card1)
        c1_layout.setContentsMargins(18, 16, 18, 16)
        c1_layout.setSpacing(12)

        self.lbl_c1_title = QLabel(self.i18n.t("card1_title"))
        self.lbl_c1_title.setStyleSheet("font-size: 12px; font-weight: bold; color: #38bdf8; letter-spacing: 0.5px;")
        c1_layout.addWidget(self.lbl_c1_title)

        # MO2
        r1 = QHBoxLayout()
        self.lbl_mo2 = QLabel(self.i18n.t("lbl_mo2"))
        self.lbl_mo2.setFixedWidth(190)
        self.lbl_mo2.setStyleSheet("font-size: 13px; font-weight: 500;")
        self.txt_mo2 = QLineEdit()
        self.txt_mo2.setPlaceholderText(self.i18n.t("ph_mo2"))
        self.btn_mo2 = QPushButton(self.i18n.t("btn_browse"))
        self.btn_mo2.setObjectName("BrowseButton")
        self.btn_mo2.setFixedWidth(110)
        self.btn_mo2.clicked.connect(self._browse_mo2_dir)
        r1.addWidget(self.lbl_mo2)
        r1.addWidget(self.txt_mo2)
        r1.addWidget(self.btn_mo2)
        c1_layout.addLayout(r1)

        # Profil
        r2 = QHBoxLayout()
        self.lbl_prof = QLabel(self.i18n.t("lbl_prof"))
        self.lbl_prof.setFixedWidth(190)
        self.lbl_prof.setStyleSheet("font-size: 13px; font-weight: 500;")
        self.combo_profile = QComboBox()
        self.combo_profile.currentIndexChanged.connect(self._on_profile_selected)
        r2.addWidget(self.lbl_prof)
        r2.addWidget(self.combo_profile)
        c1_layout.addLayout(r2)

        # modlist.txt
        r3 = QHBoxLayout()
        self.lbl_modl = QLabel(self.i18n.t("lbl_modl"))
        self.lbl_modl.setFixedWidth(190)
        self.lbl_modl.setStyleSheet("font-size: 13px; font-weight: 500;")
        self.txt_modlist = QLineEdit()
        self.btn_modl = QPushButton(self.i18n.t("btn_browse"))
        self.btn_modl.setObjectName("BrowseButton")
        self.btn_modl.setFixedWidth(110)
        self.btn_modl.clicked.connect(self._browse_modlist_file)
        r3.addWidget(self.lbl_modl)
        r3.addWidget(self.txt_modlist)
        r3.addWidget(self.btn_modl)
        c1_layout.addLayout(r3)

        # Destination
        r4 = QHBoxLayout()
        self.lbl_dest = QLabel(self.i18n.t("lbl_dest"))
        self.lbl_dest.setFixedWidth(190)
        self.lbl_dest.setStyleSheet("font-size: 13px; font-weight: 500;")
        self.txt_dest = QLineEdit()
        self.txt_dest.setPlaceholderText(self.i18n.t("ph_dest"))
        self.btn_dest = QPushButton(self.i18n.t("btn_browse"))
        self.btn_dest.setObjectName("BrowseButton")
        self.btn_dest.setFixedWidth(110)
        self.btn_dest.clicked.connect(self._browse_dest_dir)
        r4.addWidget(self.lbl_dest)
        r4.addWidget(self.txt_dest)
        r4.addWidget(self.btn_dest)
        c1_layout.addLayout(r4)

        # Options de contrôle
        chk_row = QHBoxLayout()
        self.chk_hardlinks = QCheckBox(self.i18n.t("chk_hardlinks"))
        self.chk_hardlinks.setChecked(False)
        chk_row.addWidget(self.chk_hardlinks)

        self.chk_stop_on_error = QCheckBox(self.i18n.t("chk_stop_on_error"))
        self.chk_stop_on_error.setChecked(True)
        chk_row.addWidget(self.chk_stop_on_error)
        c1_layout.addLayout(chk_row)

        root_layout.addWidget(card1)

        # Carte 2 : Fichiers Système
        card2 = QFrame()
        card2.setObjectName("CardFrame")
        c2_layout = QVBoxLayout(card2)
        c2_layout.setContentsMargins(18, 16, 18, 16)
        c2_layout.setSpacing(12)

        self.lbl_c2_title = QLabel(self.i18n.t("card2_title"))
        self.lbl_c2_title.setStyleSheet("font-size: 12px; font-weight: bold; color: #38bdf8; letter-spacing: 0.5px;")
        c2_layout.addWidget(self.lbl_c2_title)

        # plugins.txt
        r_p = QHBoxLayout()
        self.chk_plugins = QCheckBox(self.i18n.t("chk_plugins"))
        self.chk_plugins.setChecked(True)
        self.chk_plugins.setFixedWidth(240)
        self.chk_plugins.stateChanged.connect(self._toggle_plugins_state)
        self.txt_plugins = QLineEdit()
        self.btn_plugins = QPushButton(self.i18n.t("btn_browse"))
        self.btn_plugins.setObjectName("BrowseButton")
        self.btn_plugins.setFixedWidth(110)
        self.btn_plugins.clicked.connect(self._browse_plugins_dest)
        r_p.addWidget(self.chk_plugins)
        r_p.addWidget(self.txt_plugins)
        r_p.addWidget(self.btn_plugins)
        c2_layout.addLayout(r_p)

        # INIs
        r_i = QHBoxLayout()
        self.chk_inis = QCheckBox(self.i18n.t("chk_inis"))
        self.chk_inis.setChecked(True)
        self.chk_inis.setFixedWidth(240)
        self.chk_inis.stateChanged.connect(self._toggle_inis_state)
        self.txt_inis = QLineEdit()
        self.btn_inis = QPushButton(self.i18n.t("btn_browse"))
        self.btn_inis.setObjectName("BrowseButton")
        self.btn_inis.setFixedWidth(110)
        self.btn_inis.clicked.connect(self._browse_inis_dest)
        r_i.addWidget(self.chk_inis)
        r_i.addWidget(self.txt_inis)
        r_i.addWidget(self.btn_inis)
        c2_layout.addLayout(r_i)

        root_layout.addWidget(card2)

        # -------------------------------------------------------------
        # 3. ACTIONS PRINCIPALES (CENTRÉES)
        # -------------------------------------------------------------
        action_layout = QHBoxLayout()
        action_layout.addStretch()

        self.btn_run = QPushButton(self.i18n.t("btn_run"))
        self.btn_run.setFixedHeight(48)
        self.btn_run.setCursor(Qt.CursorShape.PointingHandCursor)
        self.btn_run.setStyleSheet("""
            QPushButton {
                background-color: #fbbf24;
                color: #181818;
                font-weight: bold;
                font-size: 14px;
                border-radius: 6px;
                border: none;
                padding: 0 34px;
            }
            QPushButton:hover { background-color: #f59e0b; }
            QPushButton:pressed { background-color: #d97706; }
        """)
        self.btn_run.clicked.connect(self._start_process)
        action_layout.addWidget(self.btn_run)

        self.btn_stop = QPushButton(self.i18n.t("btn_stop"))
        self.btn_stop.setObjectName("StopButton")
        self.btn_stop.setFixedHeight(48)
        self.btn_stop.setEnabled(False)
        self.btn_stop.setCursor(Qt.CursorShape.PointingHandCursor)
        self.btn_stop.clicked.connect(self._stop_process)
        action_layout.addWidget(self.btn_stop)

        action_layout.addStretch()
        root_layout.addLayout(action_layout)

        self.progress_bar = QProgressBar()
        self.progress_bar.setFixedHeight(8)
        self.progress_bar.setTextVisible(False)
        self.progress_bar.setValue(0)
        root_layout.addWidget(self.progress_bar)

        # -------------------------------------------------------------
        # 4. JOURNAL D'EXÉCUTION
        # -------------------------------------------------------------
        card_log = QFrame()
        card_log.setObjectName("CardFrame")
        cl_layout = QVBoxLayout(card_log)
        cl_layout.setContentsMargins(16, 12, 16, 12)
        cl_layout.setSpacing(8)

        self.lbl_log_title = QLabel(self.i18n.t("log_title"))
        self.lbl_log_title.setStyleSheet("font-size: 12px; font-weight: bold; color: #aaaaaa; letter-spacing: 0.5px;")
        cl_layout.addWidget(self.lbl_log_title)

        self.log_text = QTextEdit()
        self.log_text.setReadOnly(True)
        self.log_text.setStyleSheet(
            "background-color: #181818; color: #dddddd; font-family: 'Menlo', monospace; "
            "font-size: 12px; border: none; border-radius: 5px; padding: 10px;"
        )
        cl_layout.addWidget(self.log_text)
        root_layout.addWidget(card_log, 1)

    # -----------------------------------------------------------------
    # INTERNATIONALISATION
    # -----------------------------------------------------------------
    def _on_lang_changed(self, idx: int):
        if 0 <= idx < len(AVAILABLE_LANGUAGES):
            lang_code = AVAILABLE_LANGUAGES[idx][0]
            if self.i18n.set_language(lang_code):
                self.retranslate_ui()

    def retranslate_ui(self):
        t = self.i18n.t
        self.setWindowTitle("mO2FLATTENER")
        self.title_lbl.setText(t("app_title"))
        self.lbl_c1_title.setText(t("card1_title"))
        self.lbl_mo2.setText(t("lbl_mo2"))
        self.txt_mo2.setPlaceholderText(t("ph_mo2"))
        self.lbl_prof.setText(t("lbl_prof"))
        self.lbl_modl.setText(t("lbl_modl"))
        self.lbl_dest.setText(t("lbl_dest"))
        self.txt_dest.setPlaceholderText(t("ph_dest"))
        self.btn_mo2.setText(t("btn_browse"))
        self.btn_modl.setText(t("btn_browse"))
        self.btn_dest.setText(t("btn_browse"))
        self.chk_hardlinks.setText(t("chk_hardlinks"))
        self.chk_stop_on_error.setText(t("chk_stop_on_error"))

        self.lbl_c2_title.setText(t("card2_title"))
        self.chk_plugins.setText(t("chk_plugins"))
        self.btn_plugins.setText(t("btn_browse"))
        self.chk_inis.setText(t("chk_inis"))
        self.btn_inis.setText(t("btn_browse"))

        self.btn_run.setText(t("btn_run"))
        self.btn_stop.setText(t("btn_stop"))
        self.lbl_log_title.setText(t("log_title"))

        if not (self._worker and self._worker.isRunning()):
            prof = self.combo_profile.currentText().strip()
            if prof:
                self.status_lbl.setText(f"Skyrim SE/AE • {prof}")
            else:
                self.status_lbl.setText(t("header_status_idle"))

    # -----------------------------------------------------------------
    # ÉVÉNEMENTS UI
    # -----------------------------------------------------------------
    def _toggle_plugins_state(self):
        enabled = self.chk_plugins.isChecked()
        self.txt_plugins.setEnabled(enabled)
        self.btn_plugins.setEnabled(enabled)

    def _toggle_inis_state(self):
        enabled = self.chk_inis.isChecked()
        self.txt_inis.setEnabled(enabled)
        self.btn_inis.setEnabled(enabled)

    def _browse_mo2_dir(self):
        folder = QFileDialog.getExistingDirectory(self, self.i18n.t("lbl_mo2"))
        if folder:
            self.txt_mo2.setText(folder)
            self._scan_profiles(Path(folder))

    def _browse_dest_dir(self):
        folder = QFileDialog.getExistingDirectory(self, self.i18n.t("lbl_dest"))
        if folder:
            self.txt_dest.setText(folder)

    def _browse_modlist_file(self):
        path, _ = QFileDialog.getOpenFileName(
            self, self.i18n.t("lbl_modl"), "", "Fichiers texte (modlist.txt *.txt);;Tous les fichiers (*.*)"
        )
        if path:
            self.txt_modlist.setText(path)

    def _browse_plugins_dest(self):
        folder = QFileDialog.getExistingDirectory(self, self.i18n.t("chk_plugins"))
        if folder:
            self.txt_plugins.setText(folder)

    def _browse_inis_dest(self):
        folder = QFileDialog.getExistingDirectory(self, self.i18n.t("chk_inis"))
        if folder:
            self.txt_inis.setText(folder)

    def _scan_profiles(self, mo2_base: Path):
        profiles_dir = mo2_base / "profiles"
        if not profiles_dir.is_dir() and (mo2_base.parent / "profiles").is_dir():
            profiles_dir = mo2_base.parent / "profiles"

        self.combo_profile.clear()
        if not profiles_dir.is_dir():
            self._log(f"{self.i18n.t('warn_no_profiles')} {mo2_base}")
            return

        profiles = [p.name for p in profiles_dir.iterdir() if p.is_dir()]
        self.combo_profile.addItems(profiles)
        if profiles:
            self.combo_profile.setCurrentIndex(0)
            self._on_profile_selected()

    def _on_profile_selected(self):
        mo2_str = self.txt_mo2.text().strip()
        prof_name = self.combo_profile.currentText().strip()
        if mo2_str and prof_name:
            mo2_base = Path(mo2_str)
            target = mo2_base / "profiles" / prof_name / "modlist.txt"
            if not target.is_file() and (mo2_base.parent / "profiles" / prof_name / "modlist.txt").is_file():
                target = mo2_base.parent / "profiles" / prof_name / "modlist.txt"

            if target.is_file():
                self.txt_modlist.setText(str(target))
                self.status_lbl.setText(f"Skyrim SE/AE • {prof_name}")

    def _log(self, message: str):
        self.log_text.append(message)

    def _start_process(self):
        if self._worker and self._worker.isRunning():
            return

        t = self.i18n.t
        mo2_path = Path(self.txt_mo2.text().strip())
        modlist_file = Path(self.txt_modlist.text().strip())
        dest_root = Path(self.txt_dest.text().strip())
        use_hardlinks = self.chk_hardlinks.isChecked()
        stop_on_error = self.chk_stop_on_error.isChecked()

        copy_plugins = self.chk_plugins.isChecked()
        plugins_dest = Path(self.txt_plugins.text().strip()) if copy_plugins else None

        copy_inis = self.chk_inis.isChecked()
        inis_dest = Path(self.txt_inis.text().strip()) if copy_inis else None

        if not mo2_path.is_dir():
            QMessageBox.critical(self, t("err_title"), t("err_mo2_invalid"))
            return
        if not modlist_file.is_file():
            QMessageBox.critical(self, t("err_title"), t("err_modlist_invalid"))
            return
        if not dest_root.name:
            QMessageBox.critical(self, t("err_title"), t("err_dest_empty"))
            return
        if copy_plugins and not plugins_dest:
            QMessageBox.critical(self, t("err_title"), t("err_plugins_dest"))
            return
        if copy_inis and not inis_dest:
            QMessageBox.critical(self, t("err_title"), t("err_inis_dest"))
            return

        self.btn_run.setEnabled(False)
        self.btn_stop.setEnabled(True)
        self.progress_bar.setValue(0)
        self.status_lbl.setText(t("header_status_running"))

        self._worker = FastFlattenerWorker(
            mo2_dir=mo2_path,
            modlist_file=modlist_file,
            dest_game_root=dest_root,
            use_hardlinks=use_hardlinks,
            stop_on_error=stop_on_error,
            copy_plugins=copy_plugins,
            plugins_dest=plugins_dest,
            copy_inis=copy_inis,
            inis_dest=inis_dest,
            i18n=self.i18n,
        )
        self._worker.progress_val.connect(self.progress_bar.setValue)
        self._worker.log_msg.connect(self._log)
        self._worker.finished_ok.connect(self._on_finished)
        self._worker.stopped_signal.connect(self._on_stopped)
        self._worker.error_raised.connect(self._on_error)
        self._worker.start()

    def _stop_process(self):
        if self._worker and self._worker.isRunning():
            self.btn_stop.setEnabled(False)
            self.status_lbl.setText(self.i18n.t("header_status_stopped"))
            self._log(self.i18n.t("log_interrupt_requested"))
            self._worker.request_stop()

    def _on_finished(self):
        self.btn_run.setEnabled(True)
        self.btn_stop.setEnabled(False)
        self.status_lbl.setText(self.i18n.t("header_status_done"))
        QMessageBox.information(self, self.i18n.t("success_title"), self.i18n.t("success_msg"))

    def _on_stopped(self):
        self.btn_run.setEnabled(True)
        self.btn_stop.setEnabled(False)
        self.status_lbl.setText(self.i18n.t("header_status_stopped"))
        QMessageBox.warning(self, self.i18n.t("err_title"), self.i18n.t("stop_msg"))

    def _on_error(self, err_msg: str):
        self.btn_run.setEnabled(True)
        self.btn_stop.setEnabled(False)
        self.status_lbl.setText(self.i18n.t("header_status_error"))
        self._log(f"\n[ERREUR CRITIQUE] {err_msg}")
        QMessageBox.critical(self, self.i18n.t("err_title"), f"{err_msg}")


# ==============================================================================
# POINT D'ENTRÉE PRINCIPAL
# ==============================================================================

def main():
    app = QApplication(sys.argv)
    socle_qt.apply(app, full=False)  # design system Socle
    if sys.platform == "darwin":
        app.setFont(QFont(".AppleSystemUIFont", 14))
    else:
        app.setFont(QFont("Segoe UI", 13))

    app.setStyle("Fusion")
    app.setStyleSheet(socle_qt.qss(full=False) + DARK_THEME_QSS)  # règles Socle de base conservées

    window = MainWindow()
    window.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()