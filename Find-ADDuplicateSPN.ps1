#requires -version 5.1
#requires -Modules ActiveDirectory
<#
.SYNOPSIS
  Find duplicate Service Principal Names (SPNs) in Active Directory.

.DESCRIPTION
  Identifies duplicate SPNs across all user and computer objects in the domain.
  Duplicate SPNs cause Kerberos authentication failures and should be resolved.
  Compatible with Windows Server 2022 and Windows Server 2025 (PowerShell 5.1+).

  This script is read-only and does not modify any objects.

.PARAMETER ReportFilePath
  Optional. Full CSV path for the report. Default: C:\tmp\DuplicateSPN.csv.

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

.EXAMPLE
  .\Find-ADDuplicateSPN.ps1
  Report all duplicate SPNs in the domain.

.EXAMPLE
  .\Find-ADDuplicateSPN.ps1 -EnableLogging -EmailTo "admin@corp.local" -SmtpServer "smtp.corp.local"
  Report with logging and email notification.
#>

[CmdletBinding()]
Param (
  [ValidatePattern('\.csv$')]
  [string]$ReportFilePath = 'C:\tmp\DuplicateSPN.csv',

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

$ScriptName = 'Find-ADDuplicateSPN'

#-----------------------------------------------------------[Functions]------------------------------------------------------------

Function Get-DuplicateSPNs {
  [CmdletBinding()]
  Param ()

  Write-ADMLog "Collecting all SPNs from the domain (users and computers)..."

  Try {
    $SPNMap = @{}

    # Collect SPNs from user accounts
    $Users = Get-ADUser -Filter { ServicePrincipalName -like "*" } -Properties ServicePrincipalName
    ForEach ($User in $Users) {
      ForEach ($SPN in $User.ServicePrincipalName) {
        $SPNLower = $SPN.ToLower()
        if (-not $SPNMap.ContainsKey($SPNLower)) {
          $SPNMap[$SPNLower] = @()
        }
        $SPNMap[$SPNLower] += [PSCustomObject]@{
          SPN               = $SPN
          ObjectName        = $User.SamAccountName
          ObjectType        = 'User'
          DistinguishedName = $User.DistinguishedName
        }
      }
    }

    # Collect SPNs from computer accounts
    $Computers = Get-ADComputer -Filter { ServicePrincipalName -like "*" } -Properties ServicePrincipalName
    ForEach ($Computer in $Computers) {
      ForEach ($SPN in $Computer.ServicePrincipalName) {
        $SPNLower = $SPN.ToLower()
        if (-not $SPNMap.ContainsKey($SPNLower)) {
          $SPNMap[$SPNLower] = @()
        }
        $SPNMap[$SPNLower] += [PSCustomObject]@{
          SPN               = $SPN
          ObjectName        = $Computer.Name
          ObjectType        = 'Computer'
          DistinguishedName = $Computer.DistinguishedName
        }
      }
    }

    $TotalSPNs = ($SPNMap.Values | Measure-Object -Property Count -Sum).Sum
    Write-ADMLog "Total SPNs collected: $TotalSPNs"

    # Find duplicates
    $Duplicates = @()
    ForEach ($Key in $SPNMap.Keys) {
      if ($SPNMap[$Key].Count -gt 1) {
        ForEach ($Entry in $SPNMap[$Key]) {
          $Duplicates += [PSCustomObject]@{
            SPN               = $Entry.SPN
            ObjectName        = $Entry.ObjectName
            ObjectType        = $Entry.ObjectType
            DuplicateCount    = $SPNMap[$Key].Count
            DistinguishedName = $Entry.DistinguishedName
          }
        }
      }
    }

    $Results = @($Duplicates | Sort-Object SPN, ObjectName)
    $UniqueDuplicateSPNs = ($Results | Select-Object -Unique SPN).Count
    Write-ADMLog "Found $UniqueDuplicateSPNs duplicate SPN(s) affecting $($Results.Count) object(s)."
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

$Results = Get-DuplicateSPNs

if ($null -eq $Results -or $Results.Count -eq 0) {
  Write-ADMLog "No duplicate SPNs found. Kerberos authentication should be unaffected."
}
else {
  Export-ADMReport -Data $Results -Path $ReportFilePath -ReportName 'Duplicate SPNs report'

  Write-ADMLog "" -Level Warning
  Write-ADMLog "ACTION REQUIRED: Duplicate SPNs cause Kerberos authentication failures." -Level Warning
  Write-ADMLog "Review the report and use 'setspn -d <SPN> <account>' to remove duplicates manually." -Level Warning

  Send-ADMReport -EmailTo $EmailTo -EmailFrom $EmailFrom -SmtpServer $SmtpServer `
    -Subject "[$ScriptName] WARNING: $($Results.Count) duplicate SPN entries found" `
    -Attachments $ReportFilePath
}

if ($EnableLogging) { Stop-ADMLogging }

Write-ADMBanner -ScriptName $ScriptName -IsEnd
