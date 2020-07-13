[CmdletBinding()]
param([switch]$dotSourceOnly)

function Get-PSSessionOptions($ignoreCertificate){
    if($ignoreCertificate){
        $sessionOptions = (New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck)
    }else{
        $sessionOptions = (New-PSSessionOption)
    }

    return $sessionOptions
}

function Get-PSSession () {
    $machine = Get-VstsInput -Name "Machine" -Require
    $remoteUser = Get-VstsInput -Name "AdminUserName" -Require
    $remoteUserPass = Get-VstsInput -Name "AdminPassword" -Require
    $remoteProtocol = Get-VstsInput -Name "Protocol" -Require
    $useSSL = ($remoteProtocol -eq "Https")
    $ignoreCertificate = Get-VstsInput -Name "TestCertificate" -Require -AsBool
    # Open remote session.
    $secpasswd = ConvertTo-SecureString $remoteUserPass -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential ($remoteUser, $secpasswd)
    $remoteSession = New-PSSession -ComputerName $machine -Credential $credential -UseSSL:$useSSL -SessionOption (Get-PSSessionOptions $ignoreCertificate)

    return $remoteSession
}

function Invoke-RemoteTool ($fileName, $arguments, $remoteSession) {
    Write-Host "##[command]`"$fileName`" $arguments"
    Invoke-Command -Session $remoteSession -ArgumentList $fileName, $arguments {
        param($fileName, $arguments)
        Invoke-Expression "$fileName $arguments"
    } -ErrorAction Ignore
}

function Invoke-Tool ($fileName, $arguments, $remoteSession) {
    if($remoteSession){
        Invoke-RemoteTool -FileName $fileName -Arguments $arguments -RemoteSession $remoteSession
    }else{
        Invoke-VstsTool -FileName $fileName -Arguments $arguments
    }
}

function Set-NssmAppProperties ($nssmPath, $name, $path, $startupDir, $appArgs, $remoteSession) {
    Invoke-Tool -FileName $nssmPath -Arguments "set $name Application $path" -RemoteSession $remoteSession
    
    if($startupDir){
        Invoke-Tool -FileName $nssmPath -Arguments "set $name AppDirectory $startupDir" -RemoteSession $remoteSession
    }else{
        Invoke-Tool -FileName $nssmPath -Arguments "reset $name AppDirectory" -RemoteSession $remoteSession
    }
    
    if($appArgs){
        Invoke-Tool -FileName $nssmPath -Arguments "set $name AppParameters $appArgs" -RemoteSession $remoteSession
    }else{
        Invoke-Tool -FileName $nssmPath -Arguments "reset $name AppParameters" -RemoteSession $remoteSession
    }
}

function Set-NssmDetails ($nssmPath, $name, $displayName, $description, $remoteSession) {
    if($displayName){
        Invoke-Tool -FileName $nssmPath -Arguments "set $name DisplayName $displayName" -RemoteSession $remoteSession
    }else{
        Invoke-Tool -FileName $nssmPath -Arguments "reset $name DisplayName" -RemoteSession $remoteSession
    }
    
    if($description){
        Invoke-Tool -FileName $nssmPath -Arguments "set $name Description $description" -RemoteSession $remoteSession
    }else{
        Invoke-Tool -FileName $nssmPath -Arguments "reset $name Description" -RemoteSession $remoteSession
    }
}

function Set-NssmLogOn ($nssmPath, $name, $account, $accountPassword, $remoteSession) {
    if($account -and $accountPassword){
        Invoke-Tool -FileName $nssmPath -Arguments "set $name ObjectName  $account $accountPassword" -RemoteSession $remoteSession
    }else{
        Invoke-Tool -FileName $nssmPath -Arguments "reset $name ObjectName" -RemoteSession $remoteSession
    }
}

function Set-NssmLogs ($nssmPath, $name, $outFile, $errFile, $rotateFiles, $rotateWhileRunning, $rotateOlderThanInSeconds, $rotateBiggerThanInBytes, $remoteSession) {
    # Define stdout and stderr redirect as same file if stderr not specified.
    if($outFile){
        Invoke-Tool -FileName $nssmPath -Arguments "set $name AppStdout $outFile" -RemoteSession $remoteSession
        if(!$errFile){
            Invoke-Tool -FileName $nssmPath -Arguments "set $name AppStderr $outFile" -RemoteSession $remoteSession
        }
    }else{
        Invoke-Tool -FileName $nssmPath -Arguments "reset $name AppStdout" -RemoteSession $remoteSession
    }
    
    if($errFile){
        Invoke-Tool -FileName $nssmPath -Arguments "set $name AppStderr $errFile" -RemoteSession $remoteSession
    }else {
        Invoke-Tool -FileName $nssmPath -Arguments "reset $name AppStderr" -RemoteSession $remoteSession
    }
    
    if($rotateFiles){
        Invoke-Tool -FileName $nssmPath -Arguments "set $name AppRotateFiles  1" -RemoteSession $remoteSession
        
        if($rotateWhileRunning){
            Invoke-Tool -FileName $nssmPath -Arguments "set $name AppRotateOnline 1" -RemoteSession $remoteSession
        }else{
            Invoke-Tool -FileName $nssmPath -Arguments "reset $name AppRotateOnline" -RemoteSession $remoteSession
        }
        
        if ($rotateOlderThanInSeconds) {
            Invoke-Tool -FileName $nssmPath -Arguments "set $name AppRotateSeconds $rotateOlderThanInSeconds" -RemoteSession $remoteSession
        }else{
            Invoke-Tool -FileName $nssmPath -Arguments "reset $name AppRotateSeconds" -RemoteSession $remoteSession
        }
        
        if ($rotateBiggerThanInBytes) {
            Invoke-Tool -FileName $nssmPath -Arguments "set $name AppRotateBytes  $rotateBiggerThanInBytes" -RemoteSession $remoteSession
        }else{
            Invoke-Tool -FileName $nssmPath -Arguments "reset $name AppRotateBytes" -RemoteSession $remoteSession
        }
    }else{
        # Reset all file rotation settings.
        Invoke-Tool -FileName $nssmPath -Arguments "reset $name AppRotateFiles" -RemoteSession $remoteSession
        Invoke-Tool -FileName $nssmPath -Arguments "reset $name AppRotateOnline" -RemoteSession $remoteSession
        Invoke-Tool -FileName $nssmPath -Arguments "reset $name AppRotateSeconds" -RemoteSession $remoteSession
        Invoke-Tool -FileName $nssmPath -Arguments "reset $name AppRotateBytes" -RemoteSession $remoteSession
    }
}

function Resolve-NssmPath ($nssmPath, $remoteSession) {
    $scriptBlock = {
        param($nssmPath)
        # If path not specified or valid try to resolve from PATH.
        if(!(Get-Command $nssmPath -ErrorAction SilentlyContinue)){
            Write-Host "nssm.exe path invalid or not specified trying to resolve."
            (Get-Command nssm.exe).Source
        }else{
            $nssmPath
        }
    }

    # Run path resolution remotely or local.
    if($remoteSession){
        $validPath = Invoke-Command -Session $remoteSession -ArgumentList $nssmPath -ScriptBlock $scriptBlock
    }else{
        $validPath = &$scriptBlock $nssmPath
    }
    
    return $validPath
}

function Install-NssmService ($nssmPath, $name, $path, $remoteSession) {
    Invoke-Tool -FileName $nssmPath -Arguments "install $name $path" -RemoteSession $remoteSession
}

function Remove-NssmService ($nssmPath, $serviceName, $remoteSession) {
    #TODO: check if service exists to avoid nssm error msg in VSTS console.
    #TODO: check if service stopped to avoid abort or ignore stop error.
    Invoke-Tool -FileName $nssmPath -Arguments "stop $serviceName" -RemoteSession $remoteSession
    Invoke-Tool -FileName $nssmPath -Arguments "remove $serviceName confirm" -RemoteSession $remoteSession
}

function Get-NssmService($serviceName, $remoteSession){
    $scriptBlock = {
        param($serviceName)
        !(Get-Service $serviceName -ErrorAction SilentlyContinue)
    }

    if ($remoteSession) {
        Invoke-Command -Session $remoteSession -ArgumentList $serviceName -ScriptBlock $scriptBlock
    }else {
        &$scriptBlock $serviceName
    }
}

function Set-NssmExitActions ($nssmPath, $serviceName, $recoverAction, $remoteSession, $appRestartDelay) {
    Invoke-Tool -FileName $nssmPath -Arguments "set $serviceName AppExit Default $recoverAction" -RemoteSession $remoteSession

    if($appRestartDelay){
        Invoke-Tool -FileName $nssmPath -Arguments "set $serviceName AppRestartDelay $appRestartDelay" -RemoteSession $remoteSession
    }
}

function Set-NssmService ($nssmPath, $serviceName, $serviceState, $remoteSession) {

    # Install service if not found.
    $appPath = Get-VstsInput -Name "apppath" -Require
    $installService = Get-NssmService $serviceName $remoteSession

    if($installService){
        Write-Host "Service not already installed. Installing service."
        Install-NssmService $nssmPath $serviceName $appPath $remoteSession
    }

    # Set basic service props.
    $startupDir = Get-VstsInput -Name "startupdir"
    $appArgs = Get-VstsInput -Name "appargs"
    Set-NssmAppProperties $nssmPath $serviceName $appPath $startupDir $appArgs $remoteSession

    # Set service details.
    $displayName = Get-VstsInput -Name "displayname"
    $description = Get-VstsInput -Name "description"
    Set-NssmDetails $nssmPath $serviceName $displayName $description $remoteSession

    # Set LogOn info.
    $serviceAccount = Get-VstsInput -Name "serviceaccount"
    $serviceAccountPass = Get-VstsInput -Name "serviceaccountpass"
    Set-NssmLogOn $nssmPath $serviceName $serviceAccount $serviceAccountPass $remoteSession

    # Set I/O redirection and file rotation
    $outFile = Get-VstsInput -Name "outfile"
    $errFile = Get-VstsInput -Name "errfile"
    $rotate = Get-VstsInput -Name "rotate" -AsBool
    $rotateRunning = Get-VstsInput -Name "rotaterunning" -AsBool
    $rotatePerSeconds = Get-VstsInput -Name "rotateperseconds" -AsInt
    $rotatePerBytes = Get-VstsInput -Name "rotateperbytes" -AsInt
    Set-NssmLogs $nssmPath $serviceName $outFile $errFile $rotate $rotateRunning $rotatePerSeconds $rotatePerBytes $remoteSession

    $recoverAction = Get-VstsInput -Name "recovertaction"
    if($recoverAction -eq "Restart"){
        $appRestartDelay = Get-VstsInput -Name "restartdelay"
    }
    Set-NssmExitActions $nssmPath $serviceName $recoverAction $remoteSession $appRestartDelay

    # Apply service desired state.
    switch ($serviceState) {
        "started" {
            if((get-service $serviceName -ErrorAction Ignore).Status -ne "Running"){
                Invoke-Tool -FileName $nssmPath -Arguments "start $serviceName" -RemoteSession $remoteSession
            }
        }
        "restarted" {
            Invoke-Tool -FileName $nssmPath -Arguments "restart $serviceName" -RemoteSession $remoteSession
        }
        "stopped" {
            If((Get-Service $serviceName -ErrorAction Ignore).Status -ne "Stopped") {
                Invoke-Tool -FileName $nssmPath -Arguments "stop $serviceName" -RemoteSession $remoteSession
            }
        }
        Default {
            # Should not execute this. if happen some validation is missing.
            Write-VstsTaskWarning "No service state specified."
        }
    }
}
function Main () {
    # For more information on the VSTS Task SDK:
    # https://github.com/Microsoft/vsts-task-lib
    Trace-VstsEnteringInvocation $MyInvocation
    try {

        # Open pssession if is remote execution.
        $remoteExec = Get-VstsInput -Name "remote" -AsBool
        if($remoteExec){
            Write-Host "Remote execution via WinRM selected."
            $remoteSession = Get-PSSession
        }else{
            # Set local working directory.
            $cwd = Get-VstsInput -Name "cwd" -Require
            Assert-VstsPath -LiteralPath $cwd -PathType Container
            Write-Verbose "Setting working directory to '$cwd'."
            Set-Location $cwd
        }
        
        # Determine nssm.exe path.
        $nssmPath = Get-VstsInput -Name "nssmpath"
        $nssmPath = Resolve-NssmPath $nssmPath $remoteSession
        Write-Host "nssm path '$nssmPath'"
        
        # Get service desired state.
        $serviceName = Get-VstsInput -Name "servicename"
        $serviceState = Get-VstsInput -Name "serviceState" -Require
        
        # Remove or install/update service.
        if($serviceState -eq "absent"){
            Remove-NssmService $nssmPath $serviceName $remoteSession
        }else{
            Set-NssmService $nssmPath $serviceName $serviceState $remoteSession
        }
        
    } finally {
        Trace-VstsLeavingInvocation $MyInvocation
    }
}

if($dotSourceOnly -eq $false){
    Main
}
