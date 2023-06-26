#New-KeePassDatabaseConfiguration -DatabaseProfileName '*****' -DatabasePath 'C:\Proact\KeePass-2.53\*****\Database.kdbx' -KeyPath 'C:\Proact\KeePass-2.53\*****\Database.keyx' -UseMasterKey -Default
#Remove-KeePassDatabaseConfiguration -DatabaseProfileName '*****'
#Get-KeePassEntry -DatabaseProfileName '*****' -AsPlainText

#//Run to install/reinstall Dataontap module, should be made a comment afterwards again with '#'.
#Install-Module DataONTAP -Force -Verbose

#//Run to install/reinstall Poshkeepass module, should be made a comment afterwards again.
#Install-Module PoShKeePass -Force -Verbose


#//The Import module can be left as is so they are properly loaded if the server/computer/powershell is restarted
Import-Module NetApp.ONTAP -Force
Import-Module PoShKeePass -Force


$OutPutFile = "C:\Proact\Statusmail historik\2023\$(get-date -f yyyy-MM-dd)_log.txt"
$i = 1
while (Test-Path $OutPutFile) {
    $OutPutFile = "C:\Proact\Statusmail historik\2023\$(get-date -f yyyy-MM-dd)_log$i.txt"
    $i++
}

#output script
function Write-ToConsoleAndFile {
    param(
        $text,
        $file,
        $color = "white"
    )
    Write-Host $text -ForegroundColor $color
    $text | Out-File $file -Append -Force
}

#Add cluster IP/DNS (DNS prefered,better output) that you want the script to check, add them in an array one line for each.
$Cluster_List = Get-Content "C:\Proact\clusterlist.txt"


# Store the Entries into a variable
$kpentries = Get-KeePassEntry -KeePassEntryGroupPath 'Database' -DatabaseProfileName Tranås

# Define the entry titles from keepass for which you want to retrieve the passwords 
$entryTitles = @("172.16.51.11", "172.16.51.21", "172.16.51.76")

# Empty array to hold the passwords
$passwords = @()

# Loop through each entry title and retrieve the password from $kpentries
foreach ($entryTitle in $entryTitles) {
    $entry = $kpentries | Where-Object { $_.Title -eq $entryTitle }
    $password = $entry | Select-Object -ExpandProperty Password
    $passwords += $password
}

# Create credentials for each password variable, if more entries/clusterpasswords exist in keepass just add on more rows 6,7,8 etc
$username = "admin"
$Credential1 = New-Object System.Management.Automation.PSCredential -ArgumentList $username, $passwords[0]
$Credential2 = New-Object System.Management.Automation.PSCredential -ArgumentList $username, $passwords[1]
$Credential3 = New-Object System.Management.Automation.PSCredential -ArgumentList $username, $passwords[2]
$Credential4 = New-Object System.Management.Automation.PSCredential -ArgumentList $username, $passwords[3]
$Credential5 = New-Object System.Management.Automation.PSCredential -ArgumentList $username, $passwords[4]
$Credential6 = New-Object System.Management.Automation.PSCredential -ArgumentList $username, $passwords[5]


Set-ExecutionPolicy Unrestricted -force | Out-Null

