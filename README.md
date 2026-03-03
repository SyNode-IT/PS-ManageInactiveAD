# PS-ManageInactiveAD

## Boîte à outils de gestion Active Directory

Suite complète de scripts PowerShell pour auditer, nettoyer et maintenir un environnement Active Directory.

**Compatible :** Windows Server 2022, Windows Server 2025 (PowerShell 5.1+)

## Scripts disponibles

### Audit complet
| Script | Description |
|--------|-------------|
| `Invoke-ADFullAudit.ps1` | **Lance les 14 scripts d'un coup** et génère un tableau de bord HTML récapitulatif |

### Nettoyage AD
| Script | Description | Actions |
|--------|-------------|---------|
| `Find-ADInactiveUsers.ps1` | Utilisateurs inactifs | Rapport, Désactiver, Quarantaine, Supprimer |
| `Find-ADInactiveComputers.ps1` | Ordinateurs inactifs | Rapport, Désactiver, Quarantaine, Supprimer |
| `Find-ADEmptyGroups.ps1` | Groupes vides | Rapport, Supprimer |
| `Find-ADEmptyOU.ps1` | OUs vides | Rapport, Supprimer |

### Audit sécurité
| Script | Description | Actions |
|--------|-------------|---------|
| `Find-ADLockedAccounts.ps1` | Comptes verrouillés | Rapport, Déverrouiller |
| `Find-ADPasswordNeverExpires.ps1` | Mots de passe non-expirants | Rapport, Retirer le flag |
| `Find-ADStalePasswords.ps1` | Mots de passe anciens | Rapport, Forcer le changement |
| `Find-ADPrivilegedAccounts.ps1` | Comptes privilégiés | Rapport (lecture seule) |

### Maintenance
| Script | Description | Actions |
|--------|-------------|---------|
| `Find-ADDisabledInGroups.ps1` | Comptes désactivés dans des groupes | Rapport, Retirer les appartenances |
| `Find-ADObsoleteOS.ps1` | OS obsolètes | Rapport (lecture seule) |
| `Find-ADUnlinkedGPO.ps1` | GPOs orphelines | Rapport, Supprimer |
| `Find-ADDuplicateSPN.ps1` | SPNs dupliqués | Rapport (lecture seule) |

### Santé AD
| Script | Description |
|--------|-------------|
| `Test-ADReplicationHealth.ps1` | État de la réplication AD |
| `Test-ADFSMORoles.ps1` | Rôles FSMO et DCs |

## Prérequis

- Windows Server 2022 ou 2025 (ou Windows 10/11 avec RSAT)
- PowerShell 5.1+
- Module ActiveDirectory (RSAT)
- Module GroupPolicy (pour `Find-ADUnlinkedGPO.ps1` uniquement)

```powershell
# Installation RSAT sur Server
Install-WindowsFeature -Name RSAT-AD-PowerShell
Install-WindowsFeature -Name GPMC
```

## Installation

**Option 1 — Téléchargement direct (recommandé) :**

Télécharger le ZIP depuis GitHub : [Download ZIP](https://github.com/SyNode-IT/PS-ManageInactiveAD/archive/refs/heads/main.zip), puis extraire dans `C:\Scripts\PS-ManageInactiveAD\`.

Ou via PowerShell :
```powershell
Invoke-WebRequest -Uri "https://github.com/SyNode-IT/PS-ManageInactiveAD/archive/refs/heads/main.zip" -OutFile "$env:TEMP\PS-ManageInactiveAD.zip"
Expand-Archive -Path "$env:TEMP\PS-ManageInactiveAD.zip" -DestinationPath "C:\Scripts" -Force
Rename-Item "C:\Scripts\PS-ManageInactiveAD-main" "C:\Scripts\PS-ManageInactiveAD"
```

**Option 2 — Avec Git (si installé) :**
```powershell
git clone https://github.com/SyNode-IT/PS-ManageInactiveAD.git C:\Scripts\PS-ManageInactiveAD
```

## Utilisation rapide

```powershell
# Audit complet (lance tout et ouvre un tableau de bord)
.\Invoke-ADFullAudit.ps1

# Rapport simple (mode safe - aucune modification)
.\Find-ADInactiveUsers.ps1

# Rapport avec chemin personnalisé
.\Find-ADInactiveUsers.ps1 -ReportFilePath 'D:\Exports\MonRapport.csv'

# Simuler une action sans rien modifier
.\Find-ADInactiveUsers.ps1 -DisableUsers -WhatIf

# Désactiver + déplacer en quarantaine
.\Find-ADInactiveUsers.ps1 -DisableUsers -QuarantineOU "OU=Disabled,DC=corp,DC=local"

# Avec logging et notification email
.\Find-ADInactiveUsers.ps1 -EnableLogging -EmailTo "admin@corp.local" -SmtpServer "smtp.corp.local"
```

## Rapports

Chaque script génère automatiquement **deux rapports** :
- **CSV** : données brutes, exploitables dans Excel ou par d'autres scripts
- **HTML** : rapport visuel stylisé avec cartes résumé, couleurs de statut et table responsive

Les rapports sont enregistrés dans le sous-dossier `Rapports\` du répertoire des scripts. Le rapport HTML s'ouvre automatiquement à la fin de l'exécution (désactivable avec `-NoOpen`).

Le script `Invoke-ADFullAudit.ps1` génère en plus un **tableau de bord** HTML récapitulatif avec des liens vers chaque rapport individuel.

## Paramètres communs à tous les scripts

| Paramètre | Description |
|-----------|-------------|
| `-ReportFilePath` | Chemin du rapport CSV (défaut : `Rapports\<NomScript>.csv`) |
| `-NoOpen` | Désactive l'ouverture auto du rapport HTML (pour les tâches planifiées) |
| `-EnableLogging` | Active les logs dans `Rapports\Logs\` |
| `-EmailTo` / `-SmtpServer` | Notification email |
| `-SearchBase` | Restreindre la recherche à une OU |
| `-ExcludeOU` | Exclure des OUs des résultats |
| `-WhatIf` | Simuler les actions |
| `-Confirm` | Confirmation par item |

## Fichier commun obligatoire

Le fichier `ADManagement-Common.ps1` doit **toujours** être dans le même répertoire que les scripts. Il contient les fonctions partagées (logging, export CSV/HTML, email, quarantaine).

## Documentation

La documentation technique complète est disponible ici : [`Documentation.html`](Documentation.html)

Elle couvre : paramètres détaillés de chaque script, exemples d'utilisation, workflow de nettoyage recommandé, planification des tâches, et guide de dépannage.

## Licence

Voir le fichier [LICENSE](LICENSE).
