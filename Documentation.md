# PS-ManageInactiveAD - Documentation Technique

## Boite a outils de gestion Active Directory

**Version :** 2.0
**Compatibilite :** Windows Server 2022, Windows Server 2025 (PowerShell 5.1+)
**Derniere mise a jour :** 2026

---

## Table des matieres

1. [Prerequis](#1-prerequis)
2. [Installation](#2-installation)
3. [Architecture](#3-architecture)
4. [Parametres communs](#4-parametres-communs)
5. [Scripts de nettoyage AD](#5-scripts-de-nettoyage-ad)
   - 5.1 [Find-ADInactiveUsers](#51-find-adinactiveusers)
   - 5.2 [Find-ADInactiveComputers](#52-find-adinactivecomputers)
   - 5.3 [Find-ADEmptyGroups](#53-find-ademptygroups)
   - 5.4 [Find-ADEmptyOU](#54-find-ademptyou)
6. [Scripts d'audit securite](#6-scripts-daudit-securite)
   - 6.1 [Find-ADLockedAccounts](#61-find-adlockedaccounts)
   - 6.2 [Find-ADPasswordNeverExpires](#62-find-adpasswordneverexpires)
   - 6.3 [Find-ADStalePasswords](#63-find-adstalepasswords)
   - 6.4 [Find-ADPrivilegedAccounts](#64-find-adprivilegedaccounts)
7. [Scripts de maintenance](#7-scripts-de-maintenance)
   - 7.1 [Find-ADDisabledInGroups](#71-find-addisabledingroups)
   - 7.2 [Find-ADObsoleteOS](#72-find-adobsoleteos)
   - 7.3 [Find-ADUnlinkedGPO](#73-find-adunlinkedgpo)
   - 7.4 [Find-ADDuplicateSPN](#74-find-adduplicatespn)
8. [Scripts de sante AD](#8-scripts-de-sante-ad)
   - 8.1 [Test-ADReplicationHealth](#81-test-adreplicationhealth)
   - 8.2 [Test-ADFSMORoles](#82-test-adfsmoroles)
9. [Workflow de nettoyage recommande](#9-workflow-de-nettoyage-recommande)
10. [Planification des taches](#10-planification-des-taches)
11. [Depannage](#11-depannage)

---

## 1. Prerequis

### Logiciels requis

| Composant | Requis | Verification |
|-----------|--------|-------------|
| PowerShell 5.1+ | Oui | `$PSVersionTable.PSVersion` |
| Module ActiveDirectory | Oui | `Get-Module -ListAvailable ActiveDirectory` |
| Module GroupPolicy | Pour Find-ADUnlinkedGPO uniquement | `Get-Module -ListAvailable GroupPolicy` |
| RSAT (Remote Server Administration Tools) | Oui | Installer via Server Manager ou `Add-WindowsCapability` |

### Installation RSAT (si necessaire)

**Sur Windows Server 2022/2025 :**
```powershell
Install-WindowsFeature -Name RSAT-AD-PowerShell
Install-WindowsFeature -Name GPMC    # Pour Find-ADUnlinkedGPO
```

**Sur Windows 10/11 :**
```powershell
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
Add-WindowsCapability -Online -Name Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0
```

### Droits requis

| Action | Droit minimum |
|--------|--------------|
| Rapport (lecture seule) | Domain Users / Account Operators |
| Desactiver des comptes | Account Operators / Delegated Admin |
| Supprimer des objets | Domain Admins (ou delegation specifique) |
| GPO management | Group Policy Creator Owners |
| Replication / FSMO | Domain Admins |

---

## 2. Installation

1. Copier l'ensemble du dossier sur un serveur membre ou un controleur de domaine.
2. Verifier que tous les fichiers sont presents :

```
PS-ManageInactiveAD/
  ADManagement-Common.ps1          <- Fichier obligatoire (fonctions partagees)
  Find-ADInactiveUsers.ps1
  Find-ADInactiveComputers.ps1
  Find-ADEmptyGroups.ps1
  Find-ADEmptyOU.ps1
  Find-ADLockedAccounts.ps1
  Find-ADPasswordNeverExpires.ps1
  Find-ADStalePasswords.ps1
  Find-ADPrivilegedAccounts.ps1
  Find-ADDisabledInGroups.ps1
  Find-ADObsoleteOS.ps1
  Find-ADUnlinkedGPO.ps1
  Find-ADDuplicateSPN.ps1
  Test-ADReplicationHealth.ps1
  Test-ADFSMORoles.ps1
```

3. S'assurer que la politique d'execution PowerShell permet l'execution de scripts :

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

> **IMPORTANT** : Le fichier `ADManagement-Common.ps1` doit TOUJOURS etre dans le meme repertoire que les scripts. Tous les scripts en dependent.

---

## 3. Architecture

### Fichier commun : ADManagement-Common.ps1

Ce fichier contient les fonctions partagees par tous les scripts :

| Fonction | Role |
|----------|------|
| `Write-ADMLog` | Ecriture horodatee dans la console et le fichier de log |
| `Start-ADMLogging` / `Stop-ADMLogging` | Demarrage/arret du logging fichier |
| `Export-ADMReport` | Export CSV avec creation auto du repertoire |
| `Send-ADMReport` | Envoi du rapport par email SMTP |
| `Test-ADMExcludedOU` | Verification si un objet est dans une OU exclue |
| `Move-ADMToQuarantine` | Deplacement d'un objet vers une OU de quarantaine |
| `Write-ADMBanner` | Affichage du bandeau de debut/fin d'execution |

### Repertoires par defaut

| Chemin | Contenu |
|--------|---------|
| `C:\tmp\` | Rapports CSV |
| `C:\tmp\Logs\` | Fichiers de log (si `-EnableLogging`) |

Ces chemins sont modifiables via le parametre `-ReportFilePath`.

---

## 4. Parametres communs

Tous les scripts partagent les parametres suivants :

### Rapport

| Parametre | Type | Defaut | Description |
|-----------|------|--------|-------------|
| `-ReportFilePath` | String | `C:\tmp\<NomScript>.csv` | Chemin complet du fichier CSV de rapport |

### Logging

| Parametre | Type | Defaut | Description |
|-----------|------|--------|-------------|
| `-EnableLogging` | Switch | `$false` | Active l'ecriture d'un fichier de log horodate dans `C:\tmp\Logs\` |

### Email

| Parametre | Type | Defaut | Description |
|-----------|------|--------|-------------|
| `-EmailTo` | String[] | - | Adresse(s) email du/des destinataire(s) |
| `-SmtpServer` | String | - | Serveur SMTP pour l'envoi |
| `-EmailFrom` | String | `ADManagement@<domaine>` | Adresse email de l'expediteur |

> L'email n'est envoye que si `-EmailTo` ET `-SmtpServer` sont specifies.

### Filtrage (la plupart des scripts)

| Parametre | Type | Description |
|-----------|------|-------------|
| `-SearchBase` | String | Chemin LDAP pour restreindre la recherche a une OU |
| `-ExcludeOU` | String[] | Tableau de DN d'OUs a exclure des resultats |

### Securite (-WhatIf / -Confirm)

Tous les scripts avec des actions destructives supportent :

```powershell
# Simuler sans rien modifier
.\Find-ADInactiveUsers.ps1 -DeleteUsers -WhatIf

# Demander confirmation pour chaque action
.\Find-ADInactiveUsers.ps1 -DisableUsers -Confirm
```

---

## 5. Scripts de nettoyage AD

### 5.1 Find-ADInactiveUsers

**But :** Trouver et gerer les comptes utilisateurs inactifs.

**Parametres specifiques :**

| Parametre | Defaut | Description |
|-----------|--------|-------------|
| `-SearchScope` | `All` | Portee : `All`, `OnlyInactiveUsers`, `OnlyServiceAccounts`, `OnlyNeverLoggedOn`, `AllExceptServiceAccounts`, `AllExceptNeverLoggedOn` |
| `-DaysInactive` | `90` | Nombre de jours d'inactivite |
| `-ServiceAccountIdentifier` | `svc` | Prefixe/suffixe identifiant les comptes de service |
| `-QuarantineOU` | - | OU de quarantaine pour deplacer les comptes desactives |
| `-DisableUsers` | `$false` | Desactive les comptes inactifs |
| `-DeleteUsers` | `$false` | Supprime les comptes inactifs |

**Exemples :**

```powershell
# Rapport simple
.\Find-ADInactiveUsers.ps1

# Rapport des utilisateurs inactifs depuis 60 jours dans l'OU Paris
.\Find-ADInactiveUsers.ps1 -DaysInactive 60 -SearchBase "OU=Paris,DC=corp,DC=local"

# Desactiver et deplacer en quarantaine
.\Find-ADInactiveUsers.ps1 -DisableUsers -QuarantineOU "OU=Disabled Users,DC=corp,DC=local"

# Exclure les VIP et les comptes de service
.\Find-ADInactiveUsers.ps1 -SearchScope AllExceptServiceAccounts -ExcludeOU "OU=VIP,DC=corp,DC=local"
```

**Colonnes du rapport CSV :**
`Username`, `Name`, `LastLogonDate`, `DistinguishedName`

---

### 5.2 Find-ADInactiveComputers

**But :** Trouver et gerer les objets ordinateur inactifs.

**Parametres specifiques :**

| Parametre | Defaut | Description |
|-----------|--------|-------------|
| `-SearchScope` | `All` | Portee : `All`, `OnlyInactiveComputers`, `OnlyNeverLoggedOn` |
| `-DaysInactive` | `90` | Nombre de jours d'inactivite |
| `-QuarantineOU` | - | OU de quarantaine |
| `-DisableObjects` | `$false` | Desactive les ordinateurs inactifs |
| `-DeleteObjects` | `$false` | Supprime les ordinateurs inactifs |

**Exemples :**

```powershell
# Rapport des postes inactifs depuis 120 jours
.\Find-ADInactiveComputers.ps1 -DaysInactive 120

# Desactiver les postes et les deplacer en quarantaine
.\Find-ADInactiveComputers.ps1 -DisableObjects -QuarantineOU "OU=Disabled Computers,DC=corp,DC=local"
```

**Colonnes du rapport CSV :**
`Name`, `LastLogonDate`, `DistinguishedName`

---

### 5.3 Find-ADEmptyGroups

**But :** Trouver et gerer les groupes AD vides (sans membres).

**Parametres specifiques :**

| Parametre | Defaut | Description |
|-----------|--------|-------------|
| `-SearchScope` | Domaine entier | Chemin LDAP pour restreindre la recherche |
| `-DeleteObjects` | `$false` | Supprime les groupes vides |

**Exemples :**

```powershell
# Rapport de tous les groupes vides
.\Find-ADEmptyGroups.ps1

# Rapport des groupes vides dans une OU specifique
.\Find-ADEmptyGroups.ps1 -SearchScope "OU=Groups,DC=corp,DC=local"

# Supprimer les groupes vides (simulation)
.\Find-ADEmptyGroups.ps1 -DeleteObjects -WhatIf
```

**Colonnes du rapport CSV :**
`Name`, `GroupCategory`, `DistinguishedName`

---

### 5.4 Find-ADEmptyOU

**But :** Trouver et gerer les OUs vides (sans objets enfants).

**Parametres specifiques :**

| Parametre | Defaut | Description |
|-----------|--------|-------------|
| `-SearchScope` | Domaine entier | Chemin LDAP pour restreindre la recherche |
| `-DeleteObjects` | `$false` | Supprime les OUs vides |

> **Note :** Les OUs protegees contre la suppression accidentelle genereront une erreur.

**Exemples :**

```powershell
# Rapport de toutes les OUs vides
.\Find-ADEmptyOU.ps1

# Supprimer les OUs vides (avec confirmation)
.\Find-ADEmptyOU.ps1 -DeleteObjects -Confirm
```

**Colonnes du rapport CSV :**
`Name`, `DistinguishedName`

---

## 6. Scripts d'audit securite

### 6.1 Find-ADLockedAccounts

**But :** Trouver les comptes utilisateurs verrouilles et optionnellement les deverrouiller.

**Parametres specifiques :**

| Parametre | Defaut | Description |
|-----------|--------|-------------|
| `-UnlockAccounts` | `$false` | Deverrouille les comptes trouves |

**Exemples :**

```powershell
# Lister les comptes verrouilles
.\Find-ADLockedAccounts.ps1

# Deverrouiller tous les comptes
.\Find-ADLockedAccounts.ps1 -UnlockAccounts
```

**Colonnes du rapport CSV :**
`Username`, `Name`, `LastLogonDate`, `LockoutTime`, `LastBadPasswordAttempt`, `DistinguishedName`

---

### 6.2 Find-ADPasswordNeverExpires

**But :** Trouver les comptes avec le flag "Le mot de passe n'expire jamais".

**Parametres specifiques :**

| Parametre | Defaut | Description |
|-----------|--------|-------------|
| `-IncludeServiceAccounts` | `$false` | Inclure les comptes de service (exclus par defaut) |
| `-ServiceAccountIdentifier` | `svc` | Prefixe/suffixe des comptes de service |
| `-RemoveFlag` | `$false` | Retire le flag PasswordNeverExpires |

**Exemples :**

```powershell
# Rapport (sans comptes de service)
.\Find-ADPasswordNeverExpires.ps1

# Inclure les comptes de service
.\Find-ADPasswordNeverExpires.ps1 -IncludeServiceAccounts

# Retirer le flag (simulation)
.\Find-ADPasswordNeverExpires.ps1 -RemoveFlag -WhatIf
```

**Colonnes du rapport CSV :**
`Username`, `Name`, `PasswordLastSet`, `LastLogonDate`, `Description`, `DistinguishedName`

---

### 6.3 Find-ADStalePasswords

**But :** Trouver les comptes dont le mot de passe n'a pas ete change depuis X jours.

**Parametres specifiques :**

| Parametre | Defaut | Description |
|-----------|--------|-------------|
| `-DaysOld` | `180` | Nombre de jours depuis le dernier changement de mot de passe |
| `-ForceChangeAtLogon` | `$false` | Force le changement de mot de passe a la prochaine connexion |

**Exemples :**

```powershell
# Mots de passe de plus de 180 jours
.\Find-ADStalePasswords.ps1

# Mots de passe de plus d'un an
.\Find-ADStalePasswords.ps1 -DaysOld 365

# Forcer le changement (simulation)
.\Find-ADStalePasswords.ps1 -DaysOld 90 -ForceChangeAtLogon -WhatIf
```

**Colonnes du rapport CSV :**
`Username`, `Name`, `PasswordLastSet`, `PasswordAgeDays`, `LastLogonDate`, `Description`, `DistinguishedName`

---

### 6.4 Find-ADPrivilegedAccounts

**But :** Auditer les membres des groupes privilegies AD.

**Parametres specifiques :**

| Parametre | Defaut | Description |
|-----------|--------|-------------|
| `-Groups` | Liste complete des groupes privilegies | Tableau de noms de groupes a auditer |
| `-IncludeNested` | `$false` | Resolution recursive des groupes imbriques |

**Groupes audites par defaut :**
Domain Admins, Enterprise Admins, Schema Admins, Administrators, Account Operators,
Backup Operators, Server Operators, Print Operators, DnsAdmins, Group Policy Creator Owners

**Exemples :**

```powershell
# Audit complet
.\Find-ADPrivilegedAccounts.ps1

# Avec resolution des groupes imbriques
.\Find-ADPrivilegedAccounts.ps1 -IncludeNested

# Auditer des groupes specifiques
.\Find-ADPrivilegedAccounts.ps1 -Groups "Domain Admins","IT-Admins"
```

**Colonnes du rapport CSV :**
`GroupName`, `MemberName`, `SamAccountName`, `ObjectClass`, `Enabled`, `LastLogonDate`, `PasswordLastSet`, `DistinguishedName`

---

## 7. Scripts de maintenance

### 7.1 Find-ADDisabledInGroups

**But :** Trouver les comptes desactives qui sont encore membres de groupes.

**Parametres specifiques :**

| Parametre | Defaut | Description |
|-----------|--------|-------------|
| `-RemoveMemberships` | `$false` | Retire les appartenances aux groupes |

**Exemples :**

```powershell
# Rapport des appartenances obsoletes
.\Find-ADDisabledInGroups.ps1

# Retirer les appartenances (simulation)
.\Find-ADDisabledInGroups.ps1 -RemoveMemberships -WhatIf

# Retirer avec confirmation par item
.\Find-ADDisabledInGroups.ps1 -RemoveMemberships -Confirm
```

**Colonnes du rapport CSV :**
`Username`, `UserName`, `GroupName`, `GroupDN`, `LastLogonDate`, `WhenChanged`, `UserDN`

---

### 7.2 Find-ADObsoleteOS

**But :** Trouver les ordinateurs sous systemes d'exploitation obsoletes.

**Parametres specifiques :**

| Parametre | Defaut | Description |
|-----------|--------|-------------|
| `-ObsoletePatterns` | Liste complete (XP a Server 2019) | Patterns de noms d'OS consideres obsoletes |

**OS consideres obsoletes par defaut :**
Windows XP, Vista, 7, 8, 8.1, 10, Server 2003, 2008, 2012, 2016, 2019

> **Note :** Adapter le parametre `-ObsoletePatterns` selon votre politique de cycle de vie.
> Par exemple, si Server 2019 est encore supporte dans votre environnement, retirez-le de la liste.

**Exemples :**

```powershell
# Rapport avec les patterns par defaut
.\Find-ADObsoleteOS.ps1

# Chercher uniquement Server 2012 et 2016
.\Find-ADObsoleteOS.ps1 -ObsoletePatterns "*Server 2012*","*Server 2016*"
```

**Colonnes du rapport CSV :**
`Name`, `OperatingSystem`, `OperatingSystemVersion`, `OperatingSystemServicePack`, `LastLogonDate`, `IPv4Address`, `DistinguishedName`

---

### 7.3 Find-ADUnlinkedGPO

**But :** Trouver les GPO orphelines (non liees a aucune OU/site/domaine).

> **Prerequis supplementaire :** Module `GroupPolicy` (GPMC / RSAT)

**Parametres specifiques :**

| Parametre | Defaut | Description |
|-----------|--------|-------------|
| `-ExcludeGPO` | Default Domain Policy, Default Domain Controllers Policy | GPOs a exclure du rapport |
| `-DeleteObjects` | `$false` | Supprime les GPOs non liees |

**Exemples :**

```powershell
# Rapport des GPOs non liees
.\Find-ADUnlinkedGPO.ps1

# Supprimer les GPOs orphelines (simulation)
.\Find-ADUnlinkedGPO.ps1 -DeleteObjects -WhatIf
```

**Colonnes du rapport CSV :**
`DisplayName`, `Id`, `Status`, `CreationTime`, `ModificationTime`, `Owner`

---

### 7.4 Find-ADDuplicateSPN

**But :** Detecter les SPN (Service Principal Names) en doublon dans le domaine.

> Les SPN dupliques causent des echecs d'authentification Kerberos.

**Ce script est en lecture seule.** La correction des SPN doit etre faite manuellement avec `setspn`.

**Exemples :**

```powershell
# Rapport des SPNs dupliques
.\Find-ADDuplicateSPN.ps1
```

**Correction manuelle :**
```powershell
# Supprimer un SPN duplique
setspn -d HTTP/serveur.corp.local COMPTE_A_CORRIGER
```

**Colonnes du rapport CSV :**
`SPN`, `ObjectName`, `ObjectType`, `DuplicateCount`, `DistinguishedName`

---

## 8. Scripts de sante AD

### 8.1 Test-ADReplicationHealth

**But :** Verifier l'etat de la replication AD entre tous les controleurs de domaine.

**Ce script est en lecture seule.**

**Exemples :**

```powershell
# Verification de la replication
.\Test-ADReplicationHealth.ps1

# Avec logging et notification email
.\Test-ADReplicationHealth.ps1 -EnableLogging -EmailTo "admin@corp.local" -SmtpServer "smtp.corp.local"
```

**Colonnes du rapport CSV :**
`SourceDC`, `SourceSite`, `Partner`, `PartitionDN`, `LastReplicationSuccess`, `MinutesSinceReplication`, `LastReplicationResult`, `ConsecutiveFailures`, `Status`

**Statuts possibles :** `OK`, `ERROR`, `UNREACHABLE`

---

### 8.2 Test-ADFSMORoles

**But :** Auditer les 5 roles FSMO et l'etat des controleurs de domaine.

**Ce script est en lecture seule.**

**Roles FSMO verifies :**
- Schema Master (Foret)
- Domain Naming Master (Foret)
- PDC Emulator (Domaine)
- RID Master (Domaine)
- Infrastructure Master (Domaine)

**Exemples :**

```powershell
# Audit FSMO et DCs
.\Test-ADFSMORoles.ps1

# Avec logging
.\Test-ADFSMORoles.ps1 -EnableLogging
```

**Colonnes du rapport CSV :**
`Type`, `Name`, `Scope`, `Holder`, `Status`, `Details`

---

## 9. Workflow de nettoyage recommande

### Workflow mensuel recommande

```
Semaine 1 : AUDIT
  1. Find-ADPrivilegedAccounts       -> Verifier les comptes a privileges
  2. Find-ADPasswordNeverExpires     -> Identifier les risques de securite
  3. Find-ADStalePasswords           -> Identifier les mots de passe anciens
  4. Find-ADDuplicateSPN             -> Verifier l'integrite Kerberos
  5. Test-ADReplicationHealth        -> Verifier la replication
  6. Test-ADFSMORoles                -> Verifier les roles FSMO

Semaine 2 : NETTOYAGE OBJETS
  1. Find-ADInactiveUsers -DisableUsers -QuarantineOU "..."
  2. Find-ADInactiveComputers -DisableObjects -QuarantineOU "..."
  3. Find-ADDisabledInGroups -RemoveMemberships

Semaine 3 : NETTOYAGE STRUCTURE
  1. Find-ADEmptyGroups              -> Rapport des groupes vides
  2. Find-ADEmptyOU                  -> Rapport des OUs vides
  3. Find-ADUnlinkedGPO              -> Rapport des GPOs orphelines
  4. Find-ADObsoleteOS               -> Rapport des OS obsoletes

Semaine 4 : SUPPRESSION (apres validation des rapports)
  1. Find-ADInactiveUsers -SearchBase "OU=Quarantine,..." -DeleteUsers
  2. Find-ADInactiveComputers -SearchBase "OU=Quarantine,..." -DeleteObjects
  3. Find-ADEmptyGroups -DeleteObjects
```

### Workflow pour les comptes utilisateurs

```
                 Actif
                   |
         (Inactif > 90 jours)
                   |
                   v
    Desactiver (-DisableUsers)
                   |
    Deplacer vers quarantaine (-QuarantineOU)
                   |
         (Attendre 30 jours)
                   |
                   v
    Supprimer (-DeleteUsers -SearchBase "OU=Quarantine,...")
```

---

## 10. Planification des taches

### Exemple : Tache planifiee pour le rapport hebdomadaire

```powershell
# Creer une tache planifiee (a executer en tant qu'administrateur)
$Action = New-ScheduledTaskAction -Execute 'powershell.exe' `
  -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\PS-ManageInactiveAD\Find-ADInactiveUsers.ps1" -EnableLogging -EmailTo "admin@corp.local" -SmtpServer "smtp.corp.local"'

$Trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At '06:00'

$Settings = New-ScheduledTaskSettingsSet -RunOnlyIfNetworkAvailable -StartWhenAvailable

Register-ScheduledTask -TaskName 'AD-InactiveUsersReport' `
  -Action $Action -Trigger $Trigger -Settings $Settings `
  -User 'DOMAIN\svc-admanagement' -Password 'MotDePasse' `
  -Description 'Rapport hebdomadaire des utilisateurs AD inactifs'
```

### Exemple : Script d'execution groupee

```powershell
# RunAllReports.ps1 - Executer tous les rapports en une seule fois
$ScriptPath = 'C:\Scripts\PS-ManageInactiveAD'
$CommonParams = @{
  EnableLogging = $true
  EmailTo       = 'admin@corp.local'
  SmtpServer    = 'smtp.corp.local'
}

& "$ScriptPath\Find-ADInactiveUsers.ps1" @CommonParams
& "$ScriptPath\Find-ADInactiveComputers.ps1" @CommonParams
& "$ScriptPath\Find-ADEmptyGroups.ps1" @CommonParams
& "$ScriptPath\Find-ADEmptyOU.ps1" @CommonParams
& "$ScriptPath\Find-ADLockedAccounts.ps1" @CommonParams
& "$ScriptPath\Find-ADPasswordNeverExpires.ps1" @CommonParams
& "$ScriptPath\Find-ADStalePasswords.ps1" @CommonParams
& "$ScriptPath\Find-ADPrivilegedAccounts.ps1" @CommonParams
& "$ScriptPath\Find-ADDisabledInGroups.ps1" @CommonParams
& "$ScriptPath\Find-ADObsoleteOS.ps1" @CommonParams
& "$ScriptPath\Find-ADUnlinkedGPO.ps1" @CommonParams
& "$ScriptPath\Find-ADDuplicateSPN.ps1" @CommonParams
& "$ScriptPath\Test-ADReplicationHealth.ps1" @CommonParams
& "$ScriptPath\Test-ADFSMORoles.ps1" @CommonParams
```

---

## 11. Depannage

### Erreurs courantes

| Erreur | Cause | Solution |
|--------|-------|----------|
| `Required file not found: ADManagement-Common.ps1` | Fichier commun absent | Verifier que `ADManagement-Common.ps1` est dans le meme dossier |
| `The term 'Get-ADUser' is not recognized` | Module AD absent | Installer RSAT : `Install-WindowsFeature RSAT-AD-PowerShell` |
| `Access is denied` | Droits insuffisants | Executer en tant qu'administrateur ou avec un compte delegue |
| `Unable to contact the server` | DC injoignable | Verifier la connectivite reseau et DNS |
| `Protect from Accidental Deletion` | OU protegee | Retirer la protection dans ADUC avant suppression |
| `The term 'Get-GPO' is not recognized` | Module GroupPolicy absent | Installer GPMC : `Install-WindowsFeature GPMC` |

### Limitations connues

- **LastLogonDate** : Cette propriete est basee sur `LastLogonTimestamp` qui n'est replique qu'environ tous les 9-14 jours entre les DCs. Pour une valeur precise, interroger `LastLogon` sur chaque DC individuellement.
- **Send-MailMessage** : Cmdlet marquee comme obsolete dans PowerShell 7+ mais toujours fonctionnelle. Pour un usage en production long terme, envisager Microsoft Graph API.
- **Comptes de service geres (gMSA/MSA)** : Les scripts ne distinguent pas les gMSA des comptes utilisateur classiques. Utiliser `-ExcludeOU` pour exclure les OUs contenant des gMSA.

### Verifier les logs

```powershell
# Lister les fichiers de log
Get-ChildItem C:\tmp\Logs\ -Filter *.log | Sort-Object LastWriteTime -Descending

# Lire le dernier log
Get-Content (Get-ChildItem C:\tmp\Logs\ -Filter *.log | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
```

---

## Conversion en PDF

Pour generer une version PDF de cette documentation :

**Avec pandoc (recommande) :**
```powershell
pandoc Documentation.md -o Documentation.pdf --pdf-engine=xelatex
```

**Avec Chrome/Edge :**
1. Ouvrir `Documentation.md` dans un editeur Markdown (VS Code, Typora...)
2. Exporter en HTML ou ouvrir dans le navigateur
3. Imprimer > Enregistrer en PDF

---

*Documentation generee pour PS-ManageInactiveAD v2.0*
