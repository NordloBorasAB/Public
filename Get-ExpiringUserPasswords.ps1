<#
.SYNOPSIS
    Post Users with Expiring Passwords as Microsoft Teams Message.

.DESCRIPTION
    Send a Microsoft Teams message containing all of your Active Directory user accounts that have passwords expiring in X days or less.

.NOTES
    FileName:   Get-ExpiringUserPasswords.ps1
    Authors:    Bradley Wyatt
		Victor Dahlberg, Nordlo
    Created:	2020-10-15
    Updated:    2020-10-15

    Version history:
    1.0 - (2020-10-15) Script created
#>

# Get all users whose password expires in X days and less, this sets the days
$PasswordDays = Get-ItemProperty -Path "HKLM:\SOFTWARE\Nordlo AB\Nordlo Monitor" | Select-Object -ExpandProperty "PasswordDays"

# Teams web hook URL
$WebhookURI = Get-ItemProperty -Path "HKLM:\SOFTWARE\Nordlo AB\Nordlo Monitor" | Select-Object -ExpandProperty "WEBHOOKURI"

$ItemImage = 'https://img.icons8.com/color/1600/circled-user-male-skin-type-1-2.png'

$PWExpiringTable = New-Object 'System.Collections.Generic.List[System.Object]'
$ArrayTable = New-Object 'System.Collections.Generic.List[System.Object]'
$ArrayTableExpired = New-Object 'System.Collections.Generic.List[System.Object]'

$ExpiringUsers = 0
$ExpiredUsers = 0

$maxPasswordAge = ((Get-ADDefaultDomainPasswordPolicy).MaxPasswordAge).Days

# Get all users and store in a variable named $Users
Get-ADUser -filter { (PasswordNeverExpires -eq $false) -and (enabled -eq $true) } -properties * | ForEach-Object {
	Write-Host "Working on $($_.Name)" -ForegroundColor White
	
	# Get Password last set date
	$passwordSetDate = ($_.PasswordLastSet)
	
	if ($null -eq $passwordSetDate)	{
		# 0x1 = Never Logged On
		$daystoexpire = "0x1"
	}
	
	else {
		# Check for Fine Grained Passwords
		$PasswordPol = (Get-ADUserResultantPasswordPolicy -Identity $_.objectGUID -ErrorAction SilentlyContinue)
		
		if ($Null -ne ($PasswordPol)) {
			$maxPasswordAge = ($PasswordPol).MaxPasswordAge
		}
		
		$expireson = $passwordsetdate.AddDays($maxPasswordAge)
		$today = (Get-Date)
		
		# Gets the count on how many days until the password expires and stores it in the $daystoexpire var
		$daystoexpire = (New-TimeSpan -Start $today -End $Expireson).Days
		if ($daystoexpire -lt ($PasswordDays + 1)) {
			Write-Host "$($_.Name) will be added to table" -ForegroundColor red
			if ($daystoexpire -lt 0) {
				#0 x2 = Password has been expired
				$daystoexpire = "Password is Expired"
			}
			$obj = [PSCustomObject]@{	
				'Name' = $_.name
				'DaysUntil' = $daystoexpire
				'EmailAddress' = $_.emailaddress
				'LastSet' = $_.PasswordLastSet.ToShortDateString()
				'LockedOut' = $_.LockedOut
				'UPN'  = $_.UserPrincipalName
				'Enabled' = $_.Enabled
				'PasswordNeverExpires' = $_.PasswordNeverExpires
			}
			$PWExpiringTable.Add($obj)
		}
		else {
			Write-Host "$($_.Name)'s account is compliant" -ForegroundColor Green
		}
	}
}

# Sort the table so the Teams message shows expiring soonest to latest
$PWExpiringTable = $PWExpiringTable | Sort-Object DaysUntil
$PWExpiringTable | ForEach-Object {
	
	if ($_.DaysUntil -eq "Password is Expired")	{
		Write-Host "$($_.name) is expired" -ForegroundColor DarkRed
		$ExpiredUsers++
		$SectionExpired = @{
			activityTitle = "$($_.Name)"
			activitySubtitle = "$($_.EmailAddress)"
			activityText  = "$($_.Name)'s password has already expired!"
			activityImage = $ItemImage
		}
		$ArrayTableExpired.add($SectionExpired)
	}
	else {
		Write-Host "$($_.name) is expiring" -ForegroundColor DarkYellow
		$ExpiringUsers++
		$Section = @{
			activityTitle = "$($_.Name)"
			activitySubtitle = "$($_.EmailAddress)"
			activityText  = "$($_.Name) needs to change their password in $($_.DaysUntil) days"
			activityImage = $ItemImage
		}		
		$ArrayTable.add($Section)
	}
}

Write-Host "Expired Accounts: $($($ExpiredUsers).count)" -ForegroundColor Yellow
Write-Host "Expiring Accounts: $($($ExpiringUsers).count)" -ForegroundColor Yellow

$body = ConvertTo-Json -Depth 8 @{
	title = 'Users With Password Expiring - Notification'
	text  = "There are $($ArrayTable.Count) users that have passwords expiring in $($PasswordDays) days or less"
	sections = $ArrayTable
	
}
Write-Host "Sending expiring users notification" -ForegroundColor Green
Invoke-RestMethod -uri $WebhookURI -Method Post -body $body -ContentType 'application/json'

$body2 = ConvertTo-Json -Depth 8 @{
	title = 'Users With Password Expired - Notification'
	text  = "There are $($ArrayTableExpired.Count) users that have passwords that have expired already"
	sections = $ArrayTableExpired
	
}
Write-Host "Sending expired users notification" -ForegroundColor Green
Invoke-RestMethod -uri $WebhookURI -Method Post -body $body2 -ContentType 'application/json'
