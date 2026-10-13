# AutoCorrection

Petite app Mac, dans la barre de menus, qui corrige, embellit ou réécrit en courriel professionnel le texte sélectionné dans n'importe quelle app, grâce à Claude.

## Fonctions

- Raccourci global (⌥Espace par défaut, modifiable dans les réglages) qui ouvre une palette flottante sur le texte sélectionné.
- Trois actions : corriger seulement (↵), corriger et embellir (⌘↵), réécrire en courriel professionnel avec signature (⌥↵).
- Le résultat remplace la sélection, ou va dans le presse-papiers selon le réglage.
- Le presse-papiers d'origine est rétabli après chaque opération.
- Clé API Anthropic conservée dans le Trousseau ; modèle et signature configurables.

## Installer

Pas encore de version publiée : voir « Reconstruire ».

Configuration requise : macOS 14 ou plus et une clé API Anthropic. Au premier lancement, accorder l'autorisation Accessibilité (Réglages Système > Confidentialité et sécurité) pour que l'app puisse copier et coller le texte, puis saisir la clé dans les réglages.

## Reconstruire

Outils nécessaires : Swift 5.9 ou plus (outils en ligne de commande Xcode).

```bash
./build.sh
```

Produit `build/AutoCorrection.app` (signature ad hoc).

## Organisation

- `Sources/AutoCorrection/` : code Swift (palette, presse-papiers, client Claude, raccourci, réglages)
- `Resources/` : icône de l'app
- `scripts/` : génération de l'icône
- `build.sh` : compile et assemble l'app dans `build/`
