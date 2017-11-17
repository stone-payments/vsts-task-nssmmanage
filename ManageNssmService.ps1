[CmdletBinding()]
param()

function Install-Service ($nssmPath, $name, $path) {
    Invoke-VstsTool -FileName $nssmPath -Arguments "install $name $path"
}

# For more information on the VSTS Task SDK:
# https://github.com/Microsoft/vsts-task-lib
Trace-VstsEnteringInvocation $MyInvocation
try {
    # Set the working directory.
    $cwd = Get-VstsInput -Name cwd -Require
    Assert-VstsPath -LiteralPath $cwd -PathType Container
    Write-Verbose "Setting working directory to '$cwd'."
    Set-Location $cwd

    $nssmPath = Get-VstsInput -Name nssmpath
    # If nssm.exe path not specified try to resolve from PATH.
    if(!(Get-Command $nssmPath -ErrorAction SilentlyContinue)){
        Write-Host "nssm.exe path not specified trying to resolve."
        $nssmPath = (Get-Command nssm.exe).Source
    }
    Write-Host "nssm path '$nssmPath'"

    $serviceName = Get-VstsInput -Name servicename
    $appPath = Get-VstsInput -Name apppath

    Install-Service $nssmPath $serviceName $appPath

} finally {
    Trace-VstsLeavingInvocation $MyInvocation
}
