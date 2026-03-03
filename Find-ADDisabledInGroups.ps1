#requires -version 5.1
#requires -Modules ActiveDirectory
<#
.SYNOPSIS
  Find disabled Active Directory users that are still members of groups.

.DESCRIPTION
  Identifies disabled user accounts that still have group memberships (other than Domain Users).
  These stale memberships represent a security risk and should be cleaned up.
  Compatible with Windows Server 2022 and Windows Server 2025 (PowerShell 5.1+).

  Optionally removes group memberships. Supports -WhatIf.

.PARAMETER SearchBase
  Optional. LDAP path to restrict the search.

.PARAMETER ExcludeOU
  Optional. Array of OU distinguished names to exclude.

.PARAMETER ReportFilePath
  Optional. Full CSV/HTML report path. Default: Rapports\Find-ADDisabledInGroups.csv (+ .html).

.PARAMETER RemoveMemberships
  Optional switch. Removes group memberships from disabled accounts. Supports -WhatIf.

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
  .\Find-ADDisabledInGroups.ps1
  Report disabled users that still have group memberships.

.EXAMPLE
  .\Find-ADDisabledInGroups.ps1 -RemoveMemberships -WhatIf
  Simulate removing group memberships from disabled accounts.

.EXAMPLE
  .\Find-ADDisabledInGroups.ps1 -RemoveMemberships -Confirm
  Remove memberships with per-item confirmation.
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
Param (
  [string]$SearchBase,
  [string[]]$ExcludeOU,

  [string]$ReportFilePath = '',

  [switch]$RemoveMemberships,
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

$ScriptName = 'Find-ADDisabledInGroups'
$Paths = Resolve-ADMReportPath -ReportFilePath $ReportFilePath -ScriptName $ScriptName -CallerPSScriptRoot $PSScriptRoot
$ReportFilePath = $Paths.CsvPath
$HtmlReportPath = $Paths.HtmlPath

#-----------------------------------------------------------[Functions]------------------------------------------------------------

Function Get-DisabledUsersInGroups {
  [CmdletBinding()]
  Param ()

  Write-ADMLog "Searching for disabled users with group memberships..."
  if ($SearchBase) { Write-ADMLog "Search base: $SearchBase" }

  Try {
    $FilterParams = @{
      Filter     = { Enabled -eq $false }
      Properties = @('MemberOf', 'LastLogonDate', 'WhenChanged')
    }
    if ($SearchBase) { $FilterParams['SearchBase'] = $SearchBase }

    $DisabledUsers = Get-ADUser @FilterParams

    if ($ExcludeOU) {
      $DisabledUsers = $DisabledUsers | Where-Object {
        -not (Test-ADMExcludedOU -DistinguishedName $_.DistinguishedName -ExcludeOUs $ExcludeOU)
      }
    }

    $AllEntries = @()

    ForEach ($User in $DisabledUsers) {
      # Exclude default 'Domain Users' primary group
      $GroupMemberships = $User.MemberOf

      if ($GroupMemberships -and $GroupMemberships.Count -gt 0) {
        ForEach ($GroupDN in $GroupMemberships) {
          $GroupName = ($GroupDN -split ',')[0] -replace '^CN=', ''

          $AllEntries += [PSCustomObject]@{
            Username          = $User.SamAccountName
            UserName          = $User.Name
            GroupName         = $GroupName
            GroupDN           = $GroupDN
            LastLogonDate     = $User.LastLogonDate
            WhenChanged       = $User.WhenChanged
            UserDN            = $User.DistinguishedName
          }
        }
      }
    }

    $Results = @($AllEntries)
    $UniqueUsers = ($Results | Select-Object -Unique Username).Count
    Write-ADMLog "Found $($Results.Count) stale membership(s) across $UniqueUsers disabled user(s)."
    return $Results
  }
  Catch {
    Write-ADMLog "Failed to query Active Directory: $($_.Exception.Message)" -Level Error
    throw
  }
}

Function Remove-StaleMemberships {
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
  Param ([array]$Data)

  $UniqueUsers = $Data | Select-Object -Unique Username
  Write-ADMLog "Removing group memberships for $($UniqueUsers.Count) disabled user(s)..."
  $SuccessCount = 0; $ErrorCount = 0

  ForEach ($Entry in $Data) {
    Try {
      if ($PSCmdlet.ShouldProcess("$($Entry.Username) from $($Entry.GroupName)", "Remove group membership")) {
        Remove-ADGroupMember -Identity $Entry.GroupDN -Members $Entry.UserDN -Confirm:$false
        Write-ADMLog "  $($Entry.Username) removed from $($Entry.GroupName)"
        $SuccessCount++
      }
    }
    Catch {
      Write-ADMLog "  Failed to remove $($Entry.Username) from $($Entry.GroupName): $($_.Exception.Message)" -Level Warning
      $ErrorCount++
    }
  }

  Write-ADMLog "Removal complete: $SuccessCount succeeded, $ErrorCount failed."
}

#-----------------------------------------------------------[Execution]------------------------------------------------------------

Write-ADMBanner -ScriptName $ScriptName

if ($EnableLogging) { Start-ADMLogging -ScriptName $ScriptName }

$Results = Get-DisabledUsersInGroups

if ($null -eq $Results -or $Results.Count -eq 0) {
  Write-ADMLog "No disabled users with group memberships found. Nothing to do."
}
else {
  Export-ADMReport -Data $Results -Path $ReportFilePath -ReportName 'Disabled users in groups report'

  $UniqueUsers = ($Results | Select-Object -Unique Username).Count
  Export-ADMHTMLReport -Data $Results -Path $HtmlReportPath `
    -Title "Comptes désactivés dans des groupes" `
    -Description "$UniqueUsers compte(s) désactivé(s) avec $($Results.Count) appartenance(s) résiduelle(s)" `
    -ScriptName $ScriptName `
    -SummaryCards @(
      @{ Label = 'Appartenances'; Value = $Results.Count; Color = '#dc3545' }
      @{ Label = 'Utilisateurs'; Value = $UniqueUsers; Color = '#e67e22' }
    )

  if ($RemoveMemberships) {
    Remove-StaleMemberships -Data $Results
  }

  Send-ADMReport -EmailTo $EmailTo -EmailFrom $EmailFrom -SmtpServer $SmtpServer `
    -Subject "[$ScriptName] $($Results.Count) stale group memberships found" `
    -Attachments $ReportFilePath
}

if ($EnableLogging) { Stop-ADMLogging }

if (-not $NoOpen) { Open-ADMReport -Path $HtmlReportPath }

Write-ADMBanner -ScriptName $ScriptName -IsEnd
