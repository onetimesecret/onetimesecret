---
title: Guide de traduction pour le français
description: Guide complet pour traduire Onetime Secret en français, combinant glossaire et notes linguistiques
---

# Translation Guidance for French (Français)

This document combines the glossary and language-specific notes for French translations of Onetime Secret. It provides standardized translations for key terms and critical translation rules to ensure consistency across all French-language content.

## Language-Specific Rules

These rules are critical for maintaining proper French conventions:

| Règle | Correct | Incorrect | Exemple |
|-------|---------|-----------|---------|
| Infinitif vs. Nom | Infinitif (boutons/liens), Nom (titres/headings) | Mixed forms | ✓ Mettre à niveau (button); ✗ Mise à niveau (button) |
| Mot de passe vs. Phrase secrète | mot de passe (login), phrase secrète (secret) | Mixed usage | ✓ Entrez votre mot de passe (login); ✗ Entrez votre phrase secrète (login) |
| Ponctuation française | Espace insécable avant `:` `;` `!` `?` | No space | ✓ Question : texte ?; ✗ Question: texte? |

## Translation Glossary

### Terminologie de base

| anglais | français (FR) | Notes |
|---------|-------------|-------|
| secret (noun) | secret | Central concept of the application |
| secret (adj) | secret/sécurisé | |
| passphrase | phrase secrète | Authentication method for secrets |
| burn | brûler | Action to delete a secret before viewing |
| view/reveal | consulter/afficher | Action to access a secret |
| link | lien | The URL that provides access to a secret |
| encrypt/encrypted | chiffrer/chiffré | Security method |
| secure | sécurisé | State of protection |

### Éléments de l'interface utilisateur

| anglais | français (FR) | Notes |
|---------|-------------|-------|
| Share a secret | Partager un secret | Main action |
| Create Account | Créer un compte | Registration |
| Sign In | Se connecter | Authentication |
| Dashboard | Tableau de bord | User's main page |
| Settings | Paramètres | Configuration page |
| Privacy Options | Options de confidentialité | Secret settings |
| Feedback | Retour d'information | User comments |

### Conditions d'état

| anglais | français (FR) | Notes |
|---------|-------------|-------|
| received | reçu | Secret has been viewed |
| burned | brûlé | Secret was deleted before viewing |
| expired | expiré | Secret is no longer available due to time |
| created | créé | Secret has been generated |
| active | actif | Secret is available |
| inactive | inactif | Secret is not available |

### Termes liés au temps

| anglais | français (FR) | Notes |
|---------|-------------|-------|
| expires in | expire dans | Time until secret is no longer available |
| day/days | jour/jours | Time unit |
| hour/hours | heure/heures | Time unit |
| minute/minutes | minute/minutes | Time unit |
| second/seconds | seconde/secondes | Time unit |

### Caractéristiques de sécurité

| anglais | français (FR) | Notes |
|---------|-------------|-------|
| one-time access | accès unique | Core security feature |
| passphrase protection | protection par phrase secrète | Additional security |
| encrypted in transit | chiffré en transit | Data protection method |
| encrypted at rest | chiffré au repos | Storage protection |

### Termes relatifs au compte

| anglais | français (FR) | Notes |
|---------|-------------|-------|
| email | courriel/e-mail | User identifier |
| password | mot de passe | Authentication |
| account | compte | User profile |
| subscription | abonnement | Paid service |
| customer | client | Paying user |

### Termes liés au domaine

| anglais | français (FR) | Notes |
|---------|-------------|-------|
| custom domain | domaine personnalisé | Premium feature |
| domain verification | vérification du domaine | Setup process |
| DNS record | enregistrement DNS | Configuration |
| CNAME record | enregistrement CNAME | DNS setup |

### Messages d'erreur

| anglais | français (FR) | Notes |
|---------|-------------|-------|
| error | erreur | Problem notification |
| warning | avertissement | Caution notification |
| oops | oups | Friendly error intro |

### Boutons et actions

| anglais | français (FR) | Notes |
|---------|-------------|-------|
| submit | soumettre | Form action |
| cancel | annuler | Negative action |
| confirm | confirmer | Positive action |
| copy to clipboard | copier dans le presse-papiers | Utility action |
| continue | continuer | Navigation |
| back | retour | Navigation |

### Conditions de commercialisation

| anglais | français (FR) | Notes |
|---------|-------------|-------|
| secure links | liens sécurisés | Product feature |
| privacy-first design | conception privilégiant la protection de la vie privée | Design philosophy |
| custom branding | image de marque personnalisée | Premium feature |

## Lignes directrices pour la traduction

1. **Consistance** : Utiliser la même traduction pour un terme dans l'ensemble de l'application.
2. **Contexte** : Tenir compte de la façon dont le terme est utilisé dans l'application.
3. **Adaptation culturelle** : Adapter les termes aux conventions locales si nécessaire.
4. **Exactitude technique** : Veiller à ce que les termes relatifs à la sécurité soient traduits avec précision.
5. **Ton** : Maintenir un ton professionnel mais direct.

## Considérations particulières

- Le terme "secret" est au cœur de la demande et doit être traduit de manière cohérente.
- Les termes techniques liés à la sécurité doivent être traduits de manière plus précise que la localisation.
- Les éléments de l'interface utilisateur doivent respecter les conventions de la plate-forme pour la langue cible.
- Pour les boutons et liens, utiliser l'infinitif (ex: "Mettre à niveau") plutôt que le nom (ex: "Mise à niveau").
- Respecter la distinction entre "mot de passe" (pour l'authentification système) et "phrase secrète" (pour la protection des secrets).
- Toujours inclure un espace insécable avant les signes de ponctuation doubles (`:` `;` `!` `?`).
