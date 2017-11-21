# Found and import source script.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
$srcDir = "$here\.."
. "$srcDir\$sut" -dotSourceOnly
# Import vsts sdk.
$vstsSdkPath = Join-Path $PSScriptRoot ..\ps_modules\VstsTaskSdk\VstsTaskSdk.psm1 -Resolve
Import-Module -Name $vstsSdkPath

# Set vsts sdk aliases.
Set-Alias -Name Trace-VstsEnteringInvocation -Value Trace-EnteringInvocation
Set-Alias -Name Trace-VstsLeavingInvocation -Value Trace-LeavingInvocation
Set-Alias -Name Get-VstsInput -Value Get-Input
Set-Alias -Name Assert-VstsPath -Value Assert-Path

Describe 'Main' {
    Mock Trace-VstsEnteringInvocation -MockWith {}
    Mock Trace-VstsLeavingInvocation -MockWith {}
    Mock Get-VstsInput {}

    It 'Open remote session and warn about it' {
        # Mocks to avoid throw errors.
        Mock Resolve-NssmPath {}
        Mock Remove-NssmService {}
        Mock Get-VstsInput {
            return "absent"
        } -ParameterFilter { $Name -eq "serviceState" }
        # Mock to ensure is remote execution
        Mock Get-VstsInput {
            return $true
        } -ParameterFilter { $Name -eq "remote" }
        # Mock used to assert after act.
        Mock Write-Host {}
        Mock Get-PSSession {}

        # Act
        Main

        # Assert 
        Assert-MockCalled -CommandName Get-VstsInput -Times 1 -Exactly -ParameterFilter { $Name -eq "remote" } -Scope It
        Assert-MockCalled -CommandName Write-Host -Times 1 -Exactly -ParameterFilter { $Object -eq "Remote execution via WinRM selected." } -Scope It
        Assert-MockCalled -CommandName Get-PSSession -Times 1 -Exactly -Scope It
    }

    It 'Set working dir when local execution' {
        # Mocks to avoid throw errors.
        Mock Resolve-NssmPath {}
        Mock Remove-NssmService {}
        Mock Get-VstsInput {
            return "absent"
        } -ParameterFilter { $Name -eq "serviceState" }
        Mock Get-PSSession {}
        # Mock to ensure is local execution
        Mock Get-VstsInput {
            return $false
        } -ParameterFilter { $Name -eq "remote" }
        # Mock used to assert after act.
        $expectedWorkingDir = $env:TEMP
        Mock Get-VstsInput {
            return $expectedWorkingDir
        } -ParameterFilter { $Name -eq "cwd" }
        Mock Set-Location {}
        Mock Assert-VstsPath {}

        # Act
        Main

        # Assert path change to expected working dir.
        Assert-MockCalled -CommandName Get-VstsInput -Times 1 -Exactly -ParameterFilter { $Name -eq "cwd" } -Scope It
        Assert-MockCalled -CommandName Assert-VstsPath -Times 1 -Exactly -ParameterFilter { $LiteralPath -eq $expectedWorkingDir } -Scope It
        Assert-MockCalled -CommandName Set-Location -Times 1 -Exactly -ParameterFilter { $Path -eq $expectedWorkingDir } -Scope It
    }

    It 'Should discover nssm path' {
        # Mocks to avoid throw errors.
        Mock Remove-NssmService {}
        Mock Get-VstsInput {
            return "absent"
        } -ParameterFilter { $Name -eq "serviceState" }
        Mock Get-PSSession {}
        Mock Set-Location {}
        Mock Get-VstsInput {
            return $false
        } -ParameterFilter { $Name -eq "remote" }
        Mock Get-VstsInput {
            return "somepath"
        } -ParameterFilter { $Name -eq "cwd" }
        # Mock used to assert after act.
        $expectedNssmPath = "C:\tools\nssm.exe"
        Mock Resolve-NssmPath {
            return $expectedNssmPath
        }
        Mock Write-Host {}

        # Act
        Main

        # Assert printed nssm path is equal the expected.
        Assert-MockCalled -CommandName Get-VstsInput -Times 1 -Exactly  -ParameterFilter { $Name -eq "nssmpath" } -Scope It
        Assert-MockCalled -CommandName Resolve-NssmPath -Times 1 -Scope It
        Assert-MockCalled -CommandName Write-Host -Times 1 -Exactly -ParameterFilter { $Object -eq "nssm path '$expectedNssmPath'" } -Scope It
    }

    It "Should remove service for absent state" {
        # Mocks to avoid throw errors.
        Mock Set-Location {}
        Mock Get-VstsInput {
            return $false
        } -ParameterFilter { $Name -eq "remote" }
        Mock Get-VstsInput {
            return "somepath"
        } -ParameterFilter { $Name -eq "cwd" }
        # Mocks used to control flow.
        Mock Get-VstsInput {
            return "absent"
        } -ParameterFilter { $Name -eq "serviceState" }
        # Mock used to assert after act.
        Mock Remove-NssmService {}
        Mock Set-NssmService {}

        # Act
        Main

        # Assert service removal was called instead of service setup.
        Assert-MockCalled -CommandName Remove-NssmService -Times 1 -Exactly -Scope It
        Assert-MockCalled -CommandName Set-NssmService -Times 0 -Exactly -Scope It
    }

    It "Should setup service for non absent state" {
        # Mocks to avoid throw errors.
        Mock Set-Location {}
        Mock Get-VstsInput {
            return $false
        } -ParameterFilter { $Name -eq "remote" }
        Mock Get-VstsInput {
            return "somepath"
        } -ParameterFilter { $Name -eq "cwd" }
        # Mocks used to control flow.
        Mock Get-VstsInput {
            return "started"
        } -ParameterFilter { $Name -eq "serviceState" }
        # Mock used to assert after act.
        Mock Remove-NssmService {}
        Mock Set-NssmService {}

        # Act
        Main

        # Assert service setup was called instead of service removal.
        Assert-MockCalled -CommandName Remove-NssmService -Times 0 -Exactly -Scope It
        Assert-MockCalled -CommandName Set-NssmService -Times 1 -Exactly -Scope It
    }
}
