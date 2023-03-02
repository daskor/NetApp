#//The Import module can be left as is so they are properly loaded in if the server/computer/powershell is restarted where the script is located
Import-Module DataONTAP -Force
Import-Module PoShKeePass -Force

#//Script-SETUP 

#script that creates a text document with todays date at desired path, fill in where you want it to save.
$OutPutFile = "*PATHNAME*\Status\2023\$(get-date -f yyyy-MM-dd)_log.txt" # Set path to whatever you want
$i = 1
$i = 1
while (Test-Path $OutPutFile) {
    $OutPutFile = "*PATHNAME*\Status\2023\$(get-date -f yyyy-MM-dd)_log$i.txt" # path need to be same as above
    $i++
}

function Write-ToConsoleAndFile {
    param(
        $text,
        $file,
        $color = "white"
    )
    Write-Host $text -ForegroundColor $color
    $text | Out-File $file -Append -Force
}


#//Create a file with the IP or FQDN of Netapp Clusters - one per line
#Add cluster (FQDN prefered,better output) that you want the script to check, make sure to add them in an array, with one line for each cluster name/ip.
$Cluster_List = Get-Content "C:\clusterlist.txt" # Set path to whatever you want


#//Store the Keepass entries into a variable
$kpentries = Get-KeePassEntry -KeePassEntryGroupPath '*THEKEEPASSDATABASENAME*' -DatabaseProfileName *DATABASEPROFILENAME* #Name need to match the poshkeepass module configuration name

#//Define the entry titles from keepass for which you want to retrieve the passwords, recommend naming them the same in keepass as their real FQDN name for simlplicity sake.
$entryTitles = @("Cluster1-01", "Cluster1-02", "Cluster2-01", "Cluster2-02", "Cluster3-01", "Cluster3-02") #Change these so they match the name inside your keepass

#//Empty array to hold the passwords
$passwords = @()

#//Loop through each entry title and retrieve the password from $kpentries
foreach ($entryTitle in $entryTitles) {
    $entry = $kpentries | Where-Object { $_.Title -eq $entryTitle }
    $password = $entry | Select-Object -ExpandProperty Password
    $passwords += $password
}

#//Create credentials for each password variable, if more entries/clusterpasswords exist in keepass just add on more rows. Added som examples below 6,7
$username = "admin" #NetappUserName
$Credential1 = New-Object System.Management.Automation.PSCredential -ArgumentList $username, $passwords[0]
$Credential2 = New-Object System.Management.Automation.PSCredential -ArgumentList $username, $passwords[1]
$Credential3 = New-Object System.Management.Automation.PSCredential -ArgumentList $username, $passwords[2]
$Credential4 = New-Object System.Management.Automation.PSCredential -ArgumentList $username, $passwords[3]
$Credential5 = New-Object System.Management.Automation.PSCredential -ArgumentList $username, $passwords[4]
$Credential6 = New-Object System.Management.Automation.PSCredential -ArgumentList $username, $passwords[5]
#$Credential7 = New-Object System.Management.Automation.PSCredential -ArgumentList $username, $passwords[6]
#$Credential8 = New-Object System.Management.Automation.PSCredential -ArgumentList $username, $passwords[7]


Set-ExecutionPolicy Unrestricted -force | Out-Null

