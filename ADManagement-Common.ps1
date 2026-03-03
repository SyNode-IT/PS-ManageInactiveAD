#requires -version 5.1
<#
.SYNOPSIS
  Common functions shared by all AD management scripts.

.DESCRIPTION
  This file is dot-sourced by all AD management scripts in the toolkit.
  It provides logging, reporting (CSV + HTML), email notification,
  exclusion filtering, and quarantine functions.

  DO NOT execute this file directly. It is loaded automatically by the scripts.

.NOTES
  Version:        2.1
  Compatible:     Windows Server 2022, Windows Server 2025 (PowerShell 5.1+)
#>

#-----------------------------------------------------------[Logging]--------------------------------------------------------------

$script:LogFile = $null

function Start-ADMLogging {
  <#
  .SYNOPSIS
    Starts logging to a timestamped file.
  #>
  param(
    [string]$LogDirectory,
    [string]$ScriptName = 'ADManagement'
  )

  if (-not $LogDirectory) {
    $LogDirectory = Join-Path $PSScriptRoot 'Rapports\Logs'
  }

  if (-not (Test-Path $LogDirectory)) {
    New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
  }

  $Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  $script:LogFile = Join-Path $LogDirectory "${ScriptName}_${Timestamp}.log"
  Write-ADMLog "Logging started: $($script:LogFile)"
  return $script:LogFile
}

function Stop-ADMLogging {
  <#
  .SYNOPSIS
    Stops logging.
  #>
  if ($script:LogFile) {
    Write-ADMLog "Logging stopped."
    $script:LogFile = $null
  }
}

function Write-ADMLog {
  <#
  .SYNOPSIS
    Writes a timestamped log entry to console and optionally to a log file.
  #>
  param(
    [Parameter(Mandatory = $true)]
    [string]$Message,

    [ValidateSet('Info', 'Warning', 'Error')]
    [string]$Level = 'Info'
  )

  $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $LogLine = "[$Timestamp] [$Level] $Message"

  switch ($Level) {
    'Info'    { Write-Host $LogLine }
    'Warning' { Write-Host $LogLine -ForegroundColor Yellow }
    'Error'   { Write-Host $LogLine -ForegroundColor Red }
  }

  if ($script:LogFile) {
    Add-Content -Path $script:LogFile -Value $LogLine -ErrorAction SilentlyContinue
  }
}

#-----------------------------------------------------------[Report Paths]--------------------------------------------------------

function Resolve-ADMReportPath {
  <#
  .SYNOPSIS
    Resolves the report base path. If not specified, defaults to $PSScriptRoot\Rapports\<ScriptName>.
    Returns a hashtable with CsvPath and HtmlPath.
  #>
  param(
    [string]$ReportFilePath,
    [string]$ScriptName,
    [string]$CallerPSScriptRoot
  )

  if (-not $ReportFilePath) {
    $ReportsDir = Join-Path $CallerPSScriptRoot 'Rapports'
    $ReportFilePath = Join-Path $ReportsDir "$ScriptName.csv"
  }

  # Ensure .csv extension
  if ($ReportFilePath -notlike '*.csv') {
    $ReportFilePath = "$ReportFilePath.csv"
  }

  $HtmlPath = [System.IO.Path]::ChangeExtension($ReportFilePath, '.html')

  return @{
    CsvPath  = $ReportFilePath
    HtmlPath = $HtmlPath
  }
}

#-----------------------------------------------------------[CSV Output]-----------------------------------------------------------

function New-ADMOutputDirectory {
  <#
  .SYNOPSIS
    Creates the parent directory for a file path if it does not exist.
  #>
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $Dir = Split-Path -Path $Path -Parent
  if ($Dir -and -not (Test-Path $Dir)) {
    New-Item -Path $Dir -ItemType Directory -Force | Out-Null
    Write-ADMLog "Created directory: $Dir"
  }
}

function Export-ADMReport {
  <#
  .SYNOPSIS
    Exports data to a CSV report file with automatic directory creation.
  #>
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyCollection()]
    [array]$Data,

    [Parameter(Mandatory = $true)]
    [string]$Path,

    [string]$ReportName = 'Report'
  )

  Write-ADMLog "Creating CSV $ReportName at [$Path]..."

  try {
    New-ADMOutputDirectory -Path $Path
    $Data | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
    Write-ADMLog "CSV saved ($($Data.Count) entries)."
  }
  catch {
    Write-ADMLog "Failed to create CSV: $($_.Exception.Message)" -Level Error
    throw
  }
}

