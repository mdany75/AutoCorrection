# AutoCorrection

Petite app Mac, dans la barre de menus, qui corrige, embellit ou réécrit en courriel professionnel le texte sélectionné dans n'importe quelle app, grâce à Claude.

![AutoCorrection](docs/capture.png)

## Fonctions

- Raccourci global (⌥Espace par défaut, modifiable dans les réglages) qui ouvre une palette flottante sur le texte sélectionné.
- Trois actions : corriger seulement (↵), corriger et embellir (⌘↵), réécrire en courriel professionnel avec signature (⌥↵).
- Le résultat remplace la sélection, ou va dans le presse-papiers selon le réglage.
- Le presse-papiers d'origine est rétabli après chaque opération.
- Mises à jour automatiques depuis les Releases GitHub, installées en un clic.
- Clé API Anthropic conservée dans le Trousseau ; modèle et signature configurables.

## Installer

Télécharge [AutoCorrection.dmg](https://github.com/mdany75/AutoCorrection/releases/latest/download/AutoCorrection.dmg) (toujours la dernière version), ouvre-le, puis glisse AutoCorrection dans Applications.

Configuration requise : macOS 14 ou plus et une clé API Anthropic. Au premier lancement, accorder l'autorisation Accessibilité (Réglages Système > Confidentialité et sécurité) pour que l'app puisse copier et coller le texte, puis saisir la clé dans les réglages.

### Mises à jour

Le dépôt étant privé, l'app a besoin d'un jeton GitHub en lecture seule : sur GitHub, Réglages > Developer settings > Fine-grained tokens, accès au seul dépôt `mdany75/AutoCorrection`, permission « Contents : Read-only ». Collez-le dans les réglages de l'app (il va dans le Trousseau). L'app vérifie ensuite au lancement puis chaque jour ; le menu propose « Installer la version X ». Seule une app signée par le même développeur et notarisée est acceptée.

## Reconstruire

Outils nécessaires : Swift 5.9 ou plus (outils en ligne de commande Xcode). Avec le certificat « Developer ID Application » et le profil `notarisation` de `notarytool`, l'image disque est signée et notarisée ; sinon, signature ad hoc.

```bash
./build.sh
```

Produit `build/AutoCorrection.app` et `build/AutoCorrection.dmg`. L'option `--install` installe aussi dans `/Applications`.

## Organisation

- `Sources/AutoCorrection/` : code Swift (palette, presse-papiers, client Claude, raccourci, réglages)
- `Resources/` : icône de l'app
- `scripts/` : génération de l'icône
- `build.sh` : compile et assemble l'app dans `build/`
