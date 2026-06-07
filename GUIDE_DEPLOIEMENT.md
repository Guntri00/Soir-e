# Soirée d'été — CSE IQVIA · Guide de mise en ligne

Site adapté depuis le projet Mementos. URL cible : **https://soir-e-alpha.vercel.app/**
Dossier projet : `C:\Users\mcham\Documents\Soiree\`

## 1. Fichiers du projet

```
index.html              ← app invités (thème tropical)
dashboard.html          ← dashboard organisateur
dashboard-maries.html   ← dashboard "hôte" (galerie complète)
sw.js                   ← service worker (PWA)
manifest.json           ← manifeste PWA
vercel.json             ← config Vercel + en-têtes de sécurité
ring-intro.png          ← image PWA (à remplacer plus tard, optionnel)
SETUP_SUPABASE.sql      ← script de création de la base
icons/icon-192.png      ← À AJOUTER (voir §4)
icons/icon-512.png      ← À AJOUTER (voir §4)
```

> Les sauvegardes d'origine (`index (2).html`, `dashboard (25).html`, etc.) sont restées dans `C:\Users\mcham\Documents\Virginie\`. Ne pas les déployer.

## 2. Base de données Supabase

1. Ouvre le projet Supabase : `https://xhijahegkohowfmajjvq.supabase.co`
2. **SQL Editor → New query** → colle le contenu de **`SETUP_SUPABASE.sql`** → **Run**.
3. Ce script crée : tables `events`/`photos`, policies RLS, fonction `toggle_photo_like`, bucket `photos`, et la ligne de l'événement `soiree-ete-2026`.

Config déjà inscrite dans les 3 fichiers :
- `SB_URL = https://xhijahegkohowfmajjvq.supabase.co`
- `SB_KEY = sb_publishable_RqfsxW6HW7Zg95xG2R-sng_ILRjYtfU`
- `EVENT_ID = soiree-ete-2026`

## 3. Déploiement Vercel

- Le fichier principal s'appelle **`index.html`** → servi automatiquement sur `/` (aucun rewrite nécessaire).
- Push sur le dépôt connecté à `soir-e-alpha` → Vercel déploie tout seul.

## 4. Icônes PWA (à fournir)

Le `manifest.json` référence `/icons/icon-192.png` et `/icons/icon-512.png` qui **n'existent pas encore**. Tant qu'ils sont absents : le site fonctionne, mais l'icône d'installation PWA / l'icône Apple seront en 404. Ajoute deux PNG carrés (192×192 et 512×512) dans un dossier `icons/`.

## 5. Personnalisation après coup

Depuis le **dashboard organisateur** (`dashboard.html`) tu peux activer/couper les uploads et la vidéo. Le nom / la date / le lieu affichés sur la page d'accueil invités sont **écrits en dur** dans `index.html` (en-tête + écran d'intro) — dis-moi si tu veux les rendre modifiables depuis le dashboard.

## 6. Accès dashboards (à changer !)

Les deux dashboards se déverrouillent par un **mot de passe vérifié côté navigateur** (hash SHA-256). Les hashs actuels sont **hérités du projet Mementos d'origine** — donc les identifiants sont ceux de l'ancien projet. ⚠️ À régénérer avec tes propres identifiants (voir note de sécurité plus bas).

---
## ⚠️ Notes de sécurité

1. **Login dashboard côté client (faible).** Le contrôle se fait dans le navigateur (hash SHA-256 en clair dans le HTML) : c'est de l'obfuscation, pas une vraie protection. Quelqu'un de motivé peut le contourner. Pour un vrai contrôle, il faudrait passer par Supabase Auth. Acceptable pour un événement à faible enjeu, mais à connaître.
2. **Clé `anon` publique.** Toutes les écritures utilisent la clé publique (visible dans le HTML). Les policies RLS la cadrent (insertion seulement si l'événement est actif + uploads activés ; pas de modification arbitraire des likes). C'est le modèle voulu par l'app.
3. **Isolation OK.** Projet Supabase dédié → un seul événement → aucun risque de mélange avec d'autres soirées.
