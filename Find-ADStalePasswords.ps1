#requires -version 5.1
#requires -Modules ActiveDirectory
<#
.SYNOPSIS
  Find Active Directory users with passwords older than a specified threshold.

.DESCRIPTION
  Identifies enabled user accounts whose password has not been changed for a given number of days.
  Compatible with Windows Server 2022 and Windows Server 2025 (PowerShell 5.1+).

  Optionally forces a password change at next logon. Supports -WhatIf.

.PARAMETER DaysOld
  Optional. Number of days since the password was last set. Default: 180.

.PARAMETER SearchBase
  Optional. LDAP path to restrict the search.

.PARAMETER ExcludeOU
  Optional. Array of OU distinguished names to exclude.

.PARAMETER ReportFilePath
  Optional. Full CSV/HTML report path. Default: Rapports\Find-ADStalePasswords.csv (+ .html).

.PARAMETER ForceChangeAtLogon
  Optional switch. Sets 'User must change password at next logon'. Supports -WhatIf.

.PARAMETER EnableLogging
  Optional switch. Enables logging.

.PARAMETER EmailTo
  Optional. Email recipient(s).

.PARAMETER SmtpServer
  Optional. SMTP server.

.PARAMETER EmailFrom
  Optional. Sender email address.

.NOTES
  Version:        2.1
  Creation Date:  2026
  Compatible:     Windows Server 2022, Windows Server 2025

.EXAMPLE
  .\Find-ADStalePasswords.ps1
  Report accounts with passwords older than 180 days.

.EXAMPLE
  .\Find-ADStalePasswords.ps1 -DaysOld 365
  Report accounts with passwords older than 1 year.

.EXAMPLE
  .\Find-ADStalePasswords.ps1 -DaysOld 90 -ForceChangeAtLogon -WhatIf
  Simulate forcing password change for accounts with passwords older than 90 days.
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
Param (
  [ValidateRange(1, 3650)]
  [int]$DaysOld = 180,

  [string]$SearchBase,
  [string[]]$ExcludeOU,

  [string]$ReportFilePath = '',

  [switch]$ForceChangeAtLogon,
  [switch]$EnableLogging,
  [switch]$NoOpen,

  [string[]]$EmailTo,
  [string]$SmtpServer,
  [string]$EmailFrom
)

$ErrorActionPreference = 'Stop'

$CommonPath = Join-Path $PSScriptRoot 'ADManagement-Common.ps1'
if (-not (Test-Path $CommonPath)) {
  throw "Required file not found: $CommonPath. Ensure ADManagement-Common.ps1 is in the same directory."
}
. $CommonPath

Import-Module ActiveDirectory

$ScriptName = 'Find-ADStalePasswords'
$ThresholdDate = (Get-Date).AddDays(-$DaysOld)
$Paths = Resolve-ADMReportPath -ReportFilePath $ReportFilePath -ScriptName $ScriptName -CallerPSScriptRoot $PSScriptRoot
$ReportFilePath = $Paths.CsvPath
$HtmlReportPath = $Paths.HtmlPath

#-----------------------------------------------------------[Functions]------------------------------------------------------------

Function Get-StalePasswordAccounts {
  [CmdletBinding()]
  Param ()

  Write-ADMLog "Searching for accounts with passwords older than $DaysOld days (before $($ThresholdDate.ToString('yyyy-MM-dd')))..."
  if ($SearchBase) { Write-ADMLog "Search base: $SearchBase" }

  Try {
    $FilterParams = @{
      Filter     = { PasswordLastSet -lt $ThresholdDate -and Enabled -eq $true -and PasswordNeverExpires -eq $false }
      Properties = @('PasswordLastSet', 'LastLogonDate', 'Description')
    }
    if ($SearchBase) { $FilterParams['SearchBase'] = $SearchBase }

    $Accounts = Get-ADUser @FilterParams

    if ($ExcludeOU) {
      $Accounts = $Accounts | Where-Object {
        -not (Test-ADMExcludedOU -DistinguishedName $_.DistinguishedName -ExcludeOUs $ExcludeOU)
      }
    }

    $Results = @($Accounts | Select-Object `
      @{ Name = "Username"; Expression = { $_.SamAccountName } },
      Name,
      PasswordLastSet,
      @{ Name = "PasswordAgeDays"; Expression = { [math]::Round(((Get-Date) - $_.PasswordLastSet).TotalDays) } },
      LastLogonDate,
      Description,
      DistinguishedName
    )

    Write-ADMLog "Found $($Results.Count) account(s) with stale passwords."
    return $Results
  }
  Catch {
    Write-ADMLog "Failed to query Active Directory: $($_.Exception.Message)" -Level Error
    throw
  }
}

Function Set-ForcePasswordChange {
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
  Param ([array]$Data)

  Write-ADMLog "Forcing password change at next logon for $($Data.Count) account(s)..."
  $SuccessCount = 0; $ErrorCount = 0

  ForEach ($Item in $Data) {
    Try {
      if ($PSCmdlet.ShouldProcess($Item.Username, "Force password change at next logon")) {
        Set-ADUser -Identity $Item.DistinguishedName -ChangePasswordAtLogon $true
        Write-ADMLog "  $($Item.Username) - Password change forced (age: $($Item.PasswordAgeDays) days)"
        $SuccessCount++
      }
    }
    Catch {
      Write-ADMLog "  Failed on $($Item.Username): $($_.Exception.Message)" -Level Warning
      $ErrorCount++
    }
  }

  Write-ADMLog "Complete: $SuccessCount succeeded, $ErrorCount failed."
}

#-----------------------------------------------------------[Execution]------------------------------------------------------------

Write-ADMBanner -ScriptName $ScriptName

if ($EnableLogging) { Start-ADMLogging -ScriptName $ScriptName }

$Results = Get-StalePasswordAccounts

if ($null -eq $Results -or $Results.Count -eq 0) {
  Write-ADMLog "No accounts with stale passwords found. Nothing to do."
}
else {
  Export-ADMReport -Data $Results -Path $ReportFilePath -ReportName 'Stale passwords report'

  Export-ADMHTMLReport -Data $Results -Path $HtmlReportPath `
    -Title "Mots de passe anciens" `
    -Description "$($Results.Count) compte(s) avec mot de passe de plus de $DaysOld jours" `
    -ScriptName $ScriptName `
    -SummaryCards @(
      @{ Label = 'Mots de passe anciens'; Value = $Results.Count; Color = '#e67e22' }
      @{ Label = 'Seuil (jours)'; Value = $DaysOld; Color = '#0078d4' }
    )

  if ($ForceChangeAtLogon) {
    Set-ForcePasswordChange -Data $Results
  }

  Send-ADMReport -EmailTo $EmailTo -EmailFrom $EmailFrom -SmtpServer $SmtpServer `
    -Subject "[$ScriptName] $($Results.Count) accounts with stale passwords" `
    -Attachments $ReportFilePath
}

if ($EnableLogging) { Stop-ADMLogging }

if (-not $NoOpen) { Open-ADMReport -Path $HtmlReportPath }

Write-ADMBanner -ScriptName $ScriptName -IsEnd
