#requires -version 5.1
#requires -Modules ActiveDirectory
<#
.SYNOPSIS
  Exécute un audit complet de l'Active Directory et génère un tableau de bord HTML.

.DESCRIPTION
  Script orchestrateur qui lance les 14 scripts d'audit séquentiellement et produit
  un tableau de bord HTML récapitulatif avec liens vers chaque rapport individuel.
  Compatible avec Windows Server 2022 et Windows Server 2025 (PowerShell 5.1+).

  Les rapports individuels (CSV + HTML) sont générés dans le dossier Rapports\.
  Le tableau de bord maître est généré dans Rapports\FullAudit_yyyyMMdd_HHmmss.html.

.PARAMETER DaysInactive
  Optionnel. Nombre de jours d'inactivité pour les scripts utilisateurs/ordinateurs. Défaut : 90.

.PARAMETER SearchBase
  Optionnel. Chemin LDAP pour restreindre la recherche.

.PARAMETER ExcludeOU
  Optionnel. Tableau de DN d'OUs à exclure des résultats.

.PARAMETER NoOpen
  Optionnel. Désactive l'ouverture automatique du tableau de bord (pour les tâches planifiées).

.PARAMETER EnableLogging
  Optionnel. Active les logs dans Rapports\Logs\.

.PARAMETER EmailTo
  Optionnel. Adresse(s) email du/des destinataire(s).

.PARAMETER SmtpServer
  Optionnel. Serveur SMTP pour l'envoi.

.PARAMETER EmailFrom
  Optionnel. Adresse email de l'expéditeur.

