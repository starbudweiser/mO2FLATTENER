# Changelog — mO2FLATTENER

Notes de version / release notes (EN + FR). Translations in IT and ES: see the Nexus Mods page.

## Unreleased

**English**

- New section "3. Mac adaptation (DXMT, ENB, DLSS)". You choose how the assembled game will be used: **Universal folder (Stock)**, preselected, where nothing is added or changed and the folder works anywhere (Windows, CrossOver, Wine…), or **For a CrossOver bottle (mORTEX DXMT kit)**, which announces every fix (DXMT graphics engine, DLSS bridge, SSE Display Tweaks, DLLs duplicated by Bottled Shaders, shader compiler, Wine DLL overrides) and lets you pick the bottle. Each choice says what changes in the folder, what changes in the bottle, what you can do with the folder afterwards and how to undo. The kit needs a CrossOver bottle: without one it is not offered, and the DLSS bridge is never placed on its own.
- New "Mac report" card under the log: for each fix, applied, failed or skipped, with an Undo button per fix and for all (a Stock folder simply says nothing was changed). Original files are kept in the game's `_MAC_BACKUP` folder.
- When the game is already adapted, the announcement now says so and lists what is already in place (DXMT engine active, DLSS bridge present, SSE Display Tweaks settings suited to DXMT, no duplicated DLL) instead of only showing what is missing. Only points the engine actually checked as fine are listed.
- Bottled Shaders 1.0.26 or later is looked for in your MO2 downloads; otherwise the report links to its Nexus page (never downloaded or bundled by the app).
- Shared Mac engine (the same one as mORTEX and mABBAJACK), through the `mackit` tool bundled in the app.

**Français**

- Nouvelle section « 3. Adaptation au Mac (DXMT, ENB, DLSS) ». Vous choisissez comment le jeu assemblé sera utilisé : **Dossier universel (Stock)**, présélectionné, où rien n'est ajouté ni modifié et où le dossier fonctionne partout (Windows, CrossOver, Wine…), ou **Pour une bouteille CrossOver (kit DXMT mORTEX)**, qui annonce chaque correctif (moteur graphique DXMT, pont DLSS, SSE Display Tweaks, DLL en double avec Bottled Shaders, compilateur de shaders, substitutions de DLL Wine) et laisse choisir la bouteille. Chaque choix dit ce qui change dans le dossier, ce qui change dans la bouteille, ce qu'on peut faire du dossier ensuite et comment annuler. Le kit demande une bouteille CrossOver : sans elle il n'est pas proposé, et le pont DLSS n'est jamais posé seul.
- Nouvelle carte « Bilan Mac » sous le journal : pour chaque correctif, appliqué, échoué ou ignoré, avec un bouton Annuler par correctif et pour tout (un dossier Stock dit simplement que rien n'a été modifié). Les fichiers d'origine sont gardés dans le dossier `_MAC_BACKUP` du jeu.
- Quand le jeu est déjà adapté, l'annonce le dit et liste ce qui est déjà en place (moteur DXMT actif, pont DLSS présent, réglages de SSE Display Tweaks adaptés à DXMT, aucune DLL en double) au lieu de n'afficher que ce qui manque. Seuls les points que le moteur a vraiment contrôlés et trouvés bons sont listés.
- Bottled Shaders 1.0.26 ou plus récent est cherché dans vos téléchargements MO2 ; à défaut, le bilan renvoie vers sa page Nexus (jamais téléchargé ni embarqué par l'appli).
- Moteur Mac commun (le même que mORTEX et mABBAJACK), par l'outil `mackit` embarqué dans l'appli.

## 1.3.0

**English**

- Signed with a Developer ID and notarized by Apple: macOS now opens the app without a security warning.
- The app's launcher is now compiled from source when the app is built, instead of using PyInstaller's generic prebuilt launcher, which antivirus scanners tend to flag. No change in features.
- The first letter of the app's name now uses the colour of its logo everywhere it appears.
- Version number aligned across the Skyrim Mac Toolkit.

**Français**

- Signée avec un certificat Developer ID et notarisée par Apple : macOS ouvre désormais l'appli sans avertissement de sécurité.
- Le lanceur de l'appli est maintenant compilé depuis les sources à la construction de l'appli, au lieu du lanceur générique précompilé de PyInstaller, souvent signalé par les antivirus. Aucun changement de fonctionnalités.
- La première lettre du nom de l'appli prend la couleur de son logo partout où il est écrit.
- Numéro de version commun à tout le Skyrim Mac Toolkit.

<!-- gen_changelogs : entrées ci-dessous conservées -->

## 1.0.0

First public release. / Première version publique.
