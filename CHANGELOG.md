# Changements

## 1.15.1 — 2026-10-20
### Modifié
- Les styles s'appellent maintenant Orthographe, Personnel (l'ancien Humain), Professionnel (l'ancien Humain + Pro) et Courriel (l'ancien Humain + Courriel), dans la palette, le menu « Style de la dictée » et les réglages. Ils fonctionnent comme avant : Personnel, Professionnel et Courriel retirent toujours les tics d'écriture des IA. Le style de dictée choisi est conservé ; Personnel est le style par défaut.

## 1.15 — 2026-10-20
### Modifié
- Palette : quatre carrés, sans raccourci clavier : Orthographe, Humain, Humain + Pro et Humain + Courriel. Orthographe (l'ancien Correction) corrige les fautes sans reformuler ; elle ne sert plus à la dictée. Les trois autres retirent toujours les tics d'écriture des IA (règles du style humain) : seul, en ton professionnel, ou en courriel prêt à envoyer. Dans le texte modifiable de la palette, Entrée fait maintenant un saut de ligne.
- Dictée : le menu « Style de la dictée » et les réglages proposent Tel quel (sans IA), Humain, Humain + Pro et Humain + Courriel ; Humain par défaut. Une dictée réglée sur un style retiré passe à Humain.
- Humain + Pro : un texte anglais reste en anglais, et le contexte, le but d'une action, les intervalles (2019–2020) et les répliques de dialogue sont gardés.
- Humain + Courriel : même une note ou une dictée devient un courriel complet qui commence par « Bonjour » ; une signature d'origine est remplacée par « Merci, » ; l'offre de suivi reste simple, sans « N'hésitez pas ».
- Testé sur des textes neufs avec Haiku 5.5 en effort faible, à l'aveugle : Humain + Pro et Humain + Courriel font mieux que les anciens Pro et Courriel, avec moins de tics d'écriture des IA et sans traduire l'anglais. Le preset Humain garde la consigne de la 1.14.

### Retiré
- Les presets Personnel, Pro et Courriel seuls, remplacés par Humain + Pro et Humain + Courriel. Les presets personnalisés avant la 1.15 sont remplacés par ceux d'origine.

### Corrigé
- Un texte sélectionné qui contenait lui-même les balises `</texte>` et `<texte>` pouvait sortir de son enveloppe et faire passer une fausse consigne pour une vraie (par exemple : traduire tout le texte en anglais). Ces balises perdent maintenant leur « < », remplacé par « ‹ », avant l'envoi à Claude, quelle que soit leur casse ou leurs espaces ; le reste du texte ne change pas. La même enveloppe sert à la clé API et à Claude Code.

## 1.14 — 2026-10-20
### Modifié
- Le carré TI (⇧⌘↵) devient Humain, avec le preset « Style humain » : il corrige les fautes et retire les tics d'écriture des IA pour que le texte ne sonne pas comme écrit par une IA. Sont visés les contrastes « ce n'est pas X, c'est Y », les questions mises en scène, les annonces, les chutes d'une ligne, les mots gonflés (« crucial », « incontournable »…), les tirets cadratins, le gras, les émojis et les formules toutes faites. Les faits, le tutoiement ou le vouvoiement et les expressions québécoises restent, et un texte déjà naturel change à peine. Le texte anglais est traité aussi, en anglais. Les règles viennent du skill humanizer (d'après « Signs of AI writing » de Wikipédia).

### Retiré
- Le preset Note TI. S'il avait été personnalisé dans les réglages, le style humain le remplace ; une dictée réglée sur la Note TI revient à Correction.

## 1.13.2 — 2026-10-15
### Corrigé
- Dictée : juste après le retrait ou le branchement d'écouteurs, macOS peut encore désigner l'ancien micro pendant un instant (erreur 560227702). La dictée attend un moment et réessaie, au départ comme pendant l'écoute ; si le micro ne répond toujours pas, le message l'explique en français au lieu du seul code d'erreur.

## 1.13.1 — 2026-10-15
### Corrigé
- La dictée ne captait plus rien après avoir mis ou retiré des écouteurs, jusqu'au relancement de l'app : le moteur audio restait lié au micro du lancement. Chaque dictée prend maintenant le micro du moment, et un changement de micro pendant l'écoute est repris sans perdre les mots déjà reconnus.

## 1.13 — 2026-10-15
### Modifié
- Palette : cinq carrés, les mêmes que les presets : Correction (↵), Personnel (⌃↵), Pro (⌘↵), TI (⇧⌘↵) et Courriel (⌥↵). Leur consigne se modifie dans les réglages (onglet Dictée) et sert aussi à la dictée sans palette.
- Consigne Correction : corrige aussi les majuscules, sans reformuler (garde les mots, le ton et la structure).
- Dictée : les consignes procèdent en deux étapes (nettoyer l'oral, puis appliquer la tâche), ce qui applique plus sûrement les reprises comme « non, je veux dire… ».
- Note TI : n'écrit que les lignes dont le texte donne l'information.

### Retiré
- La dictée dans la palette (carré Dicter et touche Espace) : la dictée sans palette (⌃⌥⌘D) la remplace.

## 1.12 — 2026-10-15
### Ajouté
- Dictée sans palette : un deuxième raccourci (⌃⌥⌘D par défaut, modifiable) lance l'écoute sans aucune fenêtre. Elle s'arrête par un nouvel appui ou, au choix, après un silence de 3, 5, 7 ou 10 secondes ; le texte s'écrit alors à l'emplacement du curseur. Esc annule. Prévu pour un bouton de souris réglé dans Logi Options+ (action « Raccourci clavier »).
- Pendant l'écoute : son de début et de fin (désactivables) ; l'icône de la barre des menus devient un micro, puis un sablier pendant le traitement, et s'affiche même si elle est cachée.
- Presets de traitement de la dictée : Correction (par défaut), Style personnel, Style professionnel, Courriel, Note TI, ou Brut (sans IA). Nom et consigne modifiables, avec « Rétablir les presets d'origine ». Choix rapide dans le menu « Traitement de la dictée ».
- Les consignes de dictée retirent les hésitations et les faux départs et appliquent les corrections dites à voix haute (« non, plutôt jeudi »). Une dictée en forme de question ou de demande est écrite, jamais répondue.
- Durée maximale d'écoute réglable (1, 2 ou 5 minutes). Si Claude échoue, le texte reconnu est écrit tel quel et un message l'explique.

### Modifié
- Réglages en deux onglets : Général et Dictée.

### Corrigé
- Quand un nouveau raccourci était refusé (déjà pris par une autre app), l'ancien n'était pas rétabli et l'app restait sans raccourci.

## 1.11 — 2026-10-13
### Ajouté
- Le texte sélectionné est modifiable dans la palette avant de cliquer sur une action ; les actions s'appliquent au texte modifié. Entrée corrige, ⇧↵ fait un saut de ligne. Pendant l'édition, Espace écrit une espace au lieu de lancer la dictée.

## 1.10 — 2026-10-13
### Ajouté
- Réglages : « Style de la palette », Liquid Glass (par défaut) ou Standard. Liquid Glass : verre de macOS 26 sur le panneau et les carrés, l'action principale plus lumineuse ; flou teinté sur macOS 14 et 15. Standard : matériau flou classique et carrés blancs.
- Le texte sélectionné s'affiche en entier : la zone grandit avec le texte jusqu'à 12 lignes, puis une barre de défilement apparaît.

### Modifié
- Palette plus large (560) ; les quatre carrés gardent leur taille et sont centrés.

## 1.9.3 — 2026-10-13
### Corrigé
- Palette : coins arrondis au niveau de la fenêtre et ombre recalculée à chaque affichage et changement de taille, pour éviter les coins carrés gris.

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
