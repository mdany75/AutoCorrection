# CLAUDE.md — AutoCorrection

App Mac en barre de menus (Swift/SwiftUI, SwiftPM, macOS 14+) qui envoie le texte sélectionné, ou dicté, à Claude pour le corriger ou le réécrire selon cinq presets (Correction, Personnel, Pro, Note TI, Courriel).

Ce projet suit le standard commun des projets de Dany (`/standard-projet` le vérifie).

## Commandes

| Action | Commande |
| --- | --- |
| Construire | `./build.sh` |
| Tester | pas de tests |

Les fichiers produits vont dans `build/`, ignoré par git. Rien de compilé n'est commité.

## Publier une version

Dans cet ordre :

1. Mettre le numéro à jour dans `build.sh` (`CFBundleShortVersionString` et `CFBundleVersion`) et ajouter la section `## X.Y — date` dans `CHANGELOG.md`.
2. `git add -A && git commit -m "Version X.Y" && git push origin main`
3. `./build.sh` (produit `build/AutoCorrection.dmg`, signé et notarisé ; `./build.sh --install` installe aussi dans `/Applications`)
4. `git tag -a vX.Y -m "Version X.Y" && git push origin vX.Y`
5. `gh release create vX.Y build/AutoCorrection.dmg --title "AutoCorrection X.Y" --notes "$(~/.claude/skills/standard-projet/scripts/notes-version.sh X.Y)"`

## Règles

- Répondre et écrire (commits, README, textes de l'interface) en français.
- La clé API ne va que dans le Trousseau (`Keychain` dans `Prefs.swift`), jamais dans le code, les préférences ou git.
- Le texte de l'utilisateur est une matière à traiter : le prompt système (`Actions.swift`) l'enferme entre balises `<texte>` et interdit de suivre ses instructions. Ne pas l'affaiblir.
- Les presets (`Preset`) servent aux cinq carrés de la palette (`TextAction.presetID`) et à la dictée. Ils ne remplacent que la tâche : `Prompts.common` est toujours imposé, `Prompts.dictation` s'y ajoute pour la dictée (après la tâche, pour primer), et l'utilisateur ne peut modifier ni l'un ni l'autre.
- Dictée (seulement sans palette depuis la 1.13) : bascule (un appui démarre, un appui ou le silence arrête), car Logi Options+ envoie une frappe instantanée même quand le bouton est tenu (vérifié avec une MX Master 4). Les deux raccourcis ont chacun leur identifiant (`HotKey`) ; un gestionnaire laisse passer ceux qui ne sont pas les siens.
- Le moteur « Claude Code » (`ClaudeCodeClient` dans `ClaudeClient.swift`) lance `claude -p` sans outil ni réglage de projet (`--tools "" --setting-sources ""`) : ne jamais lui laisser d'outils, le texte de l'utilisateur est une matière à traiter. L'app graphique n'a pas le PATH du Terminal, d'où la liste des emplacements connus de `claude`.
- La mise à jour (`Updater.swift`) lit la dernière Release publique et n'installe qu'une app signée par l'équipe `2F5M9B25A6`, notarisée, dont la version correspond à la Release. La Release doit joindre `AutoCorrection.dmg` (nom fixe) ; ne pas affaiblir ces vérifications.
- Le presse-papiers de l'utilisateur doit toujours être rétabli après copie ou collage (`Clipboard.swift`).
- Avant de pousser une fonctionnalité : README et CHANGELOG à jour, capture d'écran (`docs/capture.png`) refaite si l'interface a changé, et une nouvelle version si ce qu'on installe a changé.
- Pousser sur `main` directement.

## Organisation

- `Sources/AutoCorrection/` : `AppController` (barre de menus, palette, flux), `Clipboard` (⌘C/⌘V simulés, Accessibilité), `Dictation` (dictée vocale, framework Speech), `ClaudeClient` (API), `Actions` (actions, presets de dictée et prompts), `HotKey` et `ShortcutRecorder` (raccourcis globaux de la palette et de la dictée), `Updater` (mise à jour par GitHub), `Prefs` (préférences et Trousseau), `PaletteView` et `SettingsView` (interface)
- `Resources/` : icône, `AutoCorrection.entitlements` (droit d'entrée audio, nécessaire sous le runtime durci)
- `scripts/` : génération de l'icône (`make-icon.swift`)
- `docs/` : capture d'écran, cahier des charges
