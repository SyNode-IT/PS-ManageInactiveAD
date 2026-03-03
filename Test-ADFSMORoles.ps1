#requires -version 5.1
#requires -Modules ActiveDirectory
<#
.SYNOPSIS
  Audit FSMO role holders and domain controller health in Active Directory.

.DESCRIPTION
  Reports on the 5 FSMO roles placement and tests the availability of each DC.
  Compatible with Windows Server 2022 and Windows Server 2025 (PowerShell 5.1+).

  This script is read-only and does not modify any objects.

  FSMO Roles checked:
    - Schema Master (Forest-wide)
    - Domain Naming Master (Forest-wide)
    - PDC Emulator (Domain-wide)
    - RID Master (Domain-wide)
    - Infrastructure Master (Domain-wide)

.PARAMETER ReportFilePath
  Optional. Full CSV/HTML report path. Default: Rapports\Test-ADFSMORoles.csv (+ .html).

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
  .\Test-ADFSMORoles.ps1
  Report FSMO role holders and DC health.

.EXAMPLE
  .\Test-ADFSMORoles.ps1 -EnableLogging
  Report with logging enabled.
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

$ScriptName = 'Test-ADFSMORoles'
$Paths = Resolve-ADMReportPath -ReportFilePath $ReportFilePath -ScriptName $ScriptName -CallerPSScriptRoot $PSScriptRoot
$ReportFilePath = $Paths.CsvPath
$HtmlReportPath = $Paths.HtmlPath

#-----------------------------------------------------------[Functions]------------------------------------------------------------

Function Get-FSMORoleStatus {
  [CmdletBinding()]
  Param ()

  Write-ADMLog "Retrieving FSMO role holders..."

  Try {
    $Domain = Get-ADDomain
    $Forest = Get-ADForest

    $FSMORoles = @(
      [PSCustomObject]@{
        Role        = 'Schema Master'
        Scope       = 'Forest'
        Holder      = $Forest.SchemaMaster
        Reachable   = 'Testing...'
      },
      [PSCustomObject]@{
        Role        = 'Domain Naming Master'
        Scope       = 'Forest'
        Holder      = $Forest.DomainNamingMaster
        Reachable   = 'Testing...'
      },
      [PSCustomObject]@{
        Role        = 'PDC Emulator'
        Scope       = 'Domain'
        Holder      = $Domain.PDCEmulator
        Reachable   = 'Testing...'
      },
      [PSCustomObject]@{
        Role        = 'RID Master'
        Scope       = 'Domain'
        Holder      = $Domain.RIDMaster
        Reachable   = 'Testing...'
      },
      [PSCustomObject]@{
        Role        = 'Infrastructure Master'
        Scope       = 'Domain'
        Holder      = $Domain.InfrastructureMaster
        Reachable   = 'Testing...'
      }
    )

    # Test connectivity for each role holder
    $TestedHosts = @{}

    ForEach ($Role in $FSMORoles) {
      $HostName = $Role.Holder

      if (-not $TestedHosts.ContainsKey($HostName)) {
        Try {
          $DC = Get-ADDomainController -Identity $HostName -ErrorAction Stop
          $TestedHosts[$HostName] = 'Yes'
        }
        Catch {
          $TestedHosts[$HostName] = 'No'
        }
      }

      $Role.Reachable = $TestedHosts[$HostName]
    }

    # Display summary
    ForEach ($Role in $FSMORoles) {
      $Status = if ($Role.Reachable -eq 'Yes') { 'OK' } else { 'UNREACHABLE' }
      $Level = if ($Role.Reachable -eq 'Yes') { 'Info' } else { 'Warning' }
      Write-ADMLog "  $($Role.Role) : $($Role.Holder) [$Status]" -Level $Level
    }

    # DC overview
    Write-ADMLog ""
    Write-ADMLog "Domain Controller overview:"

    $AllDCs = Get-ADDomainController -Filter *
    $DCResults = @()

    ForEach ($DC in $AllDCs) {
      $IsGC = $DC.IsGlobalCatalog
      $IsRO = $DC.IsReadOnly
      $Site = $DC.Site
      $OS = $DC.OperatingSystem

      $Roles = @()
      ForEach ($Role in $FSMORoles) {
        if ($Role.Holder -eq $DC.HostName) {
          $Roles += $Role.Role
        }
      }
      $RoleList = if ($Roles.Count -gt 0) { $Roles -join ', ' } else { 'None' }

      $DCResults += [PSCustomObject]@{
        DCName          = $DC.HostName
        Site            = $Site
        OperatingSystem = $OS
        IsGlobalCatalog = $IsGC
        IsReadOnly      = $IsRO
        FSMORoles       = $RoleList
        IPv4Address     = $DC.IPv4Address
      }

      Write-ADMLog "  $($DC.HostName) | Site: $Site | GC: $IsGC | Roles: $RoleList"
    }

    # Combine FSMO and DC data for report
    $ReportData = @()

    ForEach ($Role in $FSMORoles) {
      $ReportData += [PSCustomObject]@{
        Type        = 'FSMO Role'
        Name        = $Role.Role
        Scope       = $Role.Scope
        Holder      = $Role.Holder
        Status      = if ($Role.Reachable -eq 'Yes') { 'OK' } else { 'UNREACHABLE' }
        Details     = ''
      }
    }

    ForEach ($DC in $DCResults) {
      $ReportData += [PSCustomObject]@{
        Type        = 'Domain Controller'
        Name        = $DC.DCName
        Scope       = $DC.Site
        Holder      = $DC.OperatingSystem
        Status      = "GC=$($DC.IsGlobalCatalog) RO=$($DC.IsReadOnly)"
        Details     = $DC.FSMORoles
      }
    }

    $Results = @($ReportData)
    Write-ADMLog "Total: $($AllDCs.Count) DC(s), $($FSMORoles.Count) FSMO roles."
    return $Results
  }
  Catch {
    Write-ADMLog "Failed to query AD topology: $($_.Exception.Message)" -Level Error
    throw
  }
}

