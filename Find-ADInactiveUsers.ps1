#requires -version 5.1
#requires -Modules ActiveDirectory
<#
.SYNOPSIS
  Find and manage inactive Active Directory users.

.DESCRIPTION
  Identifies inactive users within your AD environment based on configurable criteria.
  Compatible with Windows Server 2022 and Windows Server 2025 (PowerShell 5.1+).

  Management workflow: Report -> Disable -> Move to Quarantine -> Delete
  Supports -WhatIf and -Confirm for all destructive operations.

.PARAMETER SearchScope
  Optional. Type of user accounts to include:
   - All                        : Default. All users including service accounts and never logged on.
   - OnlyInactiveUsers          : Standard users only (excludes service accounts and never logged on).
   - OnlyServiceAccounts        : Service accounts only.
   - OnlyNeverLoggedOn          : Never logged on accounts only.
   - AllExceptServiceAccounts   : All except service accounts.
   - AllExceptNeverLoggedOn     : All except never logged on accounts.

.PARAMETER DaysInactive
  Optional. Days since last logon to classify as inactive. Default: 90.

.PARAMETER ServiceAccountIdentifier
  Optional. Prefix/postfix identifying service accounts. Default: 'svc'.

.PARAMETER SearchBase
  Optional. LDAP path to restrict the search. Example: "OU=Users,DC=corp,DC=local"

.PARAMETER ExcludeOU
  Optional. Array of OU distinguished names to exclude from results.

.PARAMETER QuarantineOU
  Optional. OU to move disabled accounts to. Example: "OU=Disabled,DC=corp,DC=local"

.PARAMETER ReportFilePath
  Optional. Full CSV path for the report. Default: C:\tmp\InactiveUsers.csv.

.PARAMETER DisableUsers
  Optional switch. Disables inactive users. Supports -WhatIf.

.PARAMETER DeleteUsers
  Optional switch. Deletes inactive users. Supports -WhatIf.

.PARAMETER EnableLogging
  Optional switch. Enables logging to C:\tmp\Logs\.

.PARAMETER EmailTo
  Optional. Email recipient(s) for the report.

.PARAMETER SmtpServer
  Optional. SMTP server for sending emails.

.PARAMETER EmailFrom
  Optional. Sender email address. Defaults to ADManagement@<domain>.

.NOTES
  Version:        2.0
  Original Author: Luca Sturlese
  Updated:        2026 - Server 2022/2025 compatibility, full rewrite

.EXAMPLE
  .\Find-ADInactiveUsers.ps1
  Report only. Output to C:\tmp\InactiveUsers.csv.

.EXAMPLE
  .\Find-ADInactiveUsers.ps1 -SearchBase "OU=Paris,DC=corp,DC=local" -ExcludeOU "OU=VIP,OU=Paris,DC=corp,DC=local"
  Report inactive users in the Paris OU, excluding the VIP sub-OU.

.EXAMPLE
  .\Find-ADInactiveUsers.ps1 -DisableUsers -QuarantineOU "OU=Disabled,DC=corp,DC=local"
  Disable inactive users and move them to a quarantine OU.

.EXAMPLE
  .\Find-ADInactiveUsers.ps1 -DeleteUsers -WhatIf
  Simulate deletion without modifying anything.

.EXAMPLE
  .\Find-ADInactiveUsers.ps1 -EnableLogging -EmailTo "admin@corp.local" -SmtpServer "smtp.corp.local"
  Report with logging and email notification.
#>

