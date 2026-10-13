# Changements

## 1.9.2 — 2026-10-13
### Modifié
- Palette : plus aucun bouton en bleu au repos ; le bleu n'apparaît qu'au survol de la souris.

### Corrigé
- La palette se déplace enfin : glisser sur une zone sans bouton (en-tête, marges, pied).

## 1.9.1 — 2026-10-13
### Modifié
- Palette : les gros carrés sont blancs et passent à un bleu plus foncé au survol de la souris (le bouton principal reste bleu).
- La palette se déplace en la saisissant par son fond.

## 1.9 — 2026-10-13
### Ajouté
- Palette refaite en verre (Liquid Glass sur macOS 26, flou teinté avant) : quatre gros carrés (Dicter, Corriger, Pro, Courriel) avec leur raccourci. Sombre en mode sombre, son négatif en mode clair ; le bouton principal reste bleu.
- Espace lance la dictée quand la palette est ouverte, et l'arrête (comme « Terminer »).
- Réglages : « Ouvrir AutoCorrection au démarrage du Mac ».
- Réglages : « Cacher l'icône de la barre des menus ». Le raccourci reste actif ; rouvrir l'app depuis Applications ou Spotlight ouvre les réglages.

### Corrigé
- Dicter sans microphone fermait l'app : un message d'erreur s'affiche maintenant.

## 1.8 — 2026-10-13
### Ajouté
- Menu de mise à jour : « Rechercher les mises à jour… » dans le menu de la barre de menus, avec le numéro de version affiché. L'app compare avec la dernière Release GitHub, affiche les nouveautés et, après confirmation, télécharge, vérifie la signature (même développeur, notarisée), remplace l'app et la relance.

### Modifié
- Le dépôt GitHub est public : aucun jeton n'est nécessaire.

## 1.7.1 — 2026-10-13
### Corrigé
- Pendant la dictée, l'en-tête de la palette affiche « Dictée en cours… » au lieu de « Aucun texte sélectionné ».

## 1.7 — 2026-10-13
### Ajouté
- Dictée vocale : quand rien n'est sélectionné, la palette propose « Dicter un texte ». Le texte s'affiche en direct pendant que vous parlez (reconnaissance d'Apple, en français, sur le Mac quand c'est possible), puis les trois actions s'appliquent au texte dicté. « Redicter » recommence.
- Palette : bouton de fermeture (×) et fermeture par un clic en dehors de la palette, pour la refermer facilement si elle s'ouvre par erreur.
- Autorisations macOS demandées au premier usage : Microphone et Reconnaissance vocale.

## 1.6 — 2026-10-13
### Ajouté
- Réglages, moteur Claude Code : indicateur « connecté / non connecté » et bouton « Se connecter » (équivalent de `claude auth login`) qui ouvre le navigateur pour relier Claude Code au compte.

## 1.5 — 2026-10-13
### Modifié
- « Corriger et embellir » devient « Corriger et rendre professionnel » : corrige puis reformule dans un ton professionnel, clair et direct.
- « Réécrire en courriel » suit le style professionnel standard de Dany : français québécois, tutoiement ou vouvoiement selon le texte, « Bonjour [Prénom], », une à trois phrases courtes, « Merci, ».

### Retiré
- La signature des courriels et son réglage : le courriel se termine par « Merci, ».

## 1.4 — 2026-10-13
### Ajouté
- Réglages : choix du modèle (Haiku 5.5, Sonnet 5.5, Opus 5.5) et du niveau de réflexion (faible, moyen, élevé), pour les deux moteurs. Par défaut : Haiku 5.5, réflexion faible.

## 1.3 — 2026-10-13
### Ajouté
- Moteur « Claude Code » : les textes peuvent être traités par la commande `claude` du Mac, avec le forfait du compte connecté (Max), sans clé API. Choix du moteur dans les réglages.

### Retiré
- La mise à jour automatique par GitHub (introduite en 1.1).

## 1.2 — 2026-10-13
### Modifié
- Modèle par défaut : Claude Haiku 5.5 avec un effort de réflexion faible. Une correction coûte environ 0,02 ¢ US et répond plus vite. Le champ « Modèle » des réglages permet de revenir à un modèle plus puissant.

## 1.1 — 2026-10-13
### Ajouté
- Mises à jour par GitHub : l'app vérifie les Releases du dépôt au lancement puis chaque jour, signale la nouvelle version dans la barre de menus et l'installe en un clic (téléchargement, vérification de la signature, remplacement, relance).
- Réglages : jeton GitHub en lecture seule (gardé dans le Trousseau), vérification automatique activable, bouton « Vérifier maintenant ».

## 1.0 — 2026-10-13

Première version publiée.
