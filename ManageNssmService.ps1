[CmdletBinding()]
param()

function Install-Service ($nssmPath, $name, $path, [bool]$remoteExec, $remoteSession) {
    if($remoteExec){
        Write-Host "REMOTE INSTALLING NSSM SERVICE WITH $nssmPath"
        Invoke-Command -Session $remoteSession -ArgumentList $nssmPath, $name, $path {
            param($nssmPath, $name, $path)
            Invoke-Expression "$nssmPath install $name $path"
        }
        Write-Host "AFTER REMOTE INSTALLING NSSM SERVICE WITH $nssmPath"
    }else{
        Invoke-VstsTool -FileName $nssmPath -Arguments "install $name $path"
    }
}

function Set-AppProperties ($nssmPath, $name, $path, $startupDir, $appArgs) {
    Invoke-VstsTool -FileName $nssmPath -Arguments "set $name Application $path"

    if($startupDir){
        Invoke-VstsTool -FileName $nssmPath -Arguments "set $name AppDirectory $startupDir"
    }else{
        Invoke-VstsTool -FileName $nssmPath -Arguments "reset $name AppDirectory"
    }

    if($appArgs){
        Invoke-VstsTool -FileName $nssmPath -Arguments "set $name AppParameters $appArgs"
    }else{
        Invoke-VstsTool -FileName $nssmPath -Arguments "reset $name AppParameters"
    }
}

function Set-Details ($nssmPath, $name, $displayName, $description) {
    if($displayName){
        Invoke-VstsTool -FileName $nssmPath -Arguments "set $name DisplayName $displayName"
    }else{
        Invoke-VstsTool -FileName $nssmPath -Arguments "reset $name DisplayName"
    }

    if($description){
        Invoke-VstsTool -FileName $nssmPath -Arguments "set $name Description $description"
    }else{
        Invoke-VstsTool -FileName $nssmPath -Arguments "reset $name Description"
    }
}

function Set-LogOn ($nssmPath, $name, $account, $accountPassword) {
    if($account -and $accountPassword){
        Invoke-VstsTool -FileName $nssmPath -Arguments "set $name ObjectName  $account $accountPassword"
    }else{
        Invoke-VstsTool -FileName $nssmPath -Arguments "reset $name ObjectName"
    }
}

function Set-Logs ($nssmPath, $name, $outFile, $errFile, $rotateFiles, $rotateWhileRunning, $rotateOlderThanInSeconds, $rotateBiggerThanInBytes) {
    # Define stdout and stderr redirect as same file if stderr not specified.
    if($outFile){
        Invoke-VstsTool -FileName $nssmPath -Arguments "set $name AppStdout $outFile"
        if(!$errFile){
            Invoke-VstsTool -FileName $nssmPath -Arguments "set $name AppStderr $outFile"
        }
    }else{
        Invoke-VstsTool -FileName $nssmPath -Arguments "reset $name AppStdout"
    }

    if($errFile){
        Invoke-VstsTool -FileName $nssmPath -Arguments "set $name AppStderr $errFile"
    }else {
        Invoke-VstsTool -FileName $nssmPath -Arguments "reset $name AppStderr"
    }

    if($rotateFiles){
        Invoke-VstsTool -FileName $nssmPath -Arguments "set $name AppRotateFiles  1"

        if($rotateWhileRunning){
            Invoke-VstsTool -FileName $nssmPath -Arguments "set $name AppRotateOnline 1"
        }else{
            Invoke-VstsTool -FileName $nssmPath -Arguments "reset $name AppRotateOnline"
        }
    
        if ($rotateOlderThanInSeconds) {
            Invoke-VstsTool -FileName $nssmPath -Arguments "set $name AppRotateSeconds $rotateOlderThanInSeconds"
        }else{
            Invoke-VstsTool -FileName $nssmPath -Arguments "reset $name AppRotateSeconds"
        }
    
        if ($rotateBiggerThanInBytes) {
            Invoke-VstsTool -FileName $nssmPath -Arguments "set $name AppRotateBytes  $rotateBiggerThanInBytes"
        }else{
            Invoke-VstsTool -FileName $nssmPath -Arguments "reset $name AppRotateBytes"
        }
    }else{
        # Reset all file rotation settings.
        Invoke-VstsTool -FileName $nssmPath -Arguments "reset $name AppRotateFiles"
        Invoke-VstsTool -FileName $nssmPath -Arguments "reset $name AppRotateOnline"
        Invoke-VstsTool -FileName $nssmPath -Arguments "reset $name AppRotateSeconds"
        Invoke-VstsTool -FileName $nssmPath -Arguments "reset $name AppRotateBytes"
    }
}