#---------------------------------------------------------[Script Parameters]------------------------------------------------------

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
Param (
  [ValidateSet('All', 'OnlyInactiveUsers', 'OnlyServiceAccounts', 'OnlyNeverLoggedOn', 'AllExceptServiceAccounts', 'AllExceptNeverLoggedOn')]
  [string]$SearchScope = 'All',

  [ValidateRange(1, 3650)]
  [int]$DaysInactive = 90,

  [string]$ServiceAccountIdentifier = 'svc',

  [string]$SearchBase,

  [string[]]$ExcludeOU,

  [string]$QuarantineOU,

  [string]$ReportFilePath = '',

  [switch]$DisableUsers,
  [switch]$DeleteUsers,
  [switch]$EnableLogging,
  [switch]$NoOpen,

  [string[]]$EmailTo,
  [string]$SmtpServer,
  [string]$EmailFrom
)

#---------------------------------------------------------[Initialisations]--------------------------------------------------------

$ErrorActionPreference = 'Stop'

# Load common functions
$CommonPath = Join-Path $PSScriptRoot 'ADManagement-Common.ps1'
if (-not (Test-Path $CommonPath)) {
  throw "Required file not found: $CommonPath. Ensure ADManagement-Common.ps1 is in the same directory."
}
. $CommonPath

Import-Module ActiveDirectory

#----------------------------------------------------------[Declarations]----------------------------------------------------------

$InactiveDate = (Get-Date).AddDays(-$DaysInactive)
$ServiceAccountFilter = "*$ServiceAccountIdentifier*"
$ScriptName = 'Find-ADInactiveUsers'
$Paths = Resolve-ADMReportPath -ReportFilePath $ReportFilePath -ScriptName $ScriptName -CallerPSScriptRoot $PSScriptRoot
$ReportFilePath = $Paths.CsvPath
$HtmlReportPath = $Paths.HtmlPath

#-----------------------------------------------------------[Functions]------------------------------------------------------------

Function Get-InactiveAccounts {
  [CmdletBinding()]
  Param ()

  Write-ADMLog "Search scope: $SearchScope | Threshold: $DaysInactive days (before $($InactiveDate.ToString('yyyy-MM-dd')))"
  if ($SearchBase) { Write-ADMLog "Search base: $SearchBase" }
  if ($ExcludeOU) { Write-ADMLog "Excluding OUs: $($ExcludeOU -join ', ')" }

  Try {
    $FilterParams = @{ Properties = 'LastLogonDate' }
    if ($SearchBase) { $FilterParams['SearchBase'] = $SearchBase }

    $Accounts = switch ($SearchScope) {
      'All' {
        Get-ADUser @FilterParams -Filter {
          (LastLogonDate -lt $InactiveDate -or LastLogonDate -notlike "*") -and (Enabled -eq $true)
        }
      }
      'OnlyInactiveUsers' {
        Get-ADUser @FilterParams -Filter {
          LastLogonDate -lt $InactiveDate -and Enabled -eq $true -and SamAccountName -notlike $ServiceAccountFilter
        }
      }
      'OnlyServiceAccounts' {
        Get-ADUser @FilterParams -Filter {
          LastLogonDate -lt $InactiveDate -and Enabled -eq $true -and SamAccountName -like $ServiceAccountFilter
        }
      }
      'OnlyNeverLoggedOn' {
        Get-ADUser @FilterParams -Filter {
          LastLogonDate -notlike "*" -and Enabled -eq $true
        }
      }
      'AllExceptServiceAccounts' {
        Get-ADUser @FilterParams -Filter {
          ((LastLogonDate -lt $InactiveDate) -and (Enabled -eq $true) -and (SamAccountName -notlike $ServiceAccountFilter)) -or
          ((LastLogonDate -notlike "*") -and (Enabled -eq $true) -and (SamAccountName -notlike $ServiceAccountFilter))
        }
      }
      'AllExceptNeverLoggedOn' {
        Get-ADUser @FilterParams -Filter {
          LastLogonDate -lt $InactiveDate -and Enabled -eq $true
        }
      }
    }

    # Apply OU exclusions
    if ($ExcludeOU) {
      $Accounts = $Accounts | Where-Object {
        -not (Test-ADMExcludedOU -DistinguishedName $_.DistinguishedName -ExcludeOUs $ExcludeOU)
      }
    }

    $Results = @($Accounts | Select-Object @{ Name = "Username"; Expression = { $_.SamAccountName } }, Name, LastLogonDate, DistinguishedName)

    Write-ADMLog "Found $($Results.Count) inactive user(s)."
    return $Results
  }
  Catch {
    Write-ADMLog "Failed to query Active Directory: $($_.Exception.Message)" -Level Error
    throw
  }
}

