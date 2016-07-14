param(
  [String]$h="localhost:2375",
  [String]$f="TestGitClone",
  [String]$sqlImageName = "mssql-2014"
)
Set-ExecutionPolicy -ExecutionPolicy Bypass
#
# This Powershell script 
#   - creates and starts a SQL Server  container, 
#   - retrieves the port and sa password of the SQL container 
#   - starts the SQL Server container
#   - Updates a local copy of the web.cfg file 
#   - Builds the .NET app with updated connection string
#   - Presents the integrated environment
#

# $binDir = Get-Location
$SystemDrive = [system.environment]::getenvironmentvariable("SystemDrive")
$binDir = $SystemDrive + "\windocks\bin"

#-------
# Introduction to Automation
#--

#-------
# Create MSSQL Container and verify success
#--

$ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
$ProcessInfo.FileName = "$binDir\docker.exe"
$ProcessInfo.RedirectStandardError = $true
$ProcessInfo.RedirectStandardOutput = $true
$ProcessInfo.UseShellExecute = $false
$ProcessInfo.Arguments = "-H=tcp://$h create $sqlImageName"

$Process = New-Object System.Diagnostics.Process
$Process.StartInfo = $ProcessInfo

Write-Host "`r`n`r`nCreating container from image $sqlImageName..."

$Process.Start() | Out-Null
$Process.WaitForExit()

$output = $Process.StandardOutput.ReadToEnd()

if ($output.Contains("ContainerPort")) {
    Write-Host "Success! $sqlImageName container creation return string:"
    Write-Host "- - - - - - - - - - - - - - - - - - - - - - - - - - -"
    Write-Host $output
}
else {
    Write-Host "Creating $sqlImageName container failed..."
    Write-Host "- - - - docker return message - - - - -"
    Write-Host $output
    exit
}



#-------
# Isolate and sanitize necessary container details
#--

$returnValues = $output.Split("&") 

# Gets " ContainerPort = ***** "
# Sanitizes $portString to just "*****"
$portString = $returnValues | where { $_ -match "ContainerPort" }
$dbPort = $portString.Split("=")[1].Trim()

# repeat for dbPass
$passString = $returnValues | where { $_ -match "MSSQLServerSaPassword" }
$dbPass = $passString.Split("=")[1].Trim()

# repeat for containerId
$idString = $returnValues | where { $_ -match "ContainerId" }
$sqlContainerId = $idString.Split("=")[1].Trim()



#-------
# start created MSSQL container (reusing $processInfo with new args)
#--

$ProcessInfo.Arguments = "-H=tcp://$h start $sqlContainerId"
$Process.StartInfo = $ProcessInfo

Write-Host "Starting $sqlImageName container..."

$Process.Start() | Out-Null
$Process.WaitForExit()

$output = $Process.StandardOutput.ReadToEnd()
if ($output.Contains($sqlContainerId)) {
    Write-Host "Success! $sqlImageName container start return string:"
    Write-Host "- - - - - - - - - - - - - - - - - - - - - - - - - - -"
    Write-Host $output
} else {
    Write-Host "Starting $sqlImageName container failed..."
    Write-Host "- - - - docker return message - - - - -"
    Write-Host $output
    exit
}



#-------
# Configuring web.config in 'TestGitClone' directory
#--

Write-Host "Updating web.config in $f directory with $sqlImageName credentials ...`r`n"

# parse web.config
$webConfigFile = "$binDir\$f\web.config"
$webConfig = [xml](Get-Content $webConfigFile)

# get connection IP
$serverAddress = $h.Split(":")[0];
if ($serverAddress -eq "localhost") { $serverAddress = "127.0.0.1" }

# get and rebuild connection string
$root = $webConfig.get_DocumentElement()
$connString = $root.connectionStrings.add.connectionString
$connString = [Regex]::replace($connString, "Server=[^;]*", "Server=$serverAddress,$dbPort")
$connString = [Regex]::replace($connString, "Password=[^;]*", "Password=$dbPass")
$root.connectionStrings.add.connectionString = $connString

$webConfig.Save($webConfigFile)



#-------
# Issue docker build against specified folder/dockerfile (again, reusing process w/ updated arguments)
#--

$ProcessInfo.Arguments = "-H=tcp://$h build $binDir\$f"
$Process.StartInfo = $ProcessInfo

Write-Host "Building dotnet-4.5 container from $f"
$Process.Start() | Out-Null
$Process.WaitForExit()

$output = $Process.StandardOutput.ReadToEnd()

if ($output.Contains("ContainerPort")) {
    Write-Host "Success! docker build $f return string:"
    Write-Host "- - - - - - - - - - - - - - - - - - - -"
    Write-Host $output
} else {
    Write-Host "Building $f container failed..."
    Write-Host "- - - docker return string - - -"
    Write-Host $output
    exit
}



#-------
# Isolate and sanitize desired container details
#--

$returnValues = $output.Split("&") 

# Gets " ContainerPort = ***** "
# Sanitizes $portString to just "*****"
$portString = $returnValues | where { $_ -match "ContainerPort" }
$netPort = $portString.Split("=")[1].Trim()

# repeat for containerId
$idString = $returnValues | where { $_ -match "ContainerId" }
$netContainerId = $idString.Split("=")[1].Trim()



#-------
# Start the linked dotnet container (again, reusing $Process, modified args)
#--

$ProcessInfo.Arguments = "-H=tcp://$h start $netContainerId"
$Process.StartInfo = $ProcessInfo

Write-Host "Starting the linked $f container..."

$Process.Start() | Out-Null
$Process.WaitForExit();

$output = $Process.StandardOutput.ReadToEnd();
if ($output.Contains($netContainerId)) {
    Write-Host "Success! $f container start return string:"
    Write-Host "- - - - - - - - - - - - - - - - - - - - - - - - - - -"
    Write-Host $output
} else {
    Write-Host "Starting $f container failed..."
    Write-Host "- - - - docker return message - - - - -"
    Write-Host $output
    exit
}



Write-Host "Script execution successful...`r`n"
Write-Host "Application URI: http://$serverAddress`:$netPort/`r`n"
Write-Host "MSSQL Port:      $dbPort"
Write-Host "MSSQL Pass:      $dbPass`r`n"
Write-Host ".NET Port:       $netPort`r`n"
