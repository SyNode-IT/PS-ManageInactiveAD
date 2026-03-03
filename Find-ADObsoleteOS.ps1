#requires -version 5.1
#requires -Modules ActiveDirectory
<#
.SYNOPSIS
  Find Active Directory computers running obsolete or end-of-life operating systems.

.DESCRIPTION
  Identifies computer objects running outdated operating systems (e.g. Windows Server 2012,
  Windows 7, Windows 8, etc.) that may no longer receive security updates.
  Compatible with Windows Server 2022 and Windows Server 2025 (PowerShell 5.1+).

  This script is read-only and does not modify any objects.

.PARAMETER ObsoletePatterns
  Optional. Array of OS name patterns (wildcards) considered obsolete.
  Defaults to a comprehensive list of end-of-life Windows versions.

.PARAMETER SearchBase
  Optional. LDAP path to restrict the search.

.PARAMETER ExcludeOU
  Optional. Array of OU distinguished names to exclude.

.PARAMETER ReportFilePath
  Optional. Full CSV/HTML report path. Default: Rapports\Find-ADObsoleteOS.csv (+ .html).

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
  .\Find-ADObsoleteOS.ps1
  Report all computers with obsolete operating systems.

.EXAMPLE
  .\Find-ADObsoleteOS.ps1 -ObsoletePatterns "*Server 2012*","*Server 2016*"
  Report computers running Server 2012 or Server 2016.

.EXAMPLE
  .\Find-ADObsoleteOS.ps1 -SearchBase "OU=Servers,DC=corp,DC=local" -EnableLogging
  Report obsolete OS in the Servers OU with logging.
#>

[CmdletBinding()]
Param (
  [string[]]$ObsoletePatterns = @(
    '*Windows XP*',
    '*Windows Vista*',
    '*Windows 7*',
    '*Windows 8*',
    '*Windows 8.1*',
    '*Windows 10*',
    '*Server 2003*',
    '*Server 2008*',
    '*Server 2012*',
    '*Server 2016*',
    '*Server 2019*'
  ),

  [string]$SearchBase,
  [string[]]$ExcludeOU,

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

$ScriptName = 'Find-ADObsoleteOS'
$Paths = Resolve-ADMReportPath -ReportFilePath $ReportFilePath -ScriptName $ScriptName -CallerPSScriptRoot $PSScriptRoot
$ReportFilePath = $Paths.CsvPath
$HtmlReportPath = $Paths.HtmlPath

#-----------------------------------------------------------[Functions]------------------------------------------------------------

Function Get-ObsoleteOSComputers {
  [CmdletBinding()]
  Param ()

  Write-ADMLog "Searching for computers with obsolete operating systems..."
  Write-ADMLog "Obsolete patterns: $($ObsoletePatterns -join ', ')"
  if ($SearchBase) { Write-ADMLog "Search base: $SearchBase" }

  Try {
    $FilterParams = @{
      Filter     = { Enabled -eq $true }
      Properties = @('OperatingSystem', 'OperatingSystemVersion', 'OperatingSystemServicePack', 'LastLogonDate', 'IPv4Address')
    }
    if ($SearchBase) { $FilterParams['SearchBase'] = $SearchBase }

    $AllComputers = Get-ADComputer @FilterParams

    $ObsoleteComputers = $AllComputers | Where-Object {
      $OS = $_.OperatingSystem
      if (-not $OS) { return $false }

      foreach ($Pattern in $ObsoletePatterns) {
        if ($OS -like $Pattern) { return $true }
      }
      return $false
    }

    if ($ExcludeOU) {
      $ObsoleteComputers = $ObsoleteComputers | Where-Object {
        -not (Test-ADMExcludedOU -DistinguishedName $_.DistinguishedName -ExcludeOUs $ExcludeOU)
      }
    }

    $Results = @($ObsoleteComputers | Select-Object `
      Name,
      OperatingSystem,
      OperatingSystemVersion,
      OperatingSystemServicePack,
      LastLogonDate,
      IPv4Address,
      DistinguishedName
    )

    Write-ADMLog "Found $($Results.Count) computer(s) with obsolete OS."

    # Summary by OS
    $Results | Group-Object OperatingSystem | ForEach-Object {
      Write-ADMLog "  $($_.Name) : $($_.Count)"
    }

    return $Results
  }
  Catch {
    Write-ADMLog "Failed to query Active Directory: $($_.Exception.Message)" -Level Error
    throw
  }
}

#-----------------------------------------------------------[Execution]------------------------------------------------------------

Write-ADMBanner -ScriptName $ScriptName

if ($EnableLogging) { Start-ADMLogging -ScriptName $ScriptName }

$Results = Get-ObsoleteOSComputers

if ($null -eq $Results -or $Results.Count -eq 0) {
  Write-ADMLog "No computers with obsolete OS found."
}
else {
  Export-ADMReport -Data $Results -Path $ReportFilePath -ReportName 'Obsolete OS report'

  Export-ADMHTMLReport -Data $Results -Path $HtmlReportPath `
    -Title "OS obsolètes" `
    -Description "$($Results.Count) ordinateur(s) avec un système d'exploitation en fin de vie" `
    -ScriptName $ScriptName `
    -SummaryCards @(
      @{ Label = 'OS obsolètes'; Value = $Results.Count; Color = '#dc3545' }
    )

  Send-ADMReport -EmailTo $EmailTo -EmailFrom $EmailFrom -SmtpServer $SmtpServer `
    -Subject "[$ScriptName] $($Results.Count) computers with obsolete OS" `
    -Attachments $ReportFilePath
}

if ($EnableLogging) { Stop-ADMLogging }

if (-not $NoOpen) { Open-ADMReport -Path $HtmlReportPath }

Write-ADMBanner -ScriptName $ScriptName -IsEnd