#-----------------------------------------------------------[Execution]------------------------------------------------------------

Write-ADMBanner -ScriptName $ScriptName

if ($EnableLogging) { Start-ADMLogging -ScriptName $ScriptName }

$Results = Get-FSMORoleStatus

if ($null -eq $Results -or $Results.Count -eq 0) {
  Write-ADMLog "No data available."
}
else {
  Export-ADMReport -Data $Results -Path $ReportFilePath -ReportName 'FSMO roles and DC report'

  $FSMOCount = ($Results | Where-Object { $_.Type -eq 'FSMO Role' }).Count
  $DCCount = ($Results | Where-Object { $_.Type -eq 'Domain Controller' }).Count
  $Issues = ($Results | Where-Object { $_.Status -eq 'UNREACHABLE' }).Count

  Export-ADMHTMLReport -Data $Results -Path $HtmlReportPath `
    -Title "Rôles FSMO et contrôleurs de domaine" `
    -Description "Audit des rôles FSMO et de la disponibilité des DCs" `
    -ScriptName $ScriptName `
    -SummaryCards @(
      @{ Label = 'Rôles FSMO'; Value = $FSMOCount; Color = '#0078d4' }
      @{ Label = 'DCs'; Value = $DCCount; Color = '#28a745' }
      @{ Label = 'Problèmes'; Value = $Issues; Color = if ($Issues -gt 0) { '#dc3545' } else { '#28a745' } }
    ) `
    -StatusMappings @{
      'Status' = @{ 'OK' = 'success'; 'UNREACHABLE' = 'danger' }
    }

  $HasIssues = ($Results | Where-Object { $_.Status -eq 'UNREACHABLE' }).Count -gt 0
  $SubjectPrefix = if ($HasIssues) { 'WARNING' } else { 'OK' }

  Send-ADMReport -EmailTo $EmailTo -EmailFrom $EmailFrom -SmtpServer $SmtpServer `
    -Subject "[$ScriptName] $SubjectPrefix - FSMO roles and DC health" `
    -Attachments $ReportFilePath
}

if ($EnableLogging) { Stop-ADMLogging }

if (-not $NoOpen) { Open-ADMReport -Path $HtmlReportPath }

Write-ADMBanner -ScriptName $ScriptName -IsEnd
