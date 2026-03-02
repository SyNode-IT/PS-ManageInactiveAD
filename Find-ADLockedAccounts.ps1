#requires -version 5.1
#requires -Modules ActiveDirectory
<#
.SYNOPSIS
  Find and optionally unlock locked Active Directory user accounts.

.DESCRIPTION
  Identifies currently locked-out user accounts in your AD environment.
  Compatible with Windows Server 2022 and Windows Server 2025 (PowerShell 5.1+).

  Supports -WhatIf and -Confirm for unlock operations.

.PARAMETER SearchBase
  Optional. LDAP path to restrict the search.

.PARAMETER ReportFilePath
  Optional. Full CSV path for the report. Default: C:\tmp\LockedAccounts.csv.

.PARAMETER UnlockAccounts
  Optional switch. Unlocks the locked accounts found. Supports -WhatIf.

.PARAMETER EnableLogging
  Optional switch. Enables logging to C:\tmp\Logs\.

.PARAMETER EmailTo
  Optional. Email recipient(s) for the report.

.PARAMETER SmtpServer
  Optional. SMTP server for sending emails.

.PARAMETER EmailFrom
  Optional. Sender email address.

.NOTES
  Version:        1.0
  Creation Date:  2026
  Compatible:     Windows Server 2022, Windows Server 2025

.EXAMPLE
  .\Find-ADLockedAccounts.ps1
  Report all currently locked accounts.

.EXAMPLE
  .\Find-ADLockedAccounts.ps1 -UnlockAccounts
  Find and unlock all locked accounts.

.EXAMPLE
  .\Find-ADLockedAccounts.ps1 -UnlockAccounts -WhatIf
  Simulate unlocking without modifying anything.
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
Param (
  [string]$SearchBase,

  [ValidatePattern('\.csv$')]
  [string]$ReportFilePath = 'C:\tmp\LockedAccounts.csv',

  [switch]$UnlockAccounts,
  [switch]$EnableLogging,

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

$ScriptName = 'Find-ADLockedAccounts'

#-----------------------------------------------------------[Functions]------------------------------------------------------------

Function Get-LockedAccounts {
  [CmdletBinding()]
  Param ()

  Write-ADMLog "Searching for locked-out accounts..."
  if ($SearchBase) { Write-ADMLog "Search base: $SearchBase" }

  Try {
    $SearchParams = @{}
    if ($SearchBase) { $SearchParams['SearchBase'] = $SearchBase }

    $Locked = Search-ADAccount -LockedOut -UsersOnly @SearchParams |
      Get-ADUser -Properties LastLogonDate, LockedOut, LockoutTime, LastBadPasswordAttempt |
      Select-Object @{ Name = "Username"; Expression = { $_.SamAccountName } },
                    Name,
                    LastLogonDate,
                    @{ Name = "LockoutTime"; Expression = { [DateTime]::FromFileTime($_.LockoutTime) } },
                    LastBadPasswordAttempt,
                    DistinguishedName

    $Results = @($Locked)
    Write-ADMLog "Found $($Results.Count) locked account(s)."
    return $Results
  }
  Catch {
    Write-ADMLog "Failed to query Active Directory: $($_.Exception.Message)" -Level Error
    throw
  }
}

Function Unlock-LockedAccounts {
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
  Param ([array]$Data)

  Write-ADMLog "Unlocking $($Data.Count) account(s)..."
  $SuccessCount = 0; $ErrorCount = 0

  ForEach ($Item in $Data) {
    Try {
      if ($PSCmdlet.ShouldProcess($Item.Username, "Unlock AD user account")) {
        Unlock-ADAccount -Identity $Item.DistinguishedName
        Write-ADMLog "  $($Item.Username) - Unlocked"
        $SuccessCount++
      }
    }
    Catch {
      Write-ADMLog "  Failed to unlock $($Item.Username): $($_.Exception.Message)" -Level Warning
      $ErrorCount++
    }
  }

  Write-ADMLog "Unlock complete: $SuccessCount succeeded, $ErrorCount failed."
}

#-----------------------------------------------------------[Execution]------------------------------------------------------------

Write-ADMBanner -ScriptName $ScriptName

if ($EnableLogging) { Start-ADMLogging -ScriptName $ScriptName }

$Results = Get-LockedAccounts

if ($null -eq $Results -or $Results.Count -eq 0) {
  Write-ADMLog "No locked accounts found. Nothing to do."
}
else {
  Export-ADMReport -Data $Results -Path $ReportFilePath -ReportName 'Locked accounts report'

  if ($UnlockAccounts) {
    Unlock-LockedAccounts -Data $Results
  }

  Send-ADMReport -EmailTo $EmailTo -EmailFrom $EmailFrom -SmtpServer $SmtpServer `
    -Subject "[$ScriptName] $($Results.Count) locked accounts found" `
    -Attachments $ReportFilePath
}

if ($EnableLogging) { Stop-ADMLogging }

Write-ADMBanner -ScriptName $ScriptName -IsEnd
