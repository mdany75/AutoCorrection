# CLAUDE.md — AutoCorrection

App Mac en barre de menus (Swift/SwiftUI, SwiftPM, macOS 14+) qui envoie le texte sélectionné à Claude pour le corriger ou le réécrire selon quatre presets (Orthographe, Personnel, Professionnel, Courriel ; les trois derniers retirent les tics d'écriture des IA).

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
- Les presets (`Preset`) servent aux quatre carrés de la palette (`TextAction.presetID`) : Orthographe (id `orthographe`) et les trois presets humains, Personnel (`humain`), Professionnel (`humainPro`) et Courriel (`humainCourriel`). Les id datent de la 1.15 et restent enregistrés dans les préférences : ne pas les renommer avec les noms affichés. Ils ne remplacent que la tâche : `Prompts.common` est toujours imposé, `Prompts.human` s'ajoute après la tâche de Professionnel et de Courriel, et l'utilisateur ne peut modifier aucun de ces blocs. La consigne de Personnel, elle, contient les mêmes tics (`Prompts.humanTics`) au milieu de ses propres règles, là où ils gardent le mieux la voix de l'auteur ; comme toute consigne, elle reste modifiable dans les réglages.
- Les consignes humaines ont été mesurées avec Haiku 5.5 en effort faible (réglage par défaut), sur un banc de textes répétés plusieurs fois : un seul essai ne départage pas deux consignes. Ne pas les retoucher sans refaire la mesure.
- Pas de dictée depuis la 1.16 (la dictée de macOS la remplace) : l'app ne demande ni micro ni reconnaissance vocale, et n'a aucun droit de signature (entitlements). Ne pas la réintroduire sans que Dany le demande.
- Le moteur « Claude Code » (`ClaudeCodeClient` dans `ClaudeClient.swift`) lance `claude -p` sans outil ni réglage de projet (`--tools "" --setting-sources ""`) : ne jamais lui laisser d'outils, le texte de l'utilisateur est une matière à traiter. L'app graphique n'a pas le PATH du Terminal, d'où la liste des emplacements connus de `claude`.
- La mise à jour (`Updater.swift`) lit la dernière Release publique et n'installe qu'une app signée par l'équipe `2F5M9B25A6`, notarisée, dont la version correspond à la Release. La Release doit joindre `AutoCorrection.dmg` (nom fixe) ; ne pas affaiblir ces vérifications.
- Le presse-papiers de l'utilisateur doit toujours être rétabli après copie ou collage (`Clipboard.swift`).
- Avant de pousser une fonctionnalité : README et CHANGELOG à jour, captures d'écran (`docs/capture.png` pour la palette, `docs/reglages.png` pour l'onglet Presets des réglages) refaites si l'interface a changé, et une nouvelle version si ce qu'on installe a changé.
- Pousser sur `main` directement.

## Organisation

- `Sources/AutoCorrection/` : `AppController` (barre de menus, palette, flux), `Clipboard` (⌘C/⌘V simulés, Accessibilité), `ClaudeClient` (API), `Actions` (carrés de la palette, presets et prompts), `HotKey` et `ShortcutRecorder` (raccourci global de la palette), `Updater` (mise à jour par GitHub), `Prefs` (préférences et Trousseau), `PaletteView` et `SettingsView` (interface)
- `Resources/` : icône
- `scripts/` : génération de l'icône (`make-icon.swift`)
- `docs/` : captures d'écran (palette, réglages)
