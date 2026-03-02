<!--
  Article pour Ghost Blog
  Titre : PS-ManageInactiveAD : une boite a outils PowerShell pour nettoyer votre Active Directory
  Slug suggere : ps-manageinactivead-toolkit-powershell-active-directory
  Tags suggeres : PowerShell, Active Directory, Windows Server, Sysadmin, Securite, Automation
  Meta description : Decouvrez PS-ManageInactiveAD, une suite de 14 scripts PowerShell pour auditer, nettoyer et maintenir votre Active Directory. Compatible Server 2022 et 2025.
  Image de couverture suggeree : un terminal PowerShell avec des lignes de commande AD, ou le logo Windows Server
-->

# PS-ManageInactiveAD : 14 scripts PowerShell pour reprendre le controle de votre Active Directory

Qui n'a jamais ouvert la console Active Directory Users and Computers pour tomber sur des centaines de comptes jamais utilises, des groupes vides, et des objets ordinateur datant de l'ere Windows 7 ? Le menage AD, tout le monde sait qu'il faut le faire. Peu d'equipes le font regulierement.

**PS-ManageInactiveAD** est une boite a outils open source que j'ai retravaillee pour repondre a ce besoin. 14 scripts PowerShell, compatibles Windows Server 2022 et 2025, couvrant l'audit, le nettoyage et la surveillance de votre environnement AD.

---

## Le probleme

Un Active Directory qui n'est pas entretenu, c'est :

- **Un risque de securite** : des comptes inactifs sont des portes d'entree potentielles pour un attaquant
- **Du bruit dans vos annuaires** : les recherches sont polluees par des objets obsoletes
- **Des licences gaspillees** : des comptes actifs qui ne devraient plus l'etre
- **Des audits douloureux** : impossible de repondre clairement a "qui a acces a quoi ?"

Le nettoyage manuel est fastidieux et sujet aux erreurs. Les scripts permettent de le systematiser.

---

## Ce que contient la boite a outils

### Nettoyage AD

| Script | Ce qu'il fait |
|--------|--------------|
| **Find-ADInactiveUsers** | Detecte les comptes utilisateurs qui ne se sont pas connectes depuis X jours. Peut desactiver, deplacer en quarantaine et supprimer. |
| **Find-ADInactiveComputers** | Idem pour les objets ordinateur. |
| **Find-ADEmptyGroups** | Liste les groupes de securite et de distribution sans aucun membre. |
| **Find-ADEmptyOU** | Liste les OUs qui ne contiennent aucun objet. |

### Audit securite

| Script | Ce qu'il fait |
|--------|--------------|
| **Find-ADLockedAccounts** | Liste les comptes verrouilles, avec option de deverrouillage en masse. |
| **Find-ADPasswordNeverExpires** | Detecte les comptes avec le flag "Le mot de passe n'expire jamais". |
| **Find-ADStalePasswords** | Trouve les comptes dont le mot de passe n'a pas change depuis X jours. |
| **Find-ADPrivilegedAccounts** | Audite les membres de Domain Admins, Enterprise Admins et 8 autres groupes privilegies. |

### Maintenance

| Script | Ce qu'il fait |
|--------|--------------|
| **Find-ADDisabledInGroups** | Detecte les comptes desactives qui sont encore membres de groupes (risque de securite). |
| **Find-ADObsoleteOS** | Liste les machines sous OS en fin de vie (XP a Server 2019). |
| **Find-ADUnlinkedGPO** | Trouve les GPOs orphelines non liees a aucune OU. |
| **Find-ADDuplicateSPN** | Detecte les SPNs en doublon qui cassent l'authentification Kerberos. |

### Sante AD

| Script | Ce qu'il fait |
|--------|--------------|
| **Test-ADReplicationHealth** | Verifie la replication entre tous les controleurs de domaine. |
| **Test-ADFSMORoles** | Audite le placement et la disponibilite des 5 roles FSMO. |

---

## Philosophie de conception

### Mode safe par defaut

Chaque script genere un rapport CSV sans rien modifier. Les actions destructives (desactiver, supprimer) ne s'activent que si vous passez explicitement le switch correspondant :

