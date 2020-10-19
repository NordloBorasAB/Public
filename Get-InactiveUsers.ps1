<#
.SYNOPSIS
    Post Inactive User Accounts as a Microsoft Teams Message.

.DESCRIPTION
    Send a Microsoft Teams message containing all of your Active Directory user accounts have not logged on in X days or more.

.NOTES
    FileName:   Get-InactiveUsers.ps1
	Authors:    Bradley Wyatt
				Victor Dahlberg, Nordlo
    Created:    2020-10-15
    Updated:    2020-10-15

    Version history:
    1.0 - (2020-10-15) Script created
#>

# Teams webhook url
$WebhookURI = Get-ItemProperty -Path "HKLM:\SOFTWARE\Nordlo AB\Nordlo Monitor" | Select-Object -ExpandProperty "WEBHOOKURI"

# Find user accounts that have not logged on in X days or more.
$AccountDays = Get-ItemProperty -Path "HKLM:\SOFTWARE\Nordlo AB\Nordlo Monitor" | Select-Object -ExpandProperty "ACCOUNTDAYS"

# Image on the left hand side, here I have a regular user picture
$ItemImage = 'https://img.icons8.com/color/1600/circled-user-male-skin-type-1-2.png'

# Get the date.time object for XX days ago
$ExpireDays = (get-date).adddays(-$AccountDays)

$InactiveUsersTable = New-Object 'System.Collections.Generic.List[System.Object]'
$ArrayTable = New-Object 'System.Collections.Generic.List[System.Object]'

# If lastlogondate is not empty, and less than or equal to XX days and enabled
Get-ADUser -properties * -filter { (lastlogondate -like "*" -and lastlogondate -le $ExpireDays) -AND (Enabled -eq $True) } | ForEach-Object {
	Write-Host "Working on $($_.Name)" -ForegroundColor White
	
	$LastLogonDate = $_.LastLogonDate
	$Today = (GET-DATE)
	
	$DaysSince = ((NEW-TIMESPAN –Start $LastLogonDate –End $Today).Days).ToString() + " Days ago"
	$obj = [PSCustomObject]@{
		'Name' = $_.name
		'LastLogon' = $DaysSince
		'LastLogonDate' = (($_.LastLogonDate).ToShortDateString())
		'EmailAddress' = $_.emailaddress
		'LockedOut' = $_.LockedOut
		'UPN'  = $_.UserPrincipalName
		'Enabled' = $_.Enabled
		'PasswordNeverExpires' = $_.PasswordNeverExpires
		'SamAccountName' = $_.SamAccountName
	}
	$InactiveUsersTable.Add($obj)
}
Write-Host "Inactive users $($($InactiveUsersTable).count)"

$InactiveUsersTable | ForEach-Object {
	$Section = @{
		activityTitle = "$($_.Name)"
		activitySubtitle = "$($_.EmailAddress)"
		activityText  = "$($_.Name)'s last logon was $($_.LastLogon)"
		activityImage = $ItemImage
		facts		  = @(
			@{
				name  = 'Last Logon Date:'
				value = $_.LastLogonDate
			},
			@{
				name  = 'Enabled:'
				value = $_.Enabled
			},
			@{
				name  = 'Locked Out:'
				value = $_.LockedOut
			},
			@{
				name  = 'SamAccountName:'
				value = $_.SamAccountName
			}
		)
	}
	$ArrayTable.add($section)
}

$body = ConvertTo-Json -Depth 8 @{
	title = "Inactive Users - Notification"
	text  = "There are $($ArrayTable.Count) users who have not logged in since $($90Days.ToShortDateString()) or earlier"
	sections = $ArrayTable
	
}
Write-Host "Sending inactive account POST" -ForegroundColor Green
Invoke-RestMethod -uri $WebhookURI -Method Post -body $body -ContentType 'application/json'