function Get-PSSessionOptions($ignoreCertificate){
    if($ignoreCertificate){
        $sessionOptions = (New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck)
    }else{
        $sessionOptions = (New-PSSessionOption)
    }
    return $sessionOptions
}

# For more information on the VSTS Task SDK:
# https://github.com/Microsoft/vsts-task-lib
Trace-VstsEnteringInvocation $MyInvocation
try {
    # Set the working directory.
    $cwd = Get-VstsInput -Name "cwd" -Require
    Assert-VstsPath -LiteralPath $cwd -PathType Container
    Write-Verbose "Setting working directory to '$cwd'."
    Set-Location $cwd

    # Check if is a remote execution.
    $remoteExec = Get-VstsInput -Name "remote" -AsBool
    if($remoteExec){
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
    }

    # Determine nssm.exe path.
    $nssmPath = Get-VstsInput -Name "nssmpath"
    # If nssm.exe path not specified try to resolve from PATH.
    if($remoteExec){
        if($nssmPath){
            $nssmPath = Invoke-Command -Session $remoteSession { 
                (Get-Command nssm.exe).Source
            }
        }
    }else{
        if(!(Get-Command $nssmPath -ErrorAction SilentlyContinue)){
            Write-Host "nssm.exe path not specified trying to resolve."
            $nssmPath = (Get-Command nssm.exe).Source
        }
    }

    Write-Host "nssm path '$nssmPath'"

    # Get service desired state.
    $serviceName = Get-VstsInput -Name "servicename"
    $serviceState = Get-VstsInput -Name "serviceState" -Require
    # If is a service removal abort settings update.
    if($serviceState -eq "absent"){
        if($remoteExec){
            Invoke-Command -Session $remoteSession {
                Invoke-Expression "$nssmPath stop $serviceName"
                Invoke-Expression "$nssmPath remove $serviceName confirm"
            }
        }else{
            Invoke-VstsTool -FileName $nssmPath -Arguments "stop $serviceName"
            Invoke-VstsTool -FileName $nssmPath -Arguments "remove $serviceName confirm"
        }
        return
    }

    # Install service if not found.
    $appPath = Get-VstsInput -Name "apppath" -Require
    $installService = $false
    if($remoteExec){
        $installService = Invoke-Command -Session $remoteSession { !(Get-Service $serviceName -ErrorAction SilentlyContinue)}
    }else{
        if(!(Get-Service $serviceName -ErrorAction SilentlyContinue)){
            $installService = $true
        }
    }

    #if($installService){
        Write-Host "MUST INSTALL SERVICE"
        Install-Service $nssmPath $serviceName $appPath $remoteExec $remoteSession
    #}

    # Set basic service props.
    $startupDir = Get-VstsInput -Name "startupdir"
    $appArgs = Get-VstsInput -Name "appargs"
    Set-AppProperties $nssmPath $serviceName $appPath $startupDir $appArgs

    # Set service details.
    $displayName = Get-VstsInput -Name "displayname"
    $description = Get-VstsInput -Name "description"
    Set-Details $nssmPath $serviceName $displayName $description

    # Set LogOn info.
    $serviceAccount = Get-VstsInput -Name "serviceaccount"
    $serviceAccountPass = Get-VstsInput -Name "serviceaccountpass"
    Set-LogOn $nssmPath $serviceName $serviceAccount $serviceAccountPass

    # Set I/O redirection and file rotation
    $outFile = Get-VstsInput -Name "outfile"
    $errFile = Get-VstsInput -Name "errfile"
    $rotate = Get-VstsInput -Name "rotate" -AsBool
    $rotateRunning = Get-VstsInput -Name "rotaterunning" -AsBool
    $rotatePerSeconds = Get-VstsInput -Name "rotateperseconds" -AsInt
    $rotatePerBytes = Get-VstsInput -Name "rotateperbytes" -AsInt
    Set-Logs $nssmPath $serviceName $outFile $errFile $rotate $rotateRunning $rotatePerSeconds $rotatePerBytes

    # Apply service desired state.
    switch ($serviceState) {
        "started" {
            if((get-service ExampleService).Status -ne "Running"){
                Invoke-VstsTool -FileName $nssmPath -Arguments "start $serviceName "
            }
        }
        "restarted" {
            Invoke-VstsTool -FileName $nssmPath -Arguments "restart $serviceName"
        }
        "stopped"{
            Invoke-VstsTool -FileName $nssmPath -Arguments "stop $serviceName"
        }
        Default {
            # Should not execute this. if happen some validation is missing.
            Write-VstsTaskWarning "No service state specified."
        }
    }
} finally {
    Trace-VstsLeavingInvocation $MyInvocation
}
