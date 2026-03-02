# PS-ManageInactiveAD

## Boite a outils de gestion Active Directory

Suite complete de scripts PowerShell pour auditer, nettoyer et maintenir un environnement Active Directory.

**Compatible :** Windows Server 2022, Windows Server 2025 (PowerShell 5.1+)

## Scripts disponibles

### Nettoyage AD
| Script | Description | Actions |
|--------|-------------|---------|
| `Find-ADInactiveUsers.ps1` | Utilisateurs inactifs | Rapport, Desactiver, Quarantaine, Supprimer |
| `Find-ADInactiveComputers.ps1` | Ordinateurs inactifs | Rapport, Desactiver, Quarantaine, Supprimer |
| `Find-ADEmptyGroups.ps1` | Groupes vides | Rapport, Supprimer |
| `Find-ADEmptyOU.ps1` | OUs vides | Rapport, Supprimer |

### Audit securite
| Script | Description | Actions |
|--------|-------------|---------|
| `Find-ADLockedAccounts.ps1` | Comptes verrouilles | Rapport, Deverrouiller |
| `Find-ADPasswordNeverExpires.ps1` | Mots de passe non-expirants | Rapport, Retirer le flag |
| `Find-ADStalePasswords.ps1` | Mots de passe anciens | Rapport, Forcer le changement |
| `Find-ADPrivilegedAccounts.ps1` | Comptes privilegies | Rapport (lecture seule) |

### Maintenance
| Script | Description | Actions |
|--------|-------------|---------|
| `Find-ADDisabledInGroups.ps1` | Comptes desactives dans des groupes | Rapport, Retirer les appartenances |
| `Find-ADObsoleteOS.ps1` | OS obsoletes | Rapport (lecture seule) |
| `Find-ADUnlinkedGPO.ps1` | GPOs orphelines | Rapport, Supprimer |
| `Find-ADDuplicateSPN.ps1` | SPNs dupliques | Rapport (lecture seule) |

### Sante AD
| Script | Description |
|--------|-------------|
| `Test-ADReplicationHealth.ps1` | Etat de la replication AD |
| `Test-ADFSMORoles.ps1` | Roles FSMO et DCs |

## Prerequis

- Windows Server 2022 ou 2025 (ou Windows 10/11 avec RSAT)
- PowerShell 5.1+
- Module ActiveDirectory (RSAT)
- Module GroupPolicy (pour `Find-ADUnlinkedGPO.ps1` uniquement)

```powershell
# Installation RSAT sur Server
Install-WindowsFeature -Name RSAT-AD-PowerShell
Install-WindowsFeature -Name GPMC
```

## Utilisation rapide

```powershell
# Rapport simple (mode safe - aucune modification)
.\Find-ADInactiveUsers.ps1

# Rapport avec chemin personnalise
.\Find-ADInactiveUsers.ps1 -ReportFilePath 'C:\tmp\MonRapport.csv'

# Simuler une action sans rien modifier
.\Find-ADInactiveUsers.ps1 -DisableUsers -WhatIf

# Desactiver + deplacer en quarantaine
.\Find-ADInactiveUsers.ps1 -DisableUsers -QuarantineOU "OU=Disabled,DC=corp,DC=local"

# Avec logging et notification email
.\Find-ADInactiveUsers.ps1 -EnableLogging -EmailTo "admin@corp.local" -SmtpServer "smtp.corp.local"
```

## Parametres communs a tous les scripts

| Parametre | Description |
|-----------|-------------|
| `-ReportFilePath` | Chemin du rapport CSV (defaut: `C:\tmp\`) |
| `-EnableLogging` | Active les logs dans `C:\tmp\Logs\` |
| `-EmailTo` / `-SmtpServer` | Notification email |
| `-SearchBase` | Restreindre la recherche a une OU |
| `-ExcludeOU` | Exclure des OUs des resultats |
| `-WhatIf` | Simuler les actions |
| `-Confirm` | Confirmation par item |

## Fichier commun obligatoire

Le fichier `ADManagement-Common.ps1` doit TOUJOURS etre dans le meme repertoire que les scripts. Il contient les fonctions partagees (logging, export CSV, email, quarantaine).

## Documentation

- **Markdown** : `Documentation.md`
- **PDF** : Ouvrir `Documentation.html` dans un navigateur > Ctrl+P > Enregistrer en PDF

La documentation complete inclut : parametres detailles, exemples, workflow de nettoyage recommande, planification des taches, et guide de depannage.

## Licence

Voir le fichier [LICENSE](LICENSE).
