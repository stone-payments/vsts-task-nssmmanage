# TODO: Extract script body routine to some setup behavior inside 'describes' to allow 'Run tests' and 'Debug tests' from vscode.

# Found and import source script.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
$srcDir = "$here\.."
. "$srcDir\scripts\$sut" -dotSourceOnly
# Import vsts sdk.
$vstsSdkPath = Join-Path $PSScriptRoot ..\sdk\ps_modules\VstsTaskSdk\VstsTaskSdk.psm1 -Resolve
Import-Module -Name $vstsSdkPath

# Set vsts sdk aliases.
Set-Alias -Name Trace-VstsEnteringInvocation -Value Trace-EnteringInvocation
Set-Alias -Name Trace-VstsLeavingInvocation -Value Trace-LeavingInvocation
Set-Alias -Name Get-VstsInput -Value Get-Input
Set-Alias -Name Assert-VstsPath -Value Assert-Path
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
    
    It "Must return some object" {
        Mock New-PSSession -MockWith { return "not_empty" }
        Get-PSSession | Should -Not -BeNullOrEmpty
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

Describe 'Get-PSSessionOptions' {
    It 'Given ignoreCertificate, session options must ignore certificate checks' {
        $sessionOptions = Get-PSSessionOptions -ignoreCertificate $true
        $sessionOptions | Should -Not -BeNullOrEmpty
        $sessionOptions.SkipCACheck | Should -Be $true
        $sessionOptions.SkipCNCheck | Should -Be $true
        $sessionOptions.SkipRevocationCheck | Should -Be $true
    }

    It 'Given ignoreCertificate as false, session options must do certificate checks' {
        $sessionOptions = Get-PSSessionOptions -ignoreCertificate $false
        $sessionOptions | Should -Not -BeNullOrEmpty
        $sessionOptions.SkipCACheck | Should -Be $false
        $sessionOptions.SkipCNCheck | Should -Be $false
        $sessionOptions.SkipRevocationCheck | Should -Be $false
    }
}

Describe 'Resolve-NssmPath' {

    Context 'Remote or local execution' {
        It 'Given not null remote session, must execute remotely' {

            Mock New-PSSession {
                [pscustomobject]@{
                    ComputerName      = $ComputerName[0]
                    Availability      = 'Available'
                    ComputerType      = 'RemoteMachine'
                    Id                = 1
                    Name              = 'Session1'
                    ConfigurationName = 'Microsoft.PowerShell'
                    PSTypeName        = 'System.Management.Automation.Runspaces.PSSession'
                }
            }

            Mock Get-CimInstance {
                [pscustomobject]@{
                    CSName     = 'server'
                    PSTypeName = 'Microsoft.Management.Infrastructure.CimInstance#root/cimv2/Win32_OperatingSystem'
                }
            } -ParameterFilter {$ClassName -And $ClassName -ieq 'Win32_OperatingSystem'}

            Mock Invoke-Command { } -ParameterFilter {
                $Session -ne $null
            }

            $guid = [guid]::NewGuid()
            $fakeSession = (New-PSSession -ComputerName 'server')

            $exThrowed = $false
            try {
                Resolve-NssmPath -nssmPath $guid -remoteSession $fakeSession
            }
            # Terrible way of verify if invoke-command in remote session is being called. Unfortunately we could not find a way to mock the PSSession type.
            catch {
                $exMessage = 'value of type "System.Management.Automation.Runspaces.PSSession" to type "System.Management.Automation.Runspaces.PSSession'
                $_ | Should -Match $exMessage
                $exThrowed = $true
            }
            finally {
                $exThrowed | Should -Be $true
            }
        }

        It 'Given null remote session, must execute localy' {
            $expectedPath = "fake_nssm_path"
            Mock Get-Command { return $expectedPath}

            $emptySession = [System.Management.Automation.Runspaces.PSSession]$null
            Resolve-NssmPath -nssmPath $expectedPath -remoteSession $emptySession | Should -Be $expectedPath
        }
    }

    Context 'scriptblock' {
        It 'Given valid nssmPath, must return the same value' {
            $emptySession = [System.Management.Automation.Runspaces.PSSession]$null
            Resolve-NssmPath -nssmPath "cmd.exe" -remoteSession $emptySession | Should -Be "cmd.exe"
        }

        It 'Given invalid nssmPath, must try resolve from PATH variable' {
            $expectedObject = @{ Source = "C:\temp\nssm.exe" }
            Mock Get-Command { return $null } -ParameterFilter {
                $Name -eq 'invalidpath'
            }
            Mock Get-Command { return $expectedObject } -ParameterFilter {
                $Name -eq 'nssm.exe'
            }
            Mock Write-Host {}

            $emptySession = [System.Management.Automation.Runspaces.PSSession]$null
            Resolve-NssmPath -nssmPath "invalidpath" -remoteSession $emptySession | Should -Be $expectedObject.Source
            Assert-MockCalled Write-Host -ParameterFilter {
                $Object -eq "nssm.exe path invalid or not specified trying to resolve."
            }
        }
    }
}

Describe 'Remove-NssmService' {
    It "Must stop and remove service via nssm.exe" {
        # Arrange
        Mock Invoke-Tool {}
        $fakeSession = "fakesession"
        $expectedPath = "fakenssm.exe"
        $expectedService = "nssmtestservice"
        # Act
        Remove-NssmService $expectedPath $expectedService $fakeSession
        # Assert
        $expectedStopCommand = "stop $expectedService"
        Assert-MockCalled Invoke-Tool -ParameterFilter {
            ($FileName -eq $expectedPath) -and ($Arguments -eq $expectedStopCommand) -and ($remoteSession -eq $fakeSession)
        }

        $expectedRemoveCommand = "remove $expectedService confirm"
        Assert-MockCalled Invoke-Tool -ParameterFilter {
            ($FileName -eq $expectedPath) -and ($Arguments -eq $expectedRemoveCommand) -and ($remoteSession -eq $fakeSession)
        }
    }
}

Describe 'Invoke-Tool' {

    It "Given not null remote session, must call remote tool" {
        # Arrange
        Mock Invoke-RemoteTool {}
        $expectedPath = "fakenssm.exe"
        $expectedArgs = "arg1 arg2"
        $fakeSession = "fakesession"
        # Act
        Invoke-Tool -FileName $expectedPath -Arguments $expectedArgs -remoteSession $fakeSession
        # Assert
        Assert-MockCalled Invoke-RemoteTool -ParameterFilter {
            ($FileName -eq $expectedPath) -and ($Arguments -eq $expectedArgs) -and ($remoteSession -eq $fakeSession)
        } -Exactly -Times 1
    }

    # Vsts function stub.
    function Invoke-VstsTool () {}
    It "Given null remote session, must call vsts tool" {
        # Arrange
        Mock Invoke-VstsTool {}
        $expectedPath = "fakenssm.exe"
        $expectedArgs = "arg1 arg2"
        # Act
        Invoke-Tool -FileName $expectedPath -Arguments $expectedArgs -remoteSession $null

        # Assert
        Assert-MockCalled Invoke-VstsTool -Exactly -Times 1
    }
}

# Override system Invoke-Command with stub.
function Invoke-Command ($Session, $ArgumentList, $ScriptBlock, $ErrorAction) {}
Describe 'Invoke-RemoteTool' {
    Mock Invoke-Command {}
    $emptySession = [System.Management.Automation.Runspaces.PSSession]$null
    $fileName = "fakenssm.exe"
    $fakeArguments = "arg1 arg2"
    $expectedMessage = "##[command]`"$fileName`" $fakeArguments"

    It 'Must write vsts command snippet' {
        Mock Write-Host {}
        # Act
        Invoke-RemoteTool -FileName $fileName -Arguments $fakeArguments -remoteSession $emptySession

        # Assert
        Assert-MockCalled Write-Host -Times 1 -Exactly -ParameterFilter {
            $Object -eq $expectedMessage
        }
    }

    It 'Must invoke remote command' {
        $fakeSession = "fakePssession"
        # Act
        Invoke-RemoteTool -FileName $fileName -Arguments $fakeArguments -remoteSession $fakeSession

        # Assert
        Assert-MockCalled Invoke-Command -Scope It -ParameterFilter {
            ($Session -eq $fakeSession)
        }
    }
}

Describe 'Set-NssmService' {
    Mock Write-Host {}
    $serviceName = "MyTestService"

    Context 'When $serviceState = stopped' {
        Mock Get-VstsInput {}
        Mock Get-NssmService {}
        Mock Install-NssmService {}
        Mock Set-NssmAppProperties {}
        Mock Set-NssmDetails {}
        Mock Set-NssmLogOn {}
        Mock Set-NssmLogs {}
        Mock Set-NssmExitActions {}
        Mock Invoke-Tool {}

        $service = [pscustomobject]@{
            Status          = "TempStatus"
            Name            = $serviceName
            DisplayName     = 'My Mocked Test Service'
        }
        Mock Get-Service { Return $service; } -ParameterFilter { $Name -eq $serviceName }

        It 'Given Running service, must stop the service' {
            # Arrange
            $service.Status = "Running";

            # Act
            Set-NssmService -NssmPath "NSSMPATH" -ServiceName $serviceName -ServiceState "stopped" -RemoteSession $NULL;
            
            # Assert
            Assert-MockCalled Get-Service -Exactly -Times 1 -Scope It;
            Assert-MockCalled Invoke-Tool -ParameterFilter { $Arguments -eq "stop $ServiceName"; } -Exactly -Times 1 -Scope It;
        }

        It 'Given Stopped service, must do nothing' {
            # Arrange
            $service.Status = "Stopped";

            # Act
            Set-NssmService -NssmPath "NSSMPATH" -ServiceName $serviceName -ServiceState "stopped" -RemoteSession $NULL;
            
            # Assert
            Assert-MockCalled Get-Service -Exactly -Times 1 -Scope It;
            Assert-MockCalled Invoke-Tool -ParameterFilter { $Arguments -eq "stop $ServiceName"; } -Exactly -Times 0 -Scope It;
        }
    }
}