```powershell
# Rapport seul - rien ne bouge
.\Find-ADInactiveUsers.ps1

# On desactive
.\Find-ADInactiveUsers.ps1 -DisableUsers

# On simule d'abord
.\Find-ADInactiveUsers.ps1 -DeleteUsers -WhatIf
```

### Workflow de quarantaine

Plutot que de supprimer directement un compte, la bonne pratique c'est : **desactiver, deplacer, attendre, puis supprimer**. Les scripts supportent ce workflow nativement :

```powershell
# Etape 1 : desactiver et deplacer en quarantaine
.\Find-ADInactiveUsers.ps1 -DisableUsers -QuarantineOU "OU=Quarantine,DC=corp,DC=local"

# Etape 2 (30 jours plus tard) : supprimer depuis la quarantaine
.\Find-ADInactiveUsers.ps1 -SearchBase "OU=Quarantine,DC=corp,DC=local" -DeleteUsers
```

### Parametres communs

Tous les scripts partagent les memes parametres pour une experience homogene :

- **`-ReportFilePath`** : chemin du CSV (defaut `C:\tmp\`)
- **`-SearchBase`** / **`-ExcludeOU`** : cibler ou exclure des OUs
- **`-EnableLogging`** : log horodate dans `C:\tmp\Logs\`
- **`-EmailTo`** / **`-SmtpServer`** : notification email automatique
- **`-WhatIf`** / **`-Confirm`** : simulation et confirmation

---

## Mise en place

### Prerequis

- Windows Server 2022 ou 2025
- PowerShell 5.1+
- RSAT (module ActiveDirectory)

```powershell
Install-WindowsFeature -Name RSAT-AD-PowerShell
```

### Installation

```powershell
git clone https://github.com/SyNode-IT/PS-ManageInactiveAD.git
cd PS-ManageInactiveAD
.\Find-ADInactiveUsers.ps1
```

C'est tout. Pas de module a installer, pas de dependance complexe. Le seul fichier obligatoire est `ADManagement-Common.ps1` qui doit rester dans le meme repertoire que les scripts.

---

## Automatisation

Le vrai interet de ces scripts, c'est de les planifier. Voici un exemple de tache planifiee pour un rapport hebdomadaire :

```powershell
$Action = New-ScheduledTaskAction -Execute 'powershell.exe' `
  -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\PS-ManageInactiveAD\Find-ADInactiveUsers.ps1" -EnableLogging -EmailTo "admin@corp.local" -SmtpServer "smtp.corp.local"'

$Trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At '06:00'

Register-ScheduledTask -TaskName 'AD-WeeklyReport' `
  -Action $Action -Trigger $Trigger `
  -User 'DOMAIN\svc-admanagement'
```

Tous les lundis matin a 6h, vous recevez un rapport des comptes inactifs par email. Simple et efficace.

---

## Cas d'usage concret : le menage mensuel

Voici le workflow que je recommande sur un cycle de 4 semaines :

**Semaine 1 - Audit securite** : lancer les scripts d'audit (comptes privilegies, mots de passe, SPNs, replication). Analyser les rapports.

**Semaine 2 - Nettoyage des comptes** : desactiver les comptes inactifs, les deplacer en quarantaine. Nettoyer les appartenances aux groupes des comptes desactives.

**Semaine 3 - Nettoyage structurel** : traiter les groupes vides, OUs vides, GPOs orphelines. Lister les machines sous OS obsolete.

**Semaine 4 - Suppression** : apres validation des rapports des semaines precedentes, supprimer les objets en quarantaine.

---

## Documentation

Le projet inclut une documentation technique complete (disponible en Markdown, HTML et PDF) couvrant chaque script en detail : parametres, exemples, colonnes CSV, droits requis, et guide de depannage.

---

## Conclusion

Un AD propre, c'est un AD plus sur et plus facile a administrer. Ces scripts n'ont pas vocation a remplacer une solution comme DVLS ou un SIEM, mais ils couvrent les operations de base que tout administrateur devrait automatiser.

Le projet est open source et disponible sur GitHub. N'hesitez pas a l'adapter a vos besoins.

**Lien GitHub :** [https://github.com/SyNode-IT/PS-ManageInactiveAD](https://github.com/SyNode-IT/PS-ManageInactiveAD)

---

*Tags : PowerShell, Active Directory, Windows Server 2022, Windows Server 2025, Sysadmin, Securite, Automation, Scripts*
