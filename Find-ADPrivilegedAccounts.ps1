#requires -version 5.1
#requires -Modules ActiveDirectory
<#
.SYNOPSIS
  Audit members of privileged Active Directory groups.

.DESCRIPTION
  Lists all members of critical privileged groups (Domain Admins, Enterprise Admins,
  Schema Admins, Administrators, Account Operators, Backup Operators, etc.).
  Compatible with Windows Server 2022 and Windows Server 2025 (PowerShell 5.1+).

  This script is read-only and does not modify any objects.

.PARAMETER Groups
  Optional. Array of group names to audit. Defaults to a comprehensive list of
  built-in privileged groups.

.PARAMETER IncludeNested
  Optional switch. Recursively resolves nested group memberships. Default: $false.

.PARAMETER ReportFilePath
  Optional. Full CSV/HTML report path. Default: Rapports\Find-ADPrivilegedAccounts.csv (+ .html).

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
  .\Find-ADPrivilegedAccounts.ps1
  Audit all default privileged groups.

.EXAMPLE
  .\Find-ADPrivilegedAccounts.ps1 -IncludeNested
  Audit with recursive nested group resolution.

.EXAMPLE
  .\Find-ADPrivilegedAccounts.ps1 -Groups "Domain Admins","IT-Admins"
  Audit specific groups only.
#>

[CmdletBinding()]
Param (
  [string[]]$Groups = @(
    'Domain Admins',
    'Enterprise Admins',
    'Schema Admins',
    'Administrators',
    'Account Operators',
    'Backup Operators',
    'Server Operators',
    'Print Operators',
    'DnsAdmins',
    'Group Policy Creator Owners'
  ),

  [switch]$IncludeNested,

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

$ScriptName = 'Find-ADPrivilegedAccounts'
$Paths = Resolve-ADMReportPath -ReportFilePath $ReportFilePath -ScriptName $ScriptName -CallerPSScriptRoot $PSScriptRoot
$ReportFilePath = $Paths.CsvPath
$HtmlReportPath = $Paths.HtmlPath

#-----------------------------------------------------------[Functions]------------------------------------------------------------

Function Get-PrivilegedMembers {
  [CmdletBinding()]
  Param ()

  Write-ADMLog "Auditing privileged groups: $($Groups -join ', ')"
  if ($IncludeNested) { Write-ADMLog "Nested group resolution: enabled" }

  $AllMembers = @()

  ForEach ($GroupName in $Groups) {
    Try {
      $Group = Get-ADGroup -Filter { Name -eq $GroupName } -ErrorAction SilentlyContinue

      if (-not $Group) {
        Write-ADMLog "  Group not found: $GroupName (may not exist in this domain)" -Level Warning
        continue
      }

      $MemberParams = @{ Identity = $Group.DistinguishedName }
      if ($IncludeNested) { $MemberParams['Recursive'] = $true }

      $Members = Get-ADGroupMember @MemberParams -ErrorAction SilentlyContinue

      ForEach ($Member in $Members) {
        $UserInfo = $null
        if ($Member.objectClass -eq 'user') {
          $UserInfo = Get-ADUser -Identity $Member.DistinguishedName -Properties LastLogonDate, Enabled, PasswordLastSet -ErrorAction SilentlyContinue
        }

        $AllMembers += [PSCustomObject]@{
          GroupName       = $GroupName
          MemberName      = $Member.Name
          SamAccountName  = $Member.SamAccountName
          ObjectClass     = $Member.objectClass
          Enabled         = if ($UserInfo) { $UserInfo.Enabled } else { 'N/A' }
          LastLogonDate   = if ($UserInfo) { $UserInfo.LastLogonDate } else { 'N/A' }
          PasswordLastSet = if ($UserInfo) { $UserInfo.PasswordLastSet } else { 'N/A' }
          DistinguishedName = $Member.DistinguishedName
        }
      }

      $MemberCount = @($Members).Count
      Write-ADMLog "  $GroupName : $MemberCount member(s)"
    }
    Catch {
      Write-ADMLog "  Error querying group $GroupName : $($_.Exception.Message)" -Level Warning
    }
  }

  $Results = @($AllMembers)
  Write-ADMLog "Total privileged entries: $($Results.Count)"
  return $Results
}

#-----------------------------------------------------------[Execution]------------------------------------------------------------

Write-ADMBanner -ScriptName $ScriptName

if ($EnableLogging) { Start-ADMLogging -ScriptName $ScriptName }

$Results = Get-PrivilegedMembers

if ($null -eq $Results -or $Results.Count -eq 0) {
  Write-ADMLog "No privileged accounts found. Nothing to report."
}
else {
  Export-ADMReport -Data $Results -Path $ReportFilePath -ReportName 'Privileged accounts audit'

  # Summary statistics
  $UniqueUsers = ($Results | Where-Object { $_.ObjectClass -eq 'user' } | Select-Object -Unique SamAccountName).Count
  $UniqueGroups = ($Results | Select-Object -Unique GroupName).Count
  Write-ADMLog "Summary: $UniqueUsers unique user(s) across $UniqueGroups group(s)."

  Export-ADMHTMLReport -Data $Results -Path $HtmlReportPath `
    -Title "Comptes privilégiés" `
    -Description "Audit des membres des groupes à privilèges élevés" `
    -ScriptName $ScriptName `
    -SummaryCards @(
      @{ Label = 'Entrées'; Value = $Results.Count; Color = '#0078d4' }
      @{ Label = 'Utilisateurs'; Value = $UniqueUsers; Color = '#dc3545' }
      @{ Label = 'Groupes'; Value = $UniqueGroups; Color = '#e67e22' }
    )

  Send-ADMReport -EmailTo $EmailTo -EmailFrom $EmailFrom -SmtpServer $SmtpServer `
    -Subject "[$ScriptName] Privileged accounts audit - $UniqueUsers users across $UniqueGroups groups" `
    -Attachments $ReportFilePath
}

if ($EnableLogging) { Stop-ADMLogging }

if (-not $NoOpen) { Open-ADMReport -Path $HtmlReportPath }

Write-ADMBanner -ScriptName $ScriptName -IsEnd