#will run below script on each cluster in the Cluster_list until all is run, if more clusters exist that need to be checked just add on more rows 6,7,8 etc
ForEach ($Cluster in $Cluster_List) {

    $credObject = $null

    If ($Cluster -imatch "172.16.51.11") {
        $credObject = $Credential1
    }
    elseif ($Cluster -imatch "172.16.51.21") {
        $credObject = $Credential2
    }
    elseif ($Cluster -imatch "172.16.51.76") {
        $credObject = $Credential3
    }

    # Check if we have a valid credential object
    if ($credObject) {
        Write-Host "Connecting to $Cluster with username: $($credObject.UserName)"
                Try {
                    Connect-NcController $Cluster -Credential $credObject -HTTPS
                } Catch {
                    Write-Host "Error connecting to $($Cluster): $($_.Exception.Message)"
                    continue
                }
            } else {
                Write-Host "No credentials found for $Cluster"
                return # Exit the script if no credentials were found for a cluster in the list
            }


            #//currentlyconnected node
            #$Nodename = Get-NcNode | Select-Object -ExpandProperty Node | Sort-Object -Property controller
            # Print the name of the current node
            #Write-ToConsoleAndFile -text "Connecting to $Nodename" -file $OutPutFile

            #//Get todays date and version of ONTAP
            $Date = Get-Date -format yyyy.MM.dd.hh.mm
            Write-ToConsoleAndFile -text "TimeStamp:",$Date -file $OutPutFile

            #//systemcheck
            Write-ToConsoleAndFile -text "------------- Ontap System Check -------------" -file $OutPutFile
            #//Check nodenames and serialnumber of nodes
            $Nodes = Get-NcNode | select Node, IsNodeHealthy, NodeLocation, NodeUptimeTS, ProductVersion, NvramBatteryStatus, EnvFailedFanMessage, EnvFailedPowerSupplyMessage | sort Node
            Write-ToConsoleAndFile -text $Nodes -file $OutPutFile

            #//Check Aggregates overall storage
            Write-ToConsoleAndFile -text "------------- Aggregate information ----------" -file $OutPutFile
            $Aggregates = Get-NcAggr | Where-Object { $_.Name -notlike "aggr*_root" }
            Write-ToConsoleAndFile -text $Aggregates -file $OutPutFile

            Write-ToConsoleAndFile -text "------------- LIF Status --------------" -file $OutPutFile

            #//Checking LIF Status
            $LIF_Status =  Get-NcNetInterface -Name * | Where-Object -Property IsHome -EQ $False | Sort-Object -Property InterfaceName | Format-Table -Property InterfaceName, IsHome, CurrentNode 

            if (!$LIF_Status) {
                 Write-ToConsoleAndFile -text "ALL Lifs are currently home" -file $OutPutFile
                 Write-ToConsoleAndFile -text "`r`n" -file $OutPutFile
                }
                 Else
                {
                 Write-ToConsoleAndFile -text "These LIFs are not home:" -file $OutPutFile
                 Write-ToConsoleAndFile -text $LIF_Status -file $OutPutFile

                }#

            #//Checking for volumes above 88%
            Write-ToConsoleAndFile -text "------------- Volumes Above 88% --------------" -file $OutPutFile
            $max_vol_percentused = 88

            $vol_low_space = get-ncvol |  where-object {$_.used -gt "$max_vol_percentused"} 
            if (!$vol_low_space){
                Write-ToConsoleAndFile -text "All volumes have sufficient free space!" -file $OutPutFile
                Write-ToConsoleAndFile -text "`r`n" -file $OutPutFile
                }
            else 
                {
	            Write-ToConsoleAndFile -text "The following NetApp volumes are starting to get full, extend volumes!" -file $OutPutFile
 	            Write-ToConsoleAndFile -text $vol_low_space -file $OutPutFile
            }

            #//Checking for files/inodes above 79%, at 8% Ontap starts to give warnings about this
            Write-ToConsoleAndFile -text "------------- Inodes/Files Above 79% --------------" -file $OutPutFile
            $InodesUsed = Get-Ncvol | ForEach-Object {
                $Limit = if($_.FilesTotal -as [int]) { $_.FilesTotal} else { 0 }
                $Used = if($_.FilesUsed -as [int]) { $_.Filesused} else { 0 }
                if($Limit -eq 0){
                    $Percentage = 0
                }
                else {
                    $Percentage = ($Used / $Limit)
                }
                if ($Percentage -gt .88 -and $_.NcController,$_.Vserver,$_.Name -match '^[a-z0-9]+$') {
                    [PSCustomObject]@{
                        Controller = $_.NcController
                        SVM = $_.Vserver
                        Name = $_.Name
                        Used = $Used
                        Limit = $Limit
                        Percentage = $Percentage.Tostring("P")
                    }
                }
            }

            # check if any inodes were found and print appropriate message
            if ($InodesUsed -eq $null) {
                Write-ToConsoleAndFile -text "No inodes above 79% found!" -file $OutPutFile
            } else {
                Write-ToConsoleAndFile -text $InodesUsed -file $OutPutFile
            }

            Write-ToConsoleAndFile -text "`r`n" -file $OutPutFile

             #//Check for SnapLagTimes, reports if there is any
            Write-ToConsoleAndFile -text "------------- Snap Lag Times -----------------" -file $OutPutFile
            function Convert-LagTime {
                param (
                    [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
                    [string]$LagTime
                )

                process {
                    if ([string]::IsNullOrEmpty($LagTime)) {
                        "N/A"
                    }
                    else {
                        $timeSpan = [System.Xml.XmlConvert]::ToTimeSpan($LagTime)
                        $formattedTime = '{0}:{1}:{2}' -f $timeSpan.Days, $timeSpan.Hours.ToString('00'), $timeSpan.Minutes.ToString('00')
                        $formattedTime
                    }
                }
            }

            # Output formatting and text explanations for snapmirror
            $SnapMirrors = Get-NcSnapmirror | ForEach-Object {
                $convertedLagTime = $_.LagTime | Convert-LagTime

                $outputLine1 = "$($_.SourceLocation) - $($_.DestinationLocation) - Status: $($_.Status) - MirrorState: $($_.MirrorState) - LagTime(Days:Hours:Min): $convertedLagTime"

                Write-ToConsoleAndFile -text $outputLine1 -file $OutPutFile
            }



            #//Check for broken disks, reports if there is any
            Write-ToConsoleAndFile -text "
            
------------- Broken Disks--------------------" -file $OutPutFile
            $DISK_Status = Get-NcDisk | ?{ $_.DiskRaidInfo.ContainerType -eq "broken" }

            if (!$DISK_Status) {
                Write-ToConsoleAndFile -text "There are no Broken Disks!


***END***END***END***END***END***END***END***END***END***END***END***END***
                " -file $OutPutFile
                }
            else 
                {
                Write-ToConsoleAndFile -text "These Disks are Broken:
                $DISK_Status
  
***END***END***END***END***END***END***END***END***END***END***END***END*** 
                " -file $OutPutFile
    
            }


}
#//Clears all variables before ending script, shuting down powershell should also clear memory
Get-Variable | Where-Object { $_.Name -ne '^' } | Remove-Variable -ErrorAction SilentlyContinue -Force