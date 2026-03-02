#requires -version 5.1
#requires -Modules ActiveDirectory
<#
.SYNOPSIS
  Find and manage empty Active Directory groups.

.DESCRIPTION
  Finds and manages empty security and distribution groups within your AD environment.
  Compatible with Windows Server 2022 and Windows Server 2025 (PowerShell 5.1+).

  Supports -WhatIf and -Confirm for deletion operations.

.PARAMETER SearchScope
  Optional. LDAP path to restrict the search. Example: "OU=GROUPS,DC=corp,DC=local"

.PARAMETER ExcludeOU
  Optional. Array of OU distinguished names to exclude from results.

.PARAMETER ReportFilePath
  Optional. Full CSV path for the report. Default: C:\tmp\EmptyGroups.csv.

.PARAMETER DeleteObjects
  Optional switch. Deletes the empty groups found. Supports -WhatIf.

.PARAMETER EnableLogging
  Optional switch. Enables logging to C:\tmp\Logs\.

.PARAMETER EmailTo
  Optional. Email recipient(s) for the report.

.PARAMETER SmtpServer
  Optional. SMTP server for sending emails.

.PARAMETER EmailFrom
  Optional. Sender email address.

.NOTES
  Version:        2.0
  Original Author: Luca Sturlese
  Updated:        2026 - Server 2022/2025 compatibility, full rewrite

.EXAMPLE
  .\Find-ADEmptyGroups.ps1
  Report only. Output to C:\tmp\EmptyGroups.csv.

.EXAMPLE
  .\Find-ADEmptyGroups.ps1 -SearchScope "OU=GROUPS,DC=corp,DC=local" -DeleteObjects -WhatIf
  Simulate deleting empty groups in the GROUPS OU.

.EXAMPLE
  .\Find-ADEmptyGroups.ps1 -ExcludeOU "OU=BuiltIn,DC=corp,DC=local" -EnableLogging
  Report empty groups excluding built-in groups, with logging.
#>

#---------------------------------------------------------[Script Parameters]------------------------------------------------------

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
Param (
  [string]$SearchScope,

  [string[]]$ExcludeOU,

  [ValidatePattern('\.csv$')]
  [string]$ReportFilePath = 'C:\tmp\EmptyGroups.csv',

  [switch]$DeleteObjects,
  [switch]$EnableLogging,

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

$ScriptName = 'Find-ADEmptyGroups'

#-----------------------------------------------------------[Functions]------------------------------------------------------------

Function Get-EmptyGroups {
  [CmdletBinding()]
  Param ()

  if ($SearchScope) {
    Write-ADMLog "Finding empty groups under [$SearchScope]..."
  }
  else {
    Write-ADMLog "Finding empty groups in the entire domain..."
  }
  if ($ExcludeOU) { Write-ADMLog "Excluding OUs: $($ExcludeOU -join ', ')" }

  Try {
    $GetParams = @{
      Filter     = { Members -notlike "*" }
      Properties = @('Members')
    }

    if ($SearchScope) {
      $GetParams['SearchBase'] = $SearchScope
    }

    $Groups = Get-ADGroup @GetParams

    if ($ExcludeOU) {
      $Groups = $Groups | Where-Object {
        -not (Test-ADMExcludedOU -DistinguishedName $_.DistinguishedName -ExcludeOUs $ExcludeOU)
      }
    }

    $Results = @($Groups | Select-Object Name, GroupCategory, DistinguishedName)

    Write-ADMLog "Found $($Results.Count) empty group(s)."
    return $Results
  }
  Catch {
    Write-ADMLog "Failed to query Active Directory: $($_.Exception.Message)" -Level Error
    throw
  }
}

Function Remove-EmptyGroups {
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
  Param ([array]$Data)

  Write-ADMLog "Deleting $($Data.Count) empty group(s)..."
  $SuccessCount = 0; $ErrorCount = 0

  ForEach ($Item in $Data) {
    Try {
      if ($PSCmdlet.ShouldProcess($Item.Name, "Delete AD group")) {
        Remove-ADGroup -Identity $Item.DistinguishedName -Confirm:$false
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

$Results = Get-EmptyGroups

if ($null -eq $Results -or $Results.Count -eq 0) {
  Write-ADMLog "No empty groups found. Nothing to do."
}
else {
  Export-ADMReport -Data $Results -Path $ReportFilePath -ReportName 'Empty groups report'

  if ($DeleteObjects) {
    Remove-EmptyGroups -Data $Results
  }

  Send-ADMReport -EmailTo $EmailTo -EmailFrom $EmailFrom -SmtpServer $SmtpServer `
    -Subject "[$ScriptName] $($Results.Count) empty groups found" `
    -Attachments $ReportFilePath
}

if ($EnableLogging) { Stop-ADMLogging }

Write-ADMBanner -ScriptName $ScriptName -IsEnd
