<!--
  Article pour Ghost Blog
  Titre : PS-ManageInactiveAD : une boîte à outils PowerShell pour nettoyer votre Active Directory
  Slug suggéré : ps-manageinactivead-toolkit-powershell-active-directory
  Tags suggérés : PowerShell, Active Directory, Windows Server, Sysadmin, Sécurité, Automation
  Meta description : Découvrez PS-ManageInactiveAD, une suite de 14 scripts PowerShell pour auditer, nettoyer et maintenir votre Active Directory. Compatible Server 2022 et 2025.
  Image de couverture suggérée : un terminal PowerShell avec des lignes de commande AD, ou le logo Windows Server
-->

# PS-ManageInactiveAD : 14 scripts PowerShell pour reprendre le contrôle de votre Active Directory

Qui n'a jamais ouvert la console Active Directory Users and Computers pour tomber sur des centaines de comptes jamais utilisés, des groupes vides, et des objets ordinateur datant de l'ère Windows 7 ? Le ménage AD, tout le monde sait qu'il faut le faire. Peu d'équipes le font régulièrement.

**PS-ManageInactiveAD** est une boîte à outils open source que j'ai retravaillée pour répondre à ce besoin. 14 scripts PowerShell, compatibles Windows Server 2022 et 2025, couvrant l'audit, le nettoyage et la surveillance de votre environnement AD.

---

## Le problème

Un Active Directory qui n'est pas entretenu, c'est :

- **Un risque de sécurité** : des comptes inactifs sont des portes d'entrée potentielles pour un attaquant
- **Du bruit dans vos annuaires** : les recherches sont polluées par des objets obsolètes
- **Des licences gaspillées** : des comptes actifs qui ne devraient plus l'être
- **Des audits douloureux** : impossible de répondre clairement à "qui a accès à quoi ?"

Le nettoyage manuel est fastidieux et sujet aux erreurs. Les scripts permettent de le systématiser.

---

## Ce que contient la boîte à outils

### Nettoyage AD

| Script | Ce qu'il fait |
|--------|--------------|
| **Find-ADInactiveUsers** | Détecte les comptes utilisateurs qui ne se sont pas connectés depuis X jours. Peut désactiver, déplacer en quarantaine et supprimer. |
| **Find-ADInactiveComputers** | Idem pour les objets ordinateur. |
| **Find-ADEmptyGroups** | Liste les groupes de sécurité et de distribution sans aucun membre. |
| **Find-ADEmptyOU** | Liste les OUs qui ne contiennent aucun objet. |

### Audit sécurité

| Script | Ce qu'il fait |
|--------|--------------|
| **Find-ADLockedAccounts** | Liste les comptes verrouillés, avec option de déverrouillage en masse. |
| **Find-ADPasswordNeverExpires** | Détecte les comptes avec le flag "Le mot de passe n'expire jamais". |
| **Find-ADStalePasswords** | Trouve les comptes dont le mot de passe n'a pas changé depuis X jours. |
| **Find-ADPrivilegedAccounts** | Audite les membres de Domain Admins, Enterprise Admins et 8 autres groupes privilégiés. |

### Maintenance

| Script | Ce qu'il fait |
|--------|--------------|
| **Find-ADDisabledInGroups** | Détecte les comptes désactivés qui sont encore membres de groupes (risque de sécurité). |
| **Find-ADObsoleteOS** | Liste les machines sous OS en fin de vie (XP à Server 2019). |
| **Find-ADUnlinkedGPO** | Trouve les GPOs orphelines non liées à aucune OU. |
| **Find-ADDuplicateSPN** | Détecte les SPNs en doublon qui cassent l'authentification Kerberos. |

### Santé AD

| Script | Ce qu'il fait |
|--------|--------------|
| **Test-ADReplicationHealth** | Vérifie la réplication entre tous les contrôleurs de domaine. |
| **Test-ADFSMORoles** | Audite le placement et la disponibilité des 5 rôles FSMO. |

---

## Philosophie de conception

### Mode safe par défaut

Chaque script génère un rapport CSV sans rien modifier. Les actions destructives (désactiver, supprimer) ne s'activent que si vous passez explicitement le switch correspondant :

```powershell
# Rapport seul - rien ne bouge
.\Find-ADInactiveUsers.ps1

# On désactive
.\Find-ADInactiveUsers.ps1 -DisableUsers

# On simule d'abord
.\Find-ADInactiveUsers.ps1 -DeleteUsers -WhatIf
```

### Workflow de quarantaine

Plutôt que de supprimer directement un compte, la bonne pratique c'est : **désactiver, déplacer, attendre, puis supprimer**. Les scripts supportent ce workflow nativement :

