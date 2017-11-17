[CmdletBinding()]
param()

function Install-Service ($nssmPath, $name, $path) {
    Invoke-VstsTool -FileName $nssmPath -Arguments "install $name $path"
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

# For more information on the VSTS Task SDK:
# https://github.com/Microsoft/vsts-task-lib
Trace-VstsEnteringInvocation $MyInvocation
try {
    # Set the working directory.
    $cwd = Get-VstsInput -Name "cwd" -Require
    Assert-VstsPath -LiteralPath $cwd -PathType Container
    Write-Verbose "Setting working directory to '$cwd'."
    Set-Location $cwd

    # Determine nssm.exe path.
    $nssmPath = Get-VstsInput -Name "nssmpath"
    # If nssm.exe path not specified try to resolve from PATH.
    if(!(Get-Command $nssmPath -ErrorAction SilentlyContinue)){
        Write-Host "nssm.exe path not specified trying to resolve."
        $nssmPath = (Get-Command nssm.exe).Source
    }
    Write-Host "nssm path '$nssmPath'"

    # Install service if not found.
    $serviceName = Get-VstsInput -Name "servicename"
    $appPath = Get-VstsInput -Name "apppath"
    if(!(Get-Service $serviceName -ErrorAction SilentlyContinue)){
        Install-Service $nssmPath $serviceName $appPath
    }

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

} finally {
    Trace-VstsLeavingInvocation $MyInvocation
}