.PARAMETER SkipGPO
  Optionnel. Ignore le script Find-ADUnlinkedGPO (si le module GroupPolicy n'est pas installé).

.NOTES
  Version:        2.1
  Creation Date:  2026
  Compatible:     Windows Server 2022, Windows Server 2025

.EXAMPLE
  .\Invoke-ADFullAudit.ps1
  Lance l'audit complet et ouvre le tableau de bord.

.EXAMPLE
  .\Invoke-ADFullAudit.ps1 -NoOpen -EnableLogging -EmailTo "admin@corp.local" -SmtpServer "smtp.corp.local"
  Audit complet en mode silencieux avec logging et notification email.

.EXAMPLE
  .\Invoke-ADFullAudit.ps1 -DaysInactive 60 -SearchBase "OU=Paris,DC=corp,DC=local"
  Audit ciblé sur l'OU Paris avec un seuil de 60 jours.
#>

#---------------------------------------------------------[Script Parameters]------------------------------------------------------

[CmdletBinding()]
Param (
  [ValidateRange(1, 3650)]
  [int]$DaysInactive = 90,

  [string]$SearchBase,
  [string[]]$ExcludeOU,

  [switch]$NoOpen,
  [switch]$EnableLogging,
  [switch]$SkipGPO,

  [string[]]$EmailTo,
  [string]$SmtpServer,
  [string]$EmailFrom
)

#---------------------------------------------------------[Initialisations]--------------------------------------------------------

$ErrorActionPreference = 'Stop'

$CommonPath = Join-Path $PSScriptRoot 'ADManagement-Common.ps1'
if (-not (Test-Path $CommonPath)) {
  throw "Required file not found: $CommonPath. Ensure ADManagement-Common.ps1 is in the same directory."
}
. $CommonPath

Import-Module ActiveDirectory

#----------------------------------------------------------[Declarations]----------------------------------------------------------

$ScriptName = 'Invoke-ADFullAudit'
$Timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$ReportsDir = Join-Path $PSScriptRoot 'Rapports'
$DashboardPath = Join-Path $ReportsDir "FullAudit_$Timestamp.html"

if (-not (Test-Path $ReportsDir)) {
  New-Item -Path $ReportsDir -ItemType Directory -Force | Out-Null
}

#-----------------------------------------------------------[Script List]---------------------------------------------------------

$Scripts = @(
  @{ File = 'Find-ADInactiveUsers.ps1';       Desc = 'Utilisateurs inactifs';            Category = 'Nettoyage';  ExtraParams = @{ DaysInactive = $DaysInactive } }
  @{ File = 'Find-ADInactiveComputers.ps1';    Desc = 'Ordinateurs inactifs';             Category = 'Nettoyage';  ExtraParams = @{ DaysInactive = $DaysInactive } }
  @{ File = 'Find-ADEmptyGroups.ps1';          Desc = 'Groupes vides';                    Category = 'Nettoyage';  ExtraParams = @{} }
  @{ File = 'Find-ADEmptyOU.ps1';              Desc = 'OUs vides';                        Category = 'Nettoyage';  ExtraParams = @{} }
  @{ File = 'Find-ADLockedAccounts.ps1';       Desc = 'Comptes verrouilles';              Category = 'Securite';   ExtraParams = @{} }
  @{ File = 'Find-ADPasswordNeverExpires.ps1'; Desc = 'Mots de passe non-expirants';      Category = 'Securite';   ExtraParams = @{} }
  @{ File = 'Find-ADStalePasswords.ps1';       Desc = 'Mots de passe anciens';            Category = 'Securite';   ExtraParams = @{} }
  @{ File = 'Find-ADPrivilegedAccounts.ps1';   Desc = 'Comptes privilegies';              Category = 'Securite';   ExtraParams = @{} }
  @{ File = 'Find-ADDisabledInGroups.ps1';     Desc = 'Desactives dans des groupes';      Category = 'Maintenance'; ExtraParams = @{} }
  @{ File = 'Find-ADObsoleteOS.ps1';           Desc = 'OS obsoletes';                     Category = 'Maintenance'; ExtraParams = @{} }
  @{ File = 'Find-ADUnlinkedGPO.ps1';          Desc = 'GPOs orphelines';                  Category = 'Maintenance'; ExtraParams = @{} }
  @{ File = 'Find-ADDuplicateSPN.ps1';         Desc = 'SPNs dupliques';                   Category = 'Maintenance'; ExtraParams = @{} }
  @{ File = 'Test-ADReplicationHealth.ps1';    Desc = 'Sante de la replication';           Category = 'Sante AD';   ExtraParams = @{} }
  @{ File = 'Test-ADFSMORoles.ps1';            Desc = 'Roles FSMO';                       Category = 'Sante AD';   ExtraParams = @{} }
)

#-----------------------------------------------------------[Execution]------------------------------------------------------------

Write-ADMBanner -ScriptName $ScriptName

if ($EnableLogging) { Start-ADMLogging -ScriptName $ScriptName }

Write-ADMLog "=== AUDIT COMPLET ACTIVE DIRECTORY ==="
Write-ADMLog "Parametres : DaysInactive=$DaysInactive | SearchBase=$SearchBase | SkipGPO=$SkipGPO"
Write-ADMLog ""

# Build common params
$CommonParams = @{ NoOpen = $true }
if ($SearchBase) { $CommonParams['SearchBase'] = $SearchBase }
if ($ExcludeOU)  { $CommonParams['ExcludeOU']  = $ExcludeOU }
if ($EnableLogging) { $CommonParams['EnableLogging'] = $true }

$AuditResults = @()
$TotalFindings  = 0
$ScriptsOK      = 0
$ScriptsError   = 0
$StartTime      = Get-Date

ForEach ($Script in $Scripts) {
  $ScriptPath = Join-Path $PSScriptRoot $Script.File
  $ScriptBaseName = [System.IO.Path]::GetFileNameWithoutExtension($Script.File)

  # Skip GPO script if requested
  if ($SkipGPO -and $Script.File -eq 'Find-ADUnlinkedGPO.ps1') {
    Write-ADMLog "  [SKIP] $ScriptBaseName (module GroupPolicy non requis / SkipGPO)"
    $AuditResults += [PSCustomObject]@{
      Script      = $ScriptBaseName
      Description = $Script.Desc
      Categorie   = $Script.Category
      Resultats   = '-'
      Statut      = 'IGNORE'
      Rapport     = ''
    }
    continue
  }

  if (-not (Test-Path $ScriptPath)) {
    Write-ADMLog "  [MISS] $ScriptBaseName - Fichier introuvable" -Level Warning
    $ScriptsError++
    $AuditResults += [PSCustomObject]@{
      Script      = $ScriptBaseName
      Description = $Script.Desc
      Categorie   = $Script.Category
      Resultats   = '-'
      Statut      = 'ABSENT'
      Rapport     = ''
    }
    continue
  }

  Write-ADMLog "  [RUN]  $ScriptBaseName..."

  try {
    # Merge common + extra params
    $RunParams = @{} + $CommonParams
    foreach ($Key in $Script.ExtraParams.Keys) {
      $RunParams[$Key] = $Script.ExtraParams[$Key]
    }

    # Filter params to only those accepted by the target script
    $ScriptCmd = Get-Command $ScriptPath
    $AcceptedParams = $ScriptCmd.Parameters.Keys
    $FilteredParams = @{}
    foreach ($Key in $RunParams.Keys) {
      if ($AcceptedParams -contains $Key) {
        $FilteredParams[$Key] = $RunParams[$Key]
      }
    }

    & $ScriptPath @FilteredParams

    # Count results from CSV
    $CsvPath = Join-Path $ReportsDir "$ScriptBaseName.csv"
    $HtmlPath = Join-Path $ReportsDir "$ScriptBaseName.html"
    $Count = 0

    if (Test-Path $CsvPath) {
      $CsvData = Import-Csv -Path $CsvPath -ErrorAction SilentlyContinue
      $Count = @($CsvData).Count
    }

    $TotalFindings += $Count
    $ScriptsOK++

    $AuditResults += [PSCustomObject]@{
      Script      = $ScriptBaseName
      Description = $Script.Desc
      Categorie   = $Script.Category
      Resultats   = $Count
      Statut      = 'OK'
      Rapport     = if (Test-Path $HtmlPath) { $HtmlPath } else { '' }
    }

    Write-ADMLog "  [OK]   $ScriptBaseName : $Count element(s)"
  }
  catch {
    $ScriptsError++
    Write-ADMLog "  [FAIL] $ScriptBaseName : $($_.Exception.Message)" -Level Warning

    $AuditResults += [PSCustomObject]@{
      Script      = $ScriptBaseName
      Description = $Script.Desc
      Categorie   = $Script.Category
      Resultats   = '-'
      Statut      = 'ERREUR'
      Rapport     = ''
    }
  }
}

$Duration = (Get-Date) - $StartTime
Write-ADMLog ""
Write-ADMLog "=== RESUME ==="
Write-ADMLog "Duree totale : $([math]::Round($Duration.TotalSeconds, 1))s"
Write-ADMLog "Scripts OK : $ScriptsOK | Erreurs : $ScriptsError | Elements trouves : $TotalFindings"

#-----------------------------------------------------------[Dashboard HTML]------------------------------------------------------

$GeneratedDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$DurationText = "$([math]::Round($Duration.TotalMinutes, 1)) min"

# Build table rows with links
$RowsHtml = foreach ($R in $AuditResults) {
  $StatusClass = switch ($R.Statut) {
    'OK'      { 'status-success' }
    'ERREUR'  { 'status-danger' }
    'ABSENT'  { 'status-danger' }
    'IGNORE'  { 'status-muted' }
    default   { '' }
  }

  $ReportLink = ''
  if ($R.Rapport -and (Test-Path $R.Rapport)) {
    $FileName = [System.IO.Path]::GetFileName($R.Rapport)
    $ReportLink = "<a href=`"$FileName`">Voir le rapport</a>"
  }

  $ResultsDisplay = $R.Resultats
  if ($R.Resultats -ne '-' -and [int]$R.Resultats -gt 0) {
    $ResultsDisplay = "<strong>$($R.Resultats)</strong>"
  }

  @"
        <tr>
          <td><strong>$($R.Script)</strong></td>
          <td>$($R.Description)</td>
          <td>$($R.Categorie)</td>
          <td style="text-align:center">$ResultsDisplay</td>
          <td class="$StatusClass" style="text-align:center">$($R.Statut)</td>
          <td style="text-align:center">$ReportLink</td>
        </tr>
"@
}

$DashboardHtml = @"
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Audit complet Active Directory</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: 'Segoe UI', Tahoma, Arial, sans-serif; background: #eef1f5; color: #2c3e50; }

  .header {
    background: linear-gradient(135deg, #1a5276 0%, #2980b9 100%);
    color: #fff; padding: 28px 36px; box-shadow: 0 2px 8px rgba(0,0,0,.15);
  }
  .header h1 { font-size: 24px; font-weight: 600; margin-bottom: 4px; }
  .header-meta { font-size: 13px; opacity: .85; }
  .header-desc { font-size: 14px; margin-top: 8px; opacity: .9; }

  .summary {
    display: flex; gap: 16px; padding: 24px 36px; flex-wrap: wrap;
  }
  .card {
    background: #fff; border-radius: 10px; padding: 18px 24px; flex: 1; min-width: 160px;
    text-align: center; box-shadow: 0 2px 6px rgba(0,0,0,.08); border-top: 3px solid #0078d4;
  }
  .card-value { font-size: 38px; font-weight: 700; line-height: 1.2; }
  .card-label { font-size: 11px; text-transform: uppercase; letter-spacing: .5px; color: #888; margin-top: 4px; }

  .table-container { padding: 0 36px 36px; overflow-x: auto; }
  table {
    width: 100%; border-collapse: collapse; background: #fff;
    border-radius: 10px; overflow: hidden; box-shadow: 0 2px 6px rgba(0,0,0,.08);
    font-size: 13px;
  }
  thead th {
    background: #2c3e50; color: #fff; padding: 12px 16px; text-align: left;
    font-weight: 600; font-size: 12px; text-transform: uppercase; letter-spacing: .3px;
    position: sticky; top: 0;
  }
  tbody td { padding: 10px 16px; border-bottom: 1px solid #f0f0f0; }
  tbody tr:hover { background: #f0f7ff; }
  tbody tr:nth-child(even) { background: #fafbfc; }
  tbody tr:nth-child(even):hover { background: #f0f7ff; }

  .status-success { color: #28a745; font-weight: 600; }
  .status-warning { color: #e67e22; font-weight: 600; }
  .status-danger  { color: #dc3545; font-weight: 600; }
  .status-info    { color: #0078d4; font-weight: 600; }
  .status-muted   { color: #999; font-weight: 600; }

  a { color: #0078d4; text-decoration: none; }
  a:hover { text-decoration: underline; }

  .footer {
    text-align: center; padding: 20px 36px; color: #aaa; font-size: 11px;
    border-top: 1px solid #ddd; margin-top: 12px;
  }
  .footer a { color: #0078d4; text-decoration: none; }

  @media print {
    body { background: #fff; }
    .header { box-shadow: none; }
    .card, table { box-shadow: none; border: 1px solid #ddd; }
    thead th { position: static; }
  }
  @media (max-width: 768px) {
    .summary { flex-direction: column; }
    .table-container, .summary, .header { padding-left: 16px; padding-right: 16px; }
  }
</style>
</head>
<body>

  <div class="header">
    <h1>&#128736; Audit complet Active Directory</h1>
    <div class="header-meta">G&eacute;n&eacute;r&eacute; le $GeneratedDate &mdash; Dur&eacute;e : $DurationText</div>
    <div class="header-desc">Analyse compl&egrave;te de l'environnement AD : nettoyage, s&eacute;curit&eacute;, maintenance et sant&eacute;</div>
  </div>

  <div class="summary">
    <div class="card">
      <div class="card-value" style="color:#0078d4">$($AuditResults.Count)</div>
      <div class="card-label">Scripts ex&eacute;cut&eacute;s</div>
    </div>
    <div class="card">
      <div class="card-value" style="color:#dc3545">$TotalFindings</div>
      <div class="card-label">&Eacute;l&eacute;ments trouv&eacute;s</div>
    </div>
    <div class="card">
      <div class="card-value" style="color:#28a745">$ScriptsOK</div>
      <div class="card-label">Succ&egrave;s</div>
    </div>
    <div class="card">
      <div class="card-value" style="color:$(if ($ScriptsError -gt 0) { '#dc3545' } else { '#28a745' })">$ScriptsError</div>
      <div class="card-label">Erreurs</div>
    </div>
  </div>

  <div class="table-container">
    <table>
      <thead>
      <tr>
        <th>Script</th>
        <th>Description</th>
        <th>Cat&eacute;gorie</th>
        <th style="text-align:center">R&eacute;sultats</th>
        <th style="text-align:center">Statut</th>
        <th style="text-align:center">Rapport</th>
      </tr>
      </thead>
      <tbody>
$($RowsHtml -join "`n")
      </tbody>
    </table>
  </div>

  <div class="footer">
    PS-ManageInactiveAD v2.1 &mdash;
    <a href="../Documentation.html">Documentation</a> |
    <a href="https://github.com/SyNode-IT/PS-ManageInactiveAD">GitHub</a>
  </div>

</body>
</html>
"@

$DashboardHtml | Out-File -FilePath $DashboardPath -Encoding UTF8
Write-ADMLog "Tableau de bord : $DashboardPath"

# Send email with dashboard
Send-ADMReport -EmailTo $EmailTo -EmailFrom $EmailFrom -SmtpServer $SmtpServer `
  -Subject "[$ScriptName] Audit complet - $TotalFindings elements trouves ($ScriptsOK OK / $ScriptsError erreurs)" `
  -Attachments $DashboardPath

if ($EnableLogging) { Stop-ADMLogging }

if (-not $NoOpen) { Open-ADMReport -Path $DashboardPath }

Write-ADMBanner -ScriptName $ScriptName -IsEnd
