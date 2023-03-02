# NetApp 
Netapp health check with poshkeepass, i wanted a Powershell script that could check several netapp environments at once, was secure and only required me to type a password once with no passwords inside the script.
If you only have 1 or 2 systems and only want a fast way to check for lagtimes etc i uploaded another part without keepass.

Muc can be improved, working on a version thats easier to configure with more variable and less to edit
#============================================================

#//Prerequisites that need to be installed/done before using the script

#//Update powershell to newest version to begin with to skip potential problems 5.1 newest for ISE and 7.3.2 For non regular shell atm
#//DataOntap module 9.8 or newer required
#//Poshkeepass module script uses 2.53 atm
#//Download and install KeePass + setup of database with secure Masterpassword this will need to be entered when running the script and it tries to fetch the passwords inside the keepass database. 
# - Also remove the rest of the default keepass entries.

#============================================================
#//Setup and notes

#//Example of a valid path "C:\Status\2023\" no asterix '*' should be present anywhere

#Using keepass to login requires setting up a new keypass where all the passwords to the clusters need checking can be stored for the automated login to work. 
# After installing keepass and setup a database (make a securepassword for this keepass also, will need to be entered when running the script) add the passwords in groups or wathever, but would advise to keep it simple.
# I have had them listed in the root part of Keepass and each cluster/cluster password in its own entry.

##Commands

#//To set up a new keepassdatabase use below command. If still having problem, check 'PoshKeePass' module´s "getting started" documents.

#New-KeePassDatabaseConfiguration -DatabaseProfileName '*DATABASENAME*' -DatabasePath '*PATHNAME*\*KEEPASSINSTALLFOLDER*\*DATABASFOLDERNAME*\*DATABASENAME*.kdbx' -KeyPath 'C:\*KEEPASSINSTALLFOLDER*\*DATABASFOLDERNAME*\*DATABASENAME*.keyx' -UseMasterKey -Default

#//To remove a keepassdatabaseconfig that went wrong use below command:

#Remove-KeePassDatabaseConfiguration -DatabaseProfileName '*DATABASENAME*'

#//To check if keepassdatabaseconfig is working properly use below command:

#Get-KeePassEntry -DatabaseProfileName '*DATABASENAME*' -AsPlainText

#//Run to install/reinstall Dataontap module, should be made a comment afterwards again with '#'.

#Install-Module DataONTAP -Force -Verbose

#//Run to install/reinstall Poshkeepass module, should be made a comment afterwards again.

#Install-Module PoShKeePass -Force -Verbose

#Ifproblems arise it could be to the default PowerShell "Get module" test below. If problem still persist look into updating powershell and the "PowerShellGet" module as this is the part that automaticly gets all the other modules.

#Install-Module -Name PowerShellGet -Force -SkipPublisherCheck -AllowClobber
