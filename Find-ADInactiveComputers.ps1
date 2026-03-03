#requires -version 5.1
#requires -Modules ActiveDirectory
<#
.SYNOPSIS
  Find and manage inactive Active Directory computer objects.

.DESCRIPTION
  Identifies inactive computer objects within your AD environment based on configurable criteria.
  Compatible with Windows Server 2022 and Windows Server 2025 (PowerShell 5.1+).

  Management workflow: Report -> Disable -> Move to Quarantine -> Delete
  Supports -WhatIf and -Confirm for all destructive operations.

.PARAMETER SearchScope
  Optional. Type of computer objects to include:
   - All                   : Default. All inactive and never logged on computers.
   - OnlyInactiveComputers : Computers that have logged on before but are now inactive.
   - OnlyNeverLoggedOn     : Computers that have never logged on.

.PARAMETER DaysInactive
  Optional. Days since last logon to classify as inactive. Default: 90.

.PARAMETER SearchBase
  Optional. LDAP path to restrict the search. Example: "OU=Servers,DC=corp,DC=local"

.PARAMETER ExcludeOU
  Optional. Array of OU distinguished names to exclude from results.

.PARAMETER QuarantineOU
  Optional. OU to move disabled computers to. Example: "OU=Disabled,DC=corp,DC=local"

.PARAMETER ReportFilePath
  Optional. Full CSV/HTML report path. Default: Rapports\Find-ADInactiveComputers.csv (+ .html).

.PARAMETER DisableObjects
  Optional switch. Disables inactive computers. Supports -WhatIf.

.PARAMETER DeleteObjects
  Optional switch. Deletes inactive computers. Supports -WhatIf.

.PARAMETER EnableLogging
  Optional switch. Enables logging to Rapports\Logs\.

.PARAMETER EmailTo
  Optional. Email recipient(s) for the report.

.PARAMETER SmtpServer
  Optional. SMTP server for sending emails.

.PARAMETER EmailFrom
  Optional. Sender email address.

.NOTES
  Version:        2.1
  Original Author: Luca Sturlese
  Updated:        2026 - Server 2022/2025 compatibility, full rewrite

.EXAMPLE
  .\Find-ADInactiveComputers.ps1
  Report only. Output to Rapports\Find-ADInactiveComputers.csv.

.EXAMPLE
  .\Find-ADInactiveComputers.ps1 -SearchBase "OU=Workstations,DC=corp,DC=local" -DaysInactive 60
  Report inactive computers in the Workstations OU (60+ days).

.EXAMPLE
  .\Find-ADInactiveComputers.ps1 -DisableObjects -QuarantineOU "OU=Disabled,DC=corp,DC=local"
  Disable inactive computers and move them to quarantine.

.EXAMPLE
  .\Find-ADInactiveComputers.ps1 -DeleteObjects -WhatIf
  Simulate deletion without modifying anything.
#>