#//Will run below script on each cluster in the Cluster_list until all is run, if more clusters exist that need to be checked just add on more rows. Added som examples below 7,8
ForEach ($Cluster in $Cluster_List) {

    $credObject = $null

    If ($Cluster -imatch "Cluster1-01") {
        $credObject = $Credential1
    }
    elseif ($Cluster -imatch "Cluster1-02") {
        $credObject = $Credential2
    }
    elseif ($Cluster -imatch "Cluster2-01") {
        $credObject = $Credential3
    }
    elseif ($Cluster -imatch "Cluster2-02") {
        $credObject = $Credential4
    }
    elseif ($Cluster -imatch "Cluster3-01") {
        $credObject = $Credential5
    }
    elseif ($Cluster -imatch "Cluster3-02") {
        $credObject = $Credential6
    }
    <#elseif ($Cluster -imatch "Cluster4-01") {
    $credObject = $Credential7
    }#>
    <#elseif ($Cluster -imatch "Cluster4-02") {
    $credObject = $Credential8
    }#>

    #//Check if we have a valid credential object
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

            #Main ONTAP script#

            #//currentlyconnected node
            #$Nodename = Get-NcNode | Select-Object -ExpandProperty Node | Sort-Object -Property controller
            # Print the name of the current node
            #Write-ToConsoleAndFile -text "Connecting to $Nodename" -file $OutPutFile

            #//Get todays date and version of ONTAP
            $Date = Get-Date -format yyyy.MM.dd.hh.mm
            Write-ToConsoleAndFile -text "TimeStamp:",$Date -file $OutPutFile

            #//Check nodenames and health etc
            Write-ToConsoleAndFile -text "------------- Ontap System Check -------------" -file $OutPutFile
            $Nodes = Get-NcNode | select Node, IsNodeHealthy, NodeLocation, NodeUptimeTS, ProductVersion, NvramBatteryStatus, EnvFailedFanMessage, EnvFailedPowerSupplyMessage | sort Node
            Write-ToConsoleAndFile -text $Nodes -file $OutPutFile

            #//Check Aggregates overall storage
            Write-ToConsoleAndFile -text "------------- Aggregate information ----------" -file $OutPutFile
            $Aggregates = Get-NcAggr
            Write-ToConsoleAndFile -text $Aggregates -file $OutPutFile

            #//Checking LIF Status
            $LIF_Status =  Get-NcNetInterface -Name * | Where-Object -Property IsHome -EQ $False | Sort-Object -Property InterfaceName | Format-Table -Property InterfaceName, IsHome, CurrentNode 

            if (!$LIF_Status) {
                 Write-ToConsoleAndFile -text "ALL Lifs are currently home!" -file $OutPutFile
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
                Write-ToConsoleAndFile -text "All volumes have sufficient free space!
    
  
                " -file $OutPutFile
                }
            else 
                {
	            Write-ToConsoleAndFile -text "The following NetApp volumes are starting to get full, extend volumes!" -file $OutPutFile
 	            Write-ToConsoleAndFile -text $vol_low_space -file $OutPutFile

            }


            #//Checking for files/inodes above 79%, at 80% Ontap starts to give warnings about this
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

            $LagTimeseconds = "86400"
            $SnapMirrors =  Get-NcSnapmirror | where-object {$_.LagTime -gt $lagTimeSeconds} | Select SourceLocation,DestinationLocation,@{Expression={[timespan]::fromseconds($_.'lagtime')};Label="LagTime(Days:Hours:Min:sec)"}
           
           if (!$SnapMirrors) {

                           Write-ToConsoleAndFile -text "No SnapMirror LagTimes to show!" -file $OutPutFile
                           Write-ToConsoleAndFile -text "`r`n" -file $OutPutFile
                }
            else 
                {
            Write-ToConsoleAndFile -text $SnapMirrors -file $OutPutFile
            Write-ToConsoleAndFile -text "`r`n" -file $OutPutFile
            }

            #//Check for Snapmirrors that are unhealty
            Write-ToConsoleAndFile -text "------------- SnapMirror Health -----------------" -file $OutPutFile
            $SnapMirrorHealth = Get-NcSnapmirror | Where-Object { $_.IsHealthy -eq $false }
            if ($SnapMirrorHealth) {
                Write-ToConsoleAndFile -text $SnapMirrorHealth -file $OutPutFile
            } else {
                Write-ToConsoleAndFile -text "SnapMirrors are healthy!" -file $OutPutFile
                Write-ToConsoleAndFile -text "`r`n" -file $OutPutFile
            }

            #//Check for broken disks, reports if there is any
            Write-ToConsoleAndFile -text "------------- Broken Disks--------------------" -file $OutPutFile
            $DISK_Status = Get-NcDisk | ?{ $_.DiskRaidInfo.ContainerType -eq "broken" }

            if (!$DISK_Status) {
                Write-ToConsoleAndFile -text "There are no Broken Disks


***END***END***END***END***END***END***END***END***END***END***END***END***
                " -file $OutPutFile
                }
            else 
                {
                Write-ToConsoleAndFile -text "These Disks are Broken:
 
  
***END***END***END***END***END***END***END***END***END***END***END***END*** 
                " -file $OutPutFile
    
                $DISK_Status
            }


}
#//Clears all variables before ending script, shuting down powershell also clear memory
Get-Variable | Where-Object { $_.Name -ne '^' } | Remove-Variable -ErrorAction SilentlyContinue -Force
