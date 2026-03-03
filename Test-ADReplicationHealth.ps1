#requires -version 5.1
#requires -Modules ActiveDirectory
<#
.SYNOPSIS
  Test Active Directory replication health across domain controllers.

.DESCRIPTION
  Checks AD replication status for all domain controllers in the domain.
  Reports replication partners, last replication time, failures, and status.
  Compatible with Windows Server 2022 and Windows Server 2025 (PowerShell 5.1+).

  This script is read-only and does not modify any objects.

.PARAMETER ReportFilePath
  Optional. Full CSV/HTML report path. Default: Rapports\Test-ADReplicationHealth.csv (+ .html).

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
  .\Test-ADReplicationHealth.ps1
  Check replication health for all DCs.

.EXAMPLE
  .\Test-ADReplicationHealth.ps1 -EnableLogging -EmailTo "admin@corp.local" -SmtpServer "smtp.corp.local"
  Check replication with logging and email notification.
#>

[CmdletBinding()]
Param (
  [string]$ReportFilePath = '',

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

$ScriptName = 'Test-ADReplicationHealth'
$Paths = Resolve-ADMReportPath -ReportFilePath $ReportFilePath -ScriptName $ScriptName -CallerPSScriptRoot $PSScriptRoot
$ReportFilePath = $Paths.CsvPath
$HtmlReportPath = $Paths.HtmlPath

#-----------------------------------------------------------[Functions]------------------------------------------------------------

Function Get-ReplicationStatus {
  [CmdletBinding()]
  Param ()

  Write-ADMLog "Retrieving domain controllers..."

  Try {
    $DomainControllers = Get-ADDomainController -Filter *
    Write-ADMLog "Found $($DomainControllers.Count) domain controller(s)."

    $AllResults = @()

    ForEach ($DC in $DomainControllers) {
      Write-ADMLog "  Checking replication for $($DC.HostName)..."

      Try {
        $ReplPartners = Get-ADReplicationPartnerMetadata -Target $DC.HostName -ErrorAction Stop

        ForEach ($Partner in $ReplPartners) {
          $TimeSinceReplication = if ($Partner.LastReplicationSuccess) {
            [math]::Round(((Get-Date) - $Partner.LastReplicationSuccess).TotalMinutes, 1)
          }
          else { 'Never' }

          $AllResults += [PSCustomObject]@{
            SourceDC              = $DC.HostName
            SourceSite            = $DC.Site
            Partner               = $Partner.Partner
            PartitionDN           = ($Partner.Partition -split ',')[0..1] -join ','
            LastReplicationSuccess = $Partner.LastReplicationSuccess
            MinutesSinceReplication = $TimeSinceReplication
            LastReplicationResult  = $Partner.LastReplicationResult
            ConsecutiveFailures   = $Partner.ConsecutiveReplicationFailures
            Status                = if ($Partner.LastReplicationResult -eq 0) { 'OK' } else { 'ERROR' }
          }
        }
      }
      Catch {
        Write-ADMLog "  WARNING: Cannot reach $($DC.HostName): $($_.Exception.Message)" -Level Warning

        $AllResults += [PSCustomObject]@{
          SourceDC              = $DC.HostName
          SourceSite            = $DC.Site
          Partner               = 'N/A'
          PartitionDN           = 'N/A'
          LastReplicationSuccess = 'N/A'
          MinutesSinceReplication = 'N/A'
          LastReplicationResult  = 'Unreachable'
          ConsecutiveFailures   = 'N/A'
          Status                = 'UNREACHABLE'
        }
      }
    }

    $Results = @($AllResults)

    # Summary
    $OKCount = ($Results | Where-Object { $_.Status -eq 'OK' }).Count
    $ErrorCount = ($Results | Where-Object { $_.Status -eq 'ERROR' }).Count
    $UnreachableCount = ($Results | Where-Object { $_.Status -eq 'UNREACHABLE' }).Count

    Write-ADMLog "Replication summary: $OKCount OK, $ErrorCount ERROR, $UnreachableCount UNREACHABLE"

    if ($ErrorCount -gt 0) {
      Write-ADMLog "REPLICATION ERRORS DETECTED - Review report for details." -Level Warning
    }

    return $Results
  }
  Catch {
    Write-ADMLog "Failed to query replication status: $($_.Exception.Message)" -Level Error
    throw
  }
}

#-----------------------------------------------------------[Execution]------------------------------------------------------------

Write-ADMBanner -ScriptName $ScriptName

if ($EnableLogging) { Start-ADMLogging -ScriptName $ScriptName }

$Results = Get-ReplicationStatus

if ($null -eq $Results -or $Results.Count -eq 0) {
  Write-ADMLog "No replication data available."
}
else {
  Export-ADMReport -Data $Results -Path $ReportFilePath -ReportName 'Replication health report'

  $OKCount = ($Results | Where-Object { $_.Status -eq 'OK' }).Count
  $ErrorCount = ($Results | Where-Object { $_.Status -eq 'ERROR' }).Count
  $UnreachableCount = ($Results | Where-Object { $_.Status -eq 'UNREACHABLE' }).Count

  Export-ADMHTMLReport -Data $Results -Path $HtmlReportPath `
    -Title "Santé de la réplication AD" `
    -Description "État de la réplication entre les contrôleurs de domaine" `
    -ScriptName $ScriptName `
    -SummaryCards @(
      @{ Label = 'OK'; Value = $OKCount; Color = '#28a745' }
      @{ Label = 'Erreurs'; Value = $ErrorCount; Color = '#dc3545' }
      @{ Label = 'Injoignables'; Value = $UnreachableCount; Color = '#e67e22' }
    ) `
    -StatusMappings @{
      'Status' = @{ 'OK' = 'success'; 'ERROR' = 'danger'; 'UNREACHABLE' = 'warning' }
    }

  $HasErrors = ($Results | Where-Object { $_.Status -ne 'OK' }).Count -gt 0
  $SubjectPrefix = if ($HasErrors) { 'WARNING' } else { 'OK' }

  Send-ADMReport -EmailTo $EmailTo -EmailFrom $EmailFrom -SmtpServer $SmtpServer `
    -Subject "[$ScriptName] $SubjectPrefix - Replication health check" `
    -Attachments $ReportFilePath
}

if ($EnableLogging) { Stop-ADMLogging }

if (-not $NoOpen) { Open-ADMReport -Path $HtmlReportPath }

Write-ADMBanner -ScriptName $ScriptName -IsEnd
