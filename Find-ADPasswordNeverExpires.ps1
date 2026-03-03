#requires -version 5.1
#requires -Modules ActiveDirectory
<#
.SYNOPSIS
  Find Active Directory users with passwords set to never expire.

.DESCRIPTION
  Identifies enabled user accounts with the PasswordNeverExpires flag set to True.
  This is a security risk and should be audited regularly.
  Compatible with Windows Server 2022 and Windows Server 2025 (PowerShell 5.1+).

  Optionally removes the PasswordNeverExpires flag. Supports -WhatIf.

.PARAMETER SearchBase
  Optional. LDAP path to restrict the search.

.PARAMETER ExcludeOU
  Optional. Array of OU distinguished names to exclude.

.PARAMETER IncludeServiceAccounts
  Optional switch. By default service accounts (matching ServiceAccountIdentifier) are excluded.
  Use this switch to include them.

.PARAMETER ServiceAccountIdentifier
  Optional. Prefix/postfix identifying service accounts. Default: 'svc'.

.PARAMETER ReportFilePath
  Optional. Full CSV/HTML report path. Default: Rapports\Find-ADPasswordNeverExpires.csv (+ .html).

.PARAMETER RemoveFlag
  Optional switch. Removes the PasswordNeverExpires flag. Supports -WhatIf.

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
  .\Find-ADPasswordNeverExpires.ps1
  Report all enabled users with non-expiring passwords (excluding service accounts).

.EXAMPLE
  .\Find-ADPasswordNeverExpires.ps1 -IncludeServiceAccounts
  Include service accounts in the report.

.EXAMPLE
  .\Find-ADPasswordNeverExpires.ps1 -RemoveFlag -WhatIf
  Simulate removing the PasswordNeverExpires flag.
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
Param (
  [string]$SearchBase,
  [string[]]$ExcludeOU,
  [switch]$IncludeServiceAccounts,
  [string]$ServiceAccountIdentifier = 'svc',

  [string]$ReportFilePath = '',

  [switch]$RemoveFlag,
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

$ScriptName = 'Find-ADPasswordNeverExpires'
$ServiceAccountFilter = "*$ServiceAccountIdentifier*"
$Paths = Resolve-ADMReportPath -ReportFilePath $ReportFilePath -ScriptName $ScriptName -CallerPSScriptRoot $PSScriptRoot
$ReportFilePath = $Paths.CsvPath
$HtmlReportPath = $Paths.HtmlPath

#-----------------------------------------------------------[Functions]------------------------------------------------------------

Function Get-PasswordNeverExpiresAccounts {
  [CmdletBinding()]
  Param ()

  Write-ADMLog "Searching for accounts with PasswordNeverExpires..."
  if ($SearchBase) { Write-ADMLog "Search base: $SearchBase" }

  Try {
    $FilterParams = @{
      Filter     = { PasswordNeverExpires -eq $true -and Enabled -eq $true }
      Properties = @('PasswordNeverExpires', 'PasswordLastSet', 'LastLogonDate', 'Description')
    }
    if ($SearchBase) { $FilterParams['SearchBase'] = $SearchBase }

    $Accounts = Get-ADUser @FilterParams

    if (-not $IncludeServiceAccounts) {
      $Accounts = $Accounts | Where-Object { $_.SamAccountName -notlike $ServiceAccountFilter }
    }

    if ($ExcludeOU) {
      $Accounts = $Accounts | Where-Object {
        -not (Test-ADMExcludedOU -DistinguishedName $_.DistinguishedName -ExcludeOUs $ExcludeOU)
      }
    }

    $Results = @($Accounts | Select-Object `
      @{ Name = "Username"; Expression = { $_.SamAccountName } },
      Name,
      PasswordLastSet,
      LastLogonDate,
      Description,
      DistinguishedName
    )

    Write-ADMLog "Found $($Results.Count) account(s) with PasswordNeverExpires."
    return $Results
  }
  Catch {
    Write-ADMLog "Failed to query Active Directory: $($_.Exception.Message)" -Level Error
    throw
  }
}

Function Remove-PasswordNeverExpiresFlag {
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
  Param ([array]$Data)

  Write-ADMLog "Removing PasswordNeverExpires flag from $($Data.Count) account(s)..."
  $SuccessCount = 0; $ErrorCount = 0

  ForEach ($Item in $Data) {
    Try {
      if ($PSCmdlet.ShouldProcess($Item.Username, "Remove PasswordNeverExpires flag")) {
        Set-ADUser -Identity $Item.DistinguishedName -PasswordNeverExpires $false
        Write-ADMLog "  $($Item.Username) - Flag removed"
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

$Results = Get-PasswordNeverExpiresAccounts

if ($null -eq $Results -or $Results.Count -eq 0) {
  Write-ADMLog "No accounts with PasswordNeverExpires found. Nothing to do."
}
else {
  Export-ADMReport -Data $Results -Path $ReportFilePath -ReportName 'PasswordNeverExpires report'

  Export-ADMHTMLReport -Data $Results -Path $HtmlReportPath `
    -Title "Mots de passe non-expirants" `
    -Description "$($Results.Count) compte(s) avec PasswordNeverExpires" `
    -ScriptName $ScriptName `
    -SummaryCards @(
      @{ Label = 'Non-expirants'; Value = $Results.Count; Color = '#dc3545' }
    )

  if ($RemoveFlag) {
    Remove-PasswordNeverExpiresFlag -Data $Results
  }

  Send-ADMReport -EmailTo $EmailTo -EmailFrom $EmailFrom -SmtpServer $SmtpServer `
    -Subject "[$ScriptName] $($Results.Count) accounts with non-expiring passwords" `
    -Attachments $ReportFilePath
}

if ($EnableLogging) { Stop-ADMLogging }

if (-not $NoOpen) { Open-ADMReport -Path $HtmlReportPath }

Write-ADMBanner -ScriptName $ScriptName -IsEnd
