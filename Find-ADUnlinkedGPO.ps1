#requires -version 5.1
#requires -Modules GroupPolicy
<#
.SYNOPSIS
  Find unlinked Group Policy Objects in Active Directory.

.DESCRIPTION
  Identifies GPOs that are not linked to any OU, site, or domain.
  These orphan GPOs consume space and create confusion.
  Compatible with Windows Server 2022 and Windows Server 2025 (PowerShell 5.1+).

  Requires the GroupPolicy module (installed with GPMC / RSAT).
  Optionally deletes unlinked GPOs. Supports -WhatIf.

.PARAMETER ExcludeGPO
  Optional. Array of GPO display names to exclude from the results (e.g. default GPOs).

.PARAMETER ReportFilePath
  Optional. Full CSV path for the report. Default: C:\tmp\UnlinkedGPO.csv.

.PARAMETER DeleteObjects
  Optional switch. Deletes unlinked GPOs. Supports -WhatIf.

.PARAMETER EnableLogging
  Optional switch. Enables logging.

.PARAMETER EmailTo
  Optional. Email recipient(s).

.PARAMETER SmtpServer
  Optional. SMTP server.

.PARAMETER EmailFrom
  Optional. Sender email address.

.NOTES
  Version:        1.0
  Creation Date:  2026
  Compatible:     Windows Server 2022, Windows Server 2025
  Requires:       GroupPolicy module (GPMC / RSAT)

.EXAMPLE
  .\Find-ADUnlinkedGPO.ps1
  Report all unlinked GPOs.

.EXAMPLE
  .\Find-ADUnlinkedGPO.ps1 -ExcludeGPO "Default Domain Policy","Default Domain Controllers Policy"
  Report unlinked GPOs excluding default policies.

.EXAMPLE
  .\Find-ADUnlinkedGPO.ps1 -DeleteObjects -WhatIf
  Simulate deleting unlinked GPOs.
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
Param (
  [string[]]$ExcludeGPO = @('Default Domain Policy', 'Default Domain Controllers Policy'),

  [ValidatePattern('\.csv$')]
  [string]$ReportFilePath = 'C:\tmp\UnlinkedGPO.csv',

  [switch]$DeleteObjects,
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

Import-Module GroupPolicy

$ScriptName = 'Find-ADUnlinkedGPO'

#-----------------------------------------------------------[Functions]------------------------------------------------------------

Function Get-UnlinkedGPOs {
  [CmdletBinding()]
  Param ()

  Write-ADMLog "Searching for unlinked GPOs..."
  if ($ExcludeGPO) { Write-ADMLog "Excluding GPOs: $($ExcludeGPO -join ', ')" }

  Try {
    $AllGPOs = Get-GPO -All

    $UnlinkedGPOs = foreach ($GPO in $AllGPOs) {
      if ($ExcludeGPO -contains $GPO.DisplayName) { continue }

      [xml]$Report = Get-GPOReport -Guid $GPO.Id -ReportType Xml
      $Links = $Report.GPO.LinksTo

      if (-not $Links) {
        $GPO
      }
    }

    $Results = @($UnlinkedGPOs | Select-Object `
      DisplayName,
      Id,
      @{ Name = "Status"; Expression = { $_.GpoStatus } },
      CreationTime,
      ModificationTime,
      @{ Name = "Owner"; Expression = { $_.Owner } }
    )

    Write-ADMLog "Found $($Results.Count) unlinked GPO(s) out of $($AllGPOs.Count) total."
    return $Results
  }
  Catch {
    Write-ADMLog "Failed to query GPOs: $($_.Exception.Message)" -Level Error
    throw
  }
}

Function Remove-UnlinkedGPOs {
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
  Param ([array]$Data)

  Write-ADMLog "Deleting $($Data.Count) unlinked GPO(s)..."
  $SuccessCount = 0; $ErrorCount = 0

  ForEach ($Item in $Data) {
    Try {
      if ($PSCmdlet.ShouldProcess($Item.DisplayName, "Delete GPO")) {
        Remove-GPO -Guid $Item.Id -Confirm:$false
        Write-ADMLog "  $($Item.DisplayName) - Deleted"
        $SuccessCount++
      }
    }
    Catch {
      Write-ADMLog "  Failed to delete $($Item.DisplayName): $($_.Exception.Message)" -Level Warning
      $ErrorCount++
    }
  }

  Write-ADMLog "Delete complete: $SuccessCount succeeded, $ErrorCount failed."
}

#-----------------------------------------------------------[Execution]------------------------------------------------------------

Write-ADMBanner -ScriptName $ScriptName

if ($EnableLogging) { Start-ADMLogging -ScriptName $ScriptName }

$Results = Get-UnlinkedGPOs

if ($null -eq $Results -or $Results.Count -eq 0) {
  Write-ADMLog "No unlinked GPOs found. Nothing to do."
}
else {
  Export-ADMReport -Data $Results -Path $ReportFilePath -ReportName 'Unlinked GPOs report'

  if ($DeleteObjects) {
    Remove-UnlinkedGPOs -Data $Results
  }

  Send-ADMReport -EmailTo $EmailTo -EmailFrom $EmailFrom -SmtpServer $SmtpServer `
    -Subject "[$ScriptName] $($Results.Count) unlinked GPOs found" `
    -Attachments $ReportFilePath
}

if ($EnableLogging) { Stop-ADMLogging }

Write-ADMBanner -ScriptName $ScriptName -IsEnd
