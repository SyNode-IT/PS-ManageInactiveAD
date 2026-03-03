#requires -version 5.1
#requires -Modules ActiveDirectory
<#
.SYNOPSIS
  Find and manage empty Active Directory OUs.

.DESCRIPTION
  Finds and manages empty organizational units within your AD environment.
  Compatible with Windows Server 2022 and Windows Server 2025 (PowerShell 5.1+).

  Supports -WhatIf and -Confirm for deletion operations.
  Note: OUs with 'Protect from Accidental Deletion' will fail to delete.

.PARAMETER SearchScope
  Optional. LDAP path to restrict the search. Example: "OU=MGT,DC=corp,DC=local"

.PARAMETER ExcludeOU
  Optional. Array of OU distinguished names to exclude from results.

.PARAMETER ReportFilePath
  Optional. Full CSV/HTML report path. Default: Rapports\Find-ADEmptyOU.csv (+ .html).

.PARAMETER DeleteObjects
  Optional switch. Deletes the empty OUs found. Supports -WhatIf.

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
  .\Find-ADEmptyOU.ps1
  Report only. Output to Rapports\Find-ADEmptyOU.csv.

.EXAMPLE
  .\Find-ADEmptyOU.ps1 -SearchScope "OU=MGT,DC=corp,DC=local" -DeleteObjects
  Delete all empty OUs found within the MGT OU.

.EXAMPLE
  .\Find-ADEmptyOU.ps1 -DeleteObjects -WhatIf
  Simulate deletion without modifying anything.
#>

#---------------------------------------------------------[Script Parameters]------------------------------------------------------

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
Param (
  [string]$SearchScope,

  [string[]]$ExcludeOU,

  [string]$ReportFilePath = '',

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

$ScriptName = 'Find-ADEmptyOU'
$Paths = Resolve-ADMReportPath -ReportFilePath $ReportFilePath -ScriptName $ScriptName -CallerPSScriptRoot $PSScriptRoot
$ReportFilePath = $Paths.CsvPath
$HtmlReportPath = $Paths.HtmlPath

#-----------------------------------------------------------[Functions]------------------------------------------------------------

Function Get-EmptyOUs {
  [CmdletBinding()]
  Param ()

  if ($SearchScope) {
    Write-ADMLog "Finding empty OUs under [$SearchScope]..."
  }
  else {
    Write-ADMLog "Finding empty OUs in the entire domain..."
  }
  if ($ExcludeOU) { Write-ADMLog "Excluding OUs: $($ExcludeOU -join ', ')" }

  Try {
    $GetParams = @{ Filter = '*' }

    if ($SearchScope) {
      $GetParams['SearchBase'] = $SearchScope
    }

    $AllOUs = Get-ADOrganizationalUnit @GetParams

    $EmptyOUs = foreach ($OU in $AllOUs) {
      $ChildObjects = Get-ADObject -Filter * -SearchBase $OU.DistinguishedName -SearchScope OneLevel -ErrorAction SilentlyContinue
      if (-not $ChildObjects) {
        $OU
      }
    }

    if ($ExcludeOU) {
      $EmptyOUs = $EmptyOUs | Where-Object {
        -not (Test-ADMExcludedOU -DistinguishedName $_.DistinguishedName -ExcludeOUs $ExcludeOU)
      }
    }

    $Results = @($EmptyOUs | Select-Object Name, DistinguishedName)

    Write-ADMLog "Found $($Results.Count) empty OU(s)."
    return $Results
  }
  Catch {
    Write-ADMLog "Failed to query Active Directory: $($_.Exception.Message)" -Level Error
    throw
  }
}

Function Remove-EmptyOUs {
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
  Param ([array]$Data)

  Write-ADMLog "Deleting $($Data.Count) empty OU(s)..."
  $SuccessCount = 0; $ErrorCount = 0

  ForEach ($Item in $Data) {
    Try {
      if ($PSCmdlet.ShouldProcess($Item.Name, "Delete AD organizational unit")) {
        Remove-ADOrganizationalUnit -Identity $Item.DistinguishedName -Confirm:$false
        Write-ADMLog "  $($Item.Name) - Deleted"
        $SuccessCount++
      }
    }
    Catch {
      Write-ADMLog "  Failed to delete $($Item.Name): $($_.Exception.Message)" -Level Warning
      Write-ADMLog "  (Tip: Check if 'Protect from Accidental Deletion' is enabled)" -Level Warning
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

$Results = Get-EmptyOUs

if ($null -eq $Results -or $Results.Count -eq 0) {
  Write-ADMLog "No empty OUs found. Nothing to do."
}
else {
  Export-ADMReport -Data $Results -Path $ReportFilePath -ReportName 'Empty OUs report'

  Export-ADMHTMLReport -Data $Results -Path $HtmlReportPath `
    -Title "OUs vides" `
    -Description "$($Results.Count) OU(s) sans aucun objet" `
    -ScriptName $ScriptName `
    -SummaryCards @(
      @{ Label = 'OUs vides'; Value = $Results.Count; Color = '#e67e22' }
    )

  if ($DeleteObjects) {
    Remove-EmptyOUs -Data $Results
  }

  Send-ADMReport -EmailTo $EmailTo -EmailFrom $EmailFrom -SmtpServer $SmtpServer `
    -Subject "[$ScriptName] $($Results.Count) empty OUs found" `
    -Attachments $ReportFilePath
}

if ($EnableLogging) { Stop-ADMLogging }

if (-not $NoOpen) { Open-ADMReport -Path $HtmlReportPath }

Write-ADMBanner -ScriptName $ScriptName -IsEnd