#---------------------------------------------------------[Script Parameters]------------------------------------------------------

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
Param (
  [ValidateSet('All', 'OnlyInactiveComputers', 'OnlyNeverLoggedOn')]
  [string]$SearchScope = 'All',

  [ValidateRange(1, 3650)]
  [int]$DaysInactive = 90,

  [string]$SearchBase,

  [string[]]$ExcludeOU,

  [string]$QuarantineOU,

  [string]$ReportFilePath = '',

  [switch]$DisableObjects,
  [switch]$DeleteObjects,
  [switch]$EnableLogging,
  [switch]$NoOpen,

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

$InactiveDate = (Get-Date).AddDays(-$DaysInactive)
$ScriptName = 'Find-ADInactiveComputers'
$Paths = Resolve-ADMReportPath -ReportFilePath $ReportFilePath -ScriptName $ScriptName -CallerPSScriptRoot $PSScriptRoot
$ReportFilePath = $Paths.CsvPath
$HtmlReportPath = $Paths.HtmlPath

#-----------------------------------------------------------[Functions]------------------------------------------------------------

Function Get-InactiveComputers {
  [CmdletBinding()]
  Param ()

  Write-ADMLog "Search scope: $SearchScope | Threshold: $DaysInactive days (before $($InactiveDate.ToString('yyyy-MM-dd')))"
  if ($SearchBase) { Write-ADMLog "Search base: $SearchBase" }
  if ($ExcludeOU) { Write-ADMLog "Excluding OUs: $($ExcludeOU -join ', ')" }

  Try {
    $FilterParams = @{ Properties = 'LastLogonDate' }
    if ($SearchBase) { $FilterParams['SearchBase'] = $SearchBase }

    $Computers = switch ($SearchScope) {
      'All' {
        Get-ADComputer @FilterParams -Filter {
          (LastLogonDate -lt $InactiveDate -or LastLogonDate -notlike "*") -and (Enabled -eq $true)
        }
      }
      'OnlyInactiveComputers' {
        Get-ADComputer @FilterParams -Filter {
          LastLogonDate -lt $InactiveDate -and Enabled -eq $true
        }
      }
      'OnlyNeverLoggedOn' {
        Get-ADComputer @FilterParams -Filter {
          LastLogonDate -notlike "*" -and Enabled -eq $true
        }
      }
    }

    if ($ExcludeOU) {
      $Computers = $Computers | Where-Object {
        -not (Test-ADMExcludedOU -DistinguishedName $_.DistinguishedName -ExcludeOUs $ExcludeOU)
      }
    }

    $Results = @($Computers | Select-Object Name, LastLogonDate, DistinguishedName)

    Write-ADMLog "Found $($Results.Count) inactive computer(s)."
    return $Results
  }
  Catch {
    Write-ADMLog "Failed to query Active Directory: $($_.Exception.Message)" -Level Error
    throw
  }
}

Function Disable-InactiveComputers {
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
  Param ([array]$Data)

  Write-ADMLog "Disabling $($Data.Count) inactive computer(s)..."
  $SuccessCount = 0; $ErrorCount = 0

  ForEach ($Item in $Data) {
    Try {
      if ($PSCmdlet.ShouldProcess($Item.Name, "Disable AD computer object")) {
        Set-ADComputer -Identity $Item.DistinguishedName -Enabled $false
        Write-ADMLog "  $($Item.Name) - Disabled"

        if ($QuarantineOU) {
          Move-ADMToQuarantine -Identity $Item.DistinguishedName -Name $Item.Name -QuarantineOU $QuarantineOU -ObjectType 'Computer'
        }

        $SuccessCount++
      }
    }
    Catch {
      Write-ADMLog "  Failed to disable $($Item.Name): $($_.Exception.Message)" -Level Warning
      $ErrorCount++
    }
  }

  Write-ADMLog "Disable complete: $SuccessCount succeeded, $ErrorCount failed."
}

Function Remove-InactiveComputers {
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
  Param ([array]$Data)

  Write-ADMLog "Deleting $($Data.Count) inactive computer(s)..."
  $SuccessCount = 0; $ErrorCount = 0

  ForEach ($Item in $Data) {
    Try {
      if ($PSCmdlet.ShouldProcess($Item.Name, "Delete AD computer object")) {
        Remove-ADComputer -Identity $Item.DistinguishedName -Confirm:$false
        Write-ADMLog "  $($Item.Name) - Deleted"
        $SuccessCount++
      }
    }
    Catch {
      Write-ADMLog "  Failed to delete $($Item.Name): $($_.Exception.Message)" -Level Warning
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

$Results = Get-InactiveComputers

if ($null -eq $Results -or $Results.Count -eq 0) {
  Write-ADMLog "No inactive computers found. Nothing to do."
}
else {
  Export-ADMReport -Data $Results -Path $ReportFilePath -ReportName 'Inactive computers report'

  Export-ADMHTMLReport -Data $Results -Path $HtmlReportPath `
    -Title "Ordinateurs inactifs" `
    -Description "$($Results.Count) ordinateur(s) inactif(s) depuis plus de $DaysInactive jours" `
    -ScriptName $ScriptName `
    -SummaryCards @(
      @{ Label = 'Inactifs'; Value = $Results.Count; Color = '#dc3545' }
      @{ Label = 'Seuil (jours)'; Value = $DaysInactive; Color = '#0078d4' }
    )

  if ($DisableObjects) {
    Disable-InactiveComputers -Data $Results
  }

  if ($DeleteObjects) {
    Remove-InactiveComputers -Data $Results
  }

  Send-ADMReport -EmailTo $EmailTo -EmailFrom $EmailFrom -SmtpServer $SmtpServer `
    -Subject "[$ScriptName] $($Results.Count) inactive computers found" `
    -Attachments $ReportFilePath
}

if ($EnableLogging) { Stop-ADMLogging }

if (-not $NoOpen) { Open-ADMReport -Path $HtmlReportPath }

Write-ADMBanner -ScriptName $ScriptName -IsEnd