Function Disable-InactiveAccounts {
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
  Param ([array]$Data)

  Write-ADMLog "Disabling $($Data.Count) inactive user(s)..."
  $SuccessCount = 0; $ErrorCount = 0

  ForEach ($Item in $Data) {
    Try {
      if ($PSCmdlet.ShouldProcess($Item.Username, "Disable AD user account")) {
        Disable-ADAccount -Identity $Item.DistinguishedName
        Write-ADMLog "  $($Item.Username) - Disabled"

        if ($QuarantineOU) {
          Move-ADMToQuarantine -Identity $Item.DistinguishedName -Name $Item.Username -QuarantineOU $QuarantineOU -ObjectType 'User'
        }

        $SuccessCount++
      }
    }
    Catch {
      Write-ADMLog "  Failed to disable $($Item.Username): $($_.Exception.Message)" -Level Warning
      $ErrorCount++
    }
  }

  Write-ADMLog "Disable complete: $SuccessCount succeeded, $ErrorCount failed."
}

Function Remove-InactiveAccounts {
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
  Param ([array]$Data)

  Write-ADMLog "Deleting $($Data.Count) inactive user(s)..."
  $SuccessCount = 0; $ErrorCount = 0

  ForEach ($Item in $Data) {
    Try {
      if ($PSCmdlet.ShouldProcess($Item.Username, "Delete AD user account")) {
        Remove-ADUser -Identity $Item.DistinguishedName -Confirm:$false
        Write-ADMLog "  $($Item.Username) - Deleted"
        $SuccessCount++
      }
    }
    Catch {
      Write-ADMLog "  Failed to delete $($Item.Username): $($_.Exception.Message)" -Level Warning
      $ErrorCount++
    }
  }

  Write-ADMLog "Delete complete: $SuccessCount succeeded, $ErrorCount failed."
}

#-----------------------------------------------------------[Execution]------------------------------------------------------------

Write-ADMBanner -ScriptName $ScriptName

if ($EnableLogging) {
  Start-ADMLogging -ScriptName $ScriptName
}

$Results = Get-InactiveAccounts

if ($null -eq $Results -or $Results.Count -eq 0) {
  Write-ADMLog "No inactive users found. Nothing to do."
}
else {
  Export-ADMReport -Data $Results -Path $ReportFilePath -ReportName 'Inactive users report'

  Export-ADMHTMLReport -Data $Results -Path $HtmlReportPath `
    -Title "Utilisateurs inactifs" `
    -Description "$($Results.Count) utilisateur(s) inactif(s) depuis plus de $DaysInactive jours" `
    -ScriptName $ScriptName `
    -SummaryCards @(
      @{ Label = 'Inactifs'; Value = $Results.Count; Color = '#dc3545' }
      @{ Label = 'Seuil (jours)'; Value = $DaysInactive; Color = '#0078d4' }
    )

  if ($DisableUsers) {
    Disable-InactiveAccounts -Data $Results
  }

  if ($DeleteUsers) {
    Remove-InactiveAccounts -Data $Results
  }

  Send-ADMReport -EmailTo $EmailTo -EmailFrom $EmailFrom -SmtpServer $SmtpServer `
    -Subject "[$ScriptName] $($Results.Count) inactive users found" `
    -Attachments $ReportFilePath
}

if ($EnableLogging) { Stop-ADMLogging }

if (-not $NoOpen) { Open-ADMReport -Path $HtmlReportPath }

Write-ADMBanner -ScriptName $ScriptName -IsEnd
