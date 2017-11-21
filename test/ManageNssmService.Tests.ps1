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

    # General mocks needed to control flow and avoid throwing errors.
    Mock Trace-VstsEnteringInvocation -MockWith {}
    Mock Trace-VstsLeavingInvocation -MockWith {}
    Mock Get-VstsInput {}
    Mock Resolve-NssmPath {}
    Mock Remove-NssmService {}
    Mock Get-VstsInput {
        return "absent"
    } -ParameterFilter { $Name -eq "serviceState" }
    Mock Get-PSSession {}
    Mock Set-Location {}
    Mock Assert-VstsPath {}
    Mock Write-Host {}
    Mock Set-NssmService {}
    $expectedWorkingDir = $env:TEMP
    Mock Get-VstsInput {
        return $expectedWorkingDir
    } -ParameterFilter { $Name -eq "cwd" }
    
    It 'Given remote option, opens remote session and warn about it' {
        # Mock to ensure is remote execution
        Mock Get-VstsInput {
            return $true
        } -ParameterFilter { $Name -eq "remote" }

        # Act
        Main

        # Assert 
        Assert-MockCalled -CommandName Get-VstsInput -Times 1 -Exactly -ParameterFilter { $Name -eq "remote" } -Scope It
        Assert-MockCalled -CommandName Write-Host -Times 1 -Exactly -ParameterFilter { $Object -eq "Remote execution via WinRM selected." } -Scope It
        Assert-MockCalled -CommandName Get-PSSession -Times 1 -Exactly -Scope It
    }

    It 'Given remote option is false, set working dir for local execution' {
        # Mock to ensure is local execution
        Mock Get-VstsInput {
            return $false
        } -ParameterFilter { $Name -eq "remote" }
        # Mock used to assert after act.

        # Act
        Main

        # Assert path change to expected working dir.
        Assert-MockCalled -CommandName Get-VstsInput -Times 1 -Exactly -ParameterFilter { $Name -eq "cwd" } -Scope It
        Assert-MockCalled -CommandName Assert-VstsPath -Times 1 -Exactly -ParameterFilter { $LiteralPath -eq $expectedWorkingDir } -Scope It
        Assert-MockCalled -CommandName Set-Location -Times 1 -Exactly -ParameterFilter { $Path -eq $expectedWorkingDir } -Scope It
    }

    It 'Must resolve nssm path' {
        Mock Get-VstsInput {
            return $false
        } -ParameterFilter { $Name -eq "remote" }
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

    It "Given absent desired sevice state, remove service" {
        # Mocks to avoid throw errors.
        Mock Get-VstsInput {
            return $false
        } -ParameterFilter { $Name -eq "remote" }

        # Act
        Main

        # Assert service removal was called instead of service setup.
        Assert-MockCalled -CommandName Remove-NssmService -Times 1 -Exactly -Scope It
        Assert-MockCalled -CommandName Set-NssmService -Times 0 -Exactly -Scope It
    }

    It "Given non-absent desired sevice state, setup service" {
        # Mocks to avoid throw errors.
        Mock Get-VstsInput {
            return $false
        } -ParameterFilter { $Name -eq "remote" }
        # Mocks used to control flow.
        Mock Get-VstsInput {
            return "started"
        } -ParameterFilter { $Name -eq "serviceState" }

        # Act
        Main

        # Assert service setup was called instead of service removal.
        Assert-MockCalled -CommandName Remove-NssmService -Times 0 -Exactly -Scope It
        Assert-MockCalled -CommandName Set-NssmService -Times 1 -Exactly -Scope It
    }
}

