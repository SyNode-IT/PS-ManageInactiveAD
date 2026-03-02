#requires -version 5.1
<#
.SYNOPSIS
  Common functions shared by all AD management scripts.

.DESCRIPTION
  This file is dot-sourced by all AD management scripts in the toolkit.
  It provides logging, reporting, email notification, exclusion filtering,
  and quarantine functions.

  DO NOT execute this file directly. It is loaded automatically by the scripts.

.NOTES
  Version:        2.0
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
    [string]$LogDirectory = 'C:\tmp\Logs',
    [string]$ScriptName = 'ADManagement'
  )

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

#-----------------------------------------------------------[Output]---------------------------------------------------------------

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

  Write-ADMLog "Creating $ReportName at [$Path]..."

  try {
    New-ADMOutputDirectory -Path $Path
    $Data | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
    Write-ADMLog "$ReportName saved successfully ($($Data.Count) entries)."
  }
  catch {
    Write-ADMLog "Failed to create $ReportName : $($_.Exception.Message)" -Level Error
    throw
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