```powershell
# Étape 1 : désactiver et déplacer en quarantaine
.\Find-ADInactiveUsers.ps1 -DisableUsers -QuarantineOU "OU=Quarantine,DC=corp,DC=local"

# Étape 2 (30 jours plus tard) : supprimer depuis la quarantaine
.\Find-ADInactiveUsers.ps1 -SearchBase "OU=Quarantine,DC=corp,DC=local" -DeleteUsers
```

### Paramètres communs

Tous les scripts partagent les mêmes paramètres pour une expérience homogène :

- **`-ReportFilePath`** : chemin du CSV (défaut `C:\tmp\`)
- **`-SearchBase`** / **`-ExcludeOU`** : cibler ou exclure des OUs
- **`-EnableLogging`** : log horodaté dans `C:\tmp\Logs\`
- **`-EmailTo`** / **`-SmtpServer`** : notification email automatique
- **`-WhatIf`** / **`-Confirm`** : simulation et confirmation

---

## Mise en place

### Prérequis

- Windows Server 2022 ou 2025
- PowerShell 5.1+
- RSAT (module ActiveDirectory)

```powershell
Install-WindowsFeature -Name RSAT-AD-PowerShell
```

### Installation

Pas besoin de Git sur le serveur. Téléchargez le ZIP directement depuis PowerShell :

```powershell
# Télécharger et extraire
Invoke-WebRequest -Uri "https://github.com/SyNode-IT/PS-ManageInactiveAD/archive/refs/heads/main.zip" -OutFile "$env:TEMP\PS-ManageInactiveAD.zip"
Expand-Archive -Path "$env:TEMP\PS-ManageInactiveAD.zip" -DestinationPath "C:\Scripts" -Force
Rename-Item "C:\Scripts\PS-ManageInactiveAD-main" "C:\Scripts\PS-ManageInactiveAD"

# Lancer un premier rapport
cd C:\Scripts\PS-ManageInactiveAD
.\Find-ADInactiveUsers.ps1
```

Si Git est installé sur le serveur, vous pouvez aussi cloner le dépôt :

```powershell
git clone https://github.com/SyNode-IT/PS-ManageInactiveAD.git C:\Scripts\PS-ManageInactiveAD
```

C'est tout. Pas de module à installer, pas de dépendance complexe. Le seul fichier obligatoire est `ADManagement-Common.ps1` qui doit rester dans le même répertoire que les scripts.

---

## Automatisation

Le vrai intérêt de ces scripts, c'est de les planifier. Voici un exemple de tâche planifiée pour un rapport hebdomadaire :

```powershell
$Action = New-ScheduledTaskAction -Execute 'powershell.exe' `
  -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\PS-ManageInactiveAD\Find-ADInactiveUsers.ps1" -EnableLogging -EmailTo "admin@corp.local" -SmtpServer "smtp.corp.local"'

$Trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At '06:00'

Register-ScheduledTask -TaskName 'AD-WeeklyReport' `
  -Action $Action -Trigger $Trigger `
  -User 'DOMAIN\svc-admanagement'
```

Tous les lundis matin à 6h, vous recevez un rapport des comptes inactifs par email. Simple et efficace.

---

## Cas d'usage concret : le ménage mensuel

Voici le workflow que je recommande sur un cycle de 4 semaines :

**Semaine 1 - Audit sécurité** : lancer les scripts d'audit (comptes privilégiés, mots de passe, SPNs, réplication). Analyser les rapports.

**Semaine 2 - Nettoyage des comptes** : désactiver les comptes inactifs, les déplacer en quarantaine. Nettoyer les appartenances aux groupes des comptes désactivés.

**Semaine 3 - Nettoyage structurel** : traiter les groupes vides, OUs vides, GPOs orphelines. Lister les machines sous OS obsolète.

**Semaine 4 - Suppression** : après validation des rapports des semaines précédentes, supprimer les objets en quarantaine.

---

## Documentation

Le projet inclut une documentation technique complète (disponible en Markdown, HTML et PDF) couvrant chaque script en détail : paramètres, exemples, colonnes CSV, droits requis, et guide de dépannage.

---

## Conclusion

Un AD propre, c'est un AD plus sûr et plus facile à administrer. Ces scripts n'ont pas vocation à remplacer une solution comme DVLS ou un SIEM, mais ils couvrent les opérations de base que tout administrateur devrait automatiser.

Le projet est open source et disponible sur GitHub. N'hésitez pas à l'adapter à vos besoins.

**Lien GitHub :** [https://github.com/SyNode-IT/PS-ManageInactiveAD](https://github.com/SyNode-IT/PS-ManageInactiveAD)

---

*Tags : PowerShell, Active Directory, Windows Server 2022, Windows Server 2025, Sysadmin, Sécurité, Automation, Scripts*