Describe 'Get-PSSession' {

    # Mock with defaults and avoid system functions from throwing errors.
    Mock Get-VstsInput { return "somevalue"}
    Mock Get-PSSessionOptions { return New-PSSessionOption }
    Mock New-PSSession -MockWith {}

    It "Must read session inputs from vsts sdk" {
        # Act
        Get-PSSession
        # Assert
        Assert-MockCalled -CommandName Get-VstsInput -Times 1 -Exactly -ParameterFilter { $Name -eq "Machine" -and $Require } -Scope It
        Assert-MockCalled -CommandName Get-VstsInput -Times 1 -Exactly -ParameterFilter { $Name -eq "AdminUserName" -and $Require } -Scope It
        Assert-MockCalled -CommandName Get-VstsInput -Times 1 -Exactly -ParameterFilter { $Name -eq "AdminPassword" -and $Require } -Scope It
        Assert-MockCalled -CommandName Get-VstsInput -Times 1 -Exactly -ParameterFilter { $Name -eq "Protocol" -and $Require } -Scope It
        Assert-MockCalled -CommandName Get-VstsInput -Times 1 -Exactly -ParameterFilter { $Name -eq "TestCertificate" -and $Require } -Scope It
    }
    
    Context 'PSSession args validation' {
        # Mock expected inputs.
        $expectedComputerName = "UmaMaquinaMinha"
        Mock Get-VstsInput { return $expectedComputerName } -ParameterFilter { $Name -eq "Machine" }
        Mock Get-VstsInput { return $expectedCertificateInfo } -ParameterFilter { $Name -eq "TestCertificate" }
        # Mock credentials generation.
        $expectedUser = "some_it_guy"
        Mock Get-VstsInput { return $expectedUser } -ParameterFilter { $Name -eq "AdminUserName" }
        $expectedPass = "veryHardPassword"
        Mock Get-VstsInput { return $expectedPass } -ParameterFilter { $Name -eq "AdminPassword" }
        $expectedSecurePass = ConvertTo-SecureString $expectedPass -AsPlainText -Force
        $creds = New-Object System.Management.Automation.PSCredential ($expectedUser, $expectedSecurePass)
        Mock ConvertTo-SecureString { return $expectedSecurePass }
        Mock New-Object { return $creds} -ParameterFilter { $TypeName -eq "System.Management.Automation.PSCredential" }
        
        It "Given Https protocol, UseSSL must be true" {
            Mock Get-VstsInput { return "Https"} -ParameterFilter { $Name -eq "Protocol" }
            # Act
            Get-PSSession
            # Assert
            Assert-MockCalled -Command New-PSSession -Times 1 -Exactly -ParameterFilter { $UseSSL -eq $true } -Scope It
        }

        It "Given non-Https protocol, UseSSL must be true" {
            Mock Get-VstsInput { return "Http"} -ParameterFilter { $Name -eq "Protocol" }
            # Act
            Get-PSSession
            # Assert
            Assert-MockCalled -Command New-PSSession -Times 1 -Exactly -ParameterFilter { $UseSSL -eq $false } -Scope It
        }

        It "Must map vsts machine to PSSession ComputerName" {
            # Act
            Get-PSSession
            # Assert
            Assert-MockCalled -Command New-PSSession -Times 1 -Exactly -ParameterFilter { $ComputerName -eq $expectedComputerName } -Scope It
        }

        It "Must map vsts AdminUserName and AdminPassword to Credentials" {
            # Act
            Get-PSSession
            # Assert
            Assert-MockCalled -Command ConvertTo-SecureString -Times 1 -Exactly -ParameterFilter { $String -eq $expectedPass } -Scope It
            Assert-MockCalled -Command New-Object -Times 1 -Exactly -ParameterFilter { ($TypeName -eq "System.Management.Automation.PSCredential") -and ($ArgumentList[0] -eq $expectedUser) -and ($ArgumentList[1] -eq $expectedSecurePass) } -Scope It
            Assert-MockCalled -CommandName New-PSSession -Exactly -Times 1 -ParameterFilter { $Credential -eq $creds} -Scope It
        }

        It "Must pass certificate info to pssession options" {
            $expectedCertificateInfo = $true
            # Act
            Get-PSSession
            # Assert 
            Assert-MockCalled -Command Get-PSSessionOptions -Times 1 -Exactly -ParameterFilter { $ignoreCertificate -eq $true } -Scope It
        }

        It "Must pass certificate info to pssession options" {
            $expectedCertificateInfo = $false
            # Act
            Get-PSSession
            # Assert 
            Assert-MockCalled -Command Get-PSSessionOptions -Times 1 -Exactly -ParameterFilter { $ignoreCertificate -eq $false } -Scope It
        }
    }
}