#-----------------------------------------------------------[HTML Output]----------------------------------------------------------

function Export-ADMHTMLReport {
  <#
  .SYNOPSIS
    Exports data to a styled HTML report (GPOZaurr-like).
  #>
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyCollection()]
    [array]$Data,

    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string]$Title,

    [string]$Description = '',

    [string]$ScriptName = 'PS-ManageInactiveAD',

    # Summary cards: @( @{Label='Total';Value=42;Color='#0078d4'}, ... )
    [array]$SummaryCards = @(),

    # Status column color mapping: @{ 'ColumnName' = @{ 'OK'='success'; 'ERROR'='danger' } }
    [hashtable]$StatusMappings = @{}
  )

  Write-ADMLog "Creating HTML report at [$Path]..."

  try {
    New-ADMOutputDirectory -Path $Path

    # Build summary cards HTML
    $SummaryHtml = ''
    if ($SummaryCards.Count -gt 0) {
      $CardsHtml = foreach ($Card in $SummaryCards) {
        $Color = if ($Card.Color) { $Card.Color } else { '#0078d4' }
        @"
      <div class="card">
        <div class="card-value" style="color:$Color">$($Card.Value)</div>
        <div class="card-label">$($Card.Label)</div>
      </div>
"@
      }
      $SummaryHtml = @"
    <div class="summary">
$($CardsHtml -join "`n")
    </div>
"@
    }

    # Build table
    $TableHtml = ''
    if ($Data.Count -gt 0) {
      $Columns = $Data[0].PSObject.Properties.Name

      # Table header
      $ThCells = foreach ($Col in $Columns) {
        "          <th>$Col</th>"
      }
      $TheadHtml = $ThCells -join "`n"

      # Table rows
      $RowsHtml = foreach ($Row in $Data) {
        $TdCells = foreach ($Col in $Columns) {
          $Value = $Row.$Col
          if ($null -eq $Value) { $Value = '' }
          $CssClass = ''

          # Apply status mapping if column matches
          if ($StatusMappings.ContainsKey($Col)) {
            $Map = $StatusMappings[$Col]
            $ValStr = "$Value"
            if ($Map.ContainsKey($ValStr)) {
              $CssClass = " class=`"status-$($Map[$ValStr])`""
            }
          }

          "          <td$CssClass>$Value</td>"
        }
        "        <tr>`n$($TdCells -join "`n")`n        </tr>"
      }

      $TableHtml = @"
    <div class="table-container">
      <table>
        <thead>
        <tr>
$TheadHtml
        </tr>
        </thead>
        <tbody>
$($RowsHtml -join "`n")
        </tbody>
      </table>
    </div>
"@
    }
    else {
      $TableHtml = '    <div class="no-data">Aucun r&eacute;sultat trouv&eacute;.</div>'
    }

    $GeneratedDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $DescHtml = if ($Description) { "      <div class=`"header-desc`">$Description</div>" } else { '' }

    $Html = @"
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>$Title</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: 'Segoe UI', Tahoma, Arial, sans-serif; background: #eef1f5; color: #2c3e50; }

  .header {
    background: linear-gradient(135deg, #0078d4 0%, #00a4ef 100%);
    color: #fff; padding: 28px 36px; box-shadow: 0 2px 8px rgba(0,0,0,.15);
  }
  .header h1 { font-size: 22px; font-weight: 600; margin-bottom: 4px; }
  .header-meta { font-size: 13px; opacity: .85; }
  .header-desc { font-size: 14px; margin-top: 8px; opacity: .9; }

  .summary {
    display: flex; gap: 16px; padding: 24px 36px; flex-wrap: wrap;
  }
  .card {
    background: #fff; border-radius: 10px; padding: 18px 24px; flex: 1; min-width: 140px;
    text-align: center; box-shadow: 0 2px 6px rgba(0,0,0,.08); border-top: 3px solid #0078d4;
  }
  .card-value { font-size: 34px; font-weight: 700; line-height: 1.2; }
  .card-label { font-size: 11px; text-transform: uppercase; letter-spacing: .5px; color: #888; margin-top: 4px; }

  .table-container {
    padding: 0 36px 36px; overflow-x: auto;
  }
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
  .status-muted   { color: #999; }

  .no-data {
    text-align: center; padding: 60px 20px; color: #999; font-size: 16px;
    background: #fff; border-radius: 10px; margin: 0 36px 36px;
    box-shadow: 0 2px 6px rgba(0,0,0,.08);
  }

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
    <h1>$Title</h1>
    <div class="header-meta">G&eacute;n&eacute;r&eacute; le $GeneratedDate &mdash; $ScriptName</div>
$DescHtml
  </div>

$SummaryHtml

$TableHtml

  <div class="footer">
    PS-ManageInactiveAD v2.1 &mdash;
    <a href="../Documentation.html">Documentation</a> |
    <a href="https://github.com/SyNode-IT/PS-ManageInactiveAD">GitHub</a>
  </div>

</body>
</html>
"@

    $Html | Out-File -FilePath $Path -Encoding UTF8
    Write-ADMLog "HTML report saved."
  }
  catch {
    Write-ADMLog "Failed to create HTML report: $($_.Exception.Message)" -Level Warning
  }
}

#-----------------------------------------------------------[Open Report]---------------------------------------------------------

function Open-ADMReport {
  <#
  .SYNOPSIS
    Opens a report file in the default browser/application.
  #>
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if (Test-Path $Path) {
    Write-ADMLog "Opening report: $Path"
    Start-Process $Path
  }
}

#-----------------------------------------------------------[Email]----------------------------------------------------------------

function Send-ADMReport {
  <#
  .SYNOPSIS
    Sends a report by email via SMTP. Skips silently if parameters are missing.
  #>
  param(
    [string[]]$EmailTo,
    [string]$EmailFrom,
    [string]$SmtpServer,
    [string]$Subject,
    [string]$Body = 'See attached report.',
    [string[]]$Attachments,
    [int]$SmtpPort = 25
  )

  if (-not $EmailTo -or -not $SmtpServer) {
    return
  }

  if (-not $EmailFrom) {
    $EmailFrom = "ADManagement@$($env:USERDNSDOMAIN)"
  }

  try {
    $MailParams = @{
      To         = $EmailTo
      From       = $EmailFrom
      SmtpServer = $SmtpServer
      Subject    = $Subject
      Body       = $Body
      Port       = $SmtpPort
    }

    if ($Attachments) {
      $MailParams['Attachments'] = $Attachments
    }

    Send-MailMessage @MailParams -ErrorAction Stop
    Write-ADMLog "Email sent to: $($EmailTo -join ', ')"
  }
  catch {
    Write-ADMLog "Failed to send email: $($_.Exception.Message)" -Level Warning
  }
}

#-----------------------------------------------------------[Filtering]------------------------------------------------------------

function Test-ADMExcludedOU {
  <#
  .SYNOPSIS
    Tests whether a DistinguishedName belongs to one of the excluded OUs.
  #>
  param(
    [Parameter(Mandatory = $true)]
    [string]$DistinguishedName,

    [string[]]$ExcludeOUs
  )

  if (-not $ExcludeOUs) { return $false }

  foreach ($OU in $ExcludeOUs) {
    if ($DistinguishedName -like "*,$OU" -or $DistinguishedName -eq $OU) {
      return $true
    }
  }

  return $false
}

#-----------------------------------------------------------[Quarantine]-----------------------------------------------------------

function Move-ADMToQuarantine {
  <#
  .SYNOPSIS
    Moves an AD object to a quarantine OU.
  #>
  param(
    [Parameter(Mandatory = $true)]
    [string]$Identity,

    [Parameter(Mandatory = $true)]
    [string]$Name,

    [Parameter(Mandatory = $true)]
    [string]$QuarantineOU,

    [string]$ObjectType = 'Object'
  )

  try {
    Move-ADObject -Identity $Identity -TargetPath $QuarantineOU
    Write-ADMLog "  $Name - Moved to quarantine OU"
    return $true
  }
  catch {
    Write-ADMLog "  Failed to move $Name to quarantine: $($_.Exception.Message)" -Level Warning
    return $false
  }
}

#-----------------------------------------------------------[Banner]---------------------------------------------------------------

function Write-ADMBanner {
  <#
  .SYNOPSIS
    Displays a formatted banner for script start/end.
  #>
  param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptName,

    [switch]$IsEnd
  )

  $Line = '=' * 60
  $Time = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

  Write-Host ''
  Write-Host $Line
  if ($IsEnd) {
    Write-Host " $ScriptName - Completed $Time"
  }
  else {
    Write-Host " $ScriptName - Started $Time"
  }
  Write-Host $Line
  Write-Host ''
}

#-----------------------------------------------------------[Loader]---------------------------------------------------------------

function Test-ADMCommonLoaded {
  <#
  .SYNOPSIS
    Returns $true to confirm that the common functions file has been loaded.
  #>
  return $true
}
