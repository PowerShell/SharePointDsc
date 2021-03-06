[CmdletBinding()]
param
(
    [Parameter()]
    [string]
    $SharePointCmdletModule = (Join-Path -Path $PSScriptRoot `
            -ChildPath "..\Stubs\SharePoint\15.0.4805.1000\Microsoft.SharePoint.PowerShell.psm1" `
            -Resolve)
)

$script:DSCModuleName = 'SharePointDsc'
$script:DSCResourceName = 'SPDiagnosticsProvider'
$script:DSCResourceFullName = 'MSFT_' + $script:DSCResourceName

function Invoke-TestSetup
{
    try
    {
        Import-Module -Name DscResource.Test -Force

        Import-Module -Name (Join-Path -Path $PSScriptRoot `
                -ChildPath "..\UnitTestHelper.psm1" `
                -Resolve)

        $Global:SPDscHelper = New-SPDscUnitTestHelper -SharePointStubModule $SharePointCmdletModule `
            -DscResource $script:DSCResourceName
    }
    catch [System.IO.FileNotFoundException]
    {
        throw 'DscResource.Test module dependency not found. Please run ".\build.ps1 -Tasks build" first.'
    }

    $script:testEnvironment = Initialize-TestEnvironment `
        -DSCModuleName $script:DSCModuleName `
        -DSCResourceName $script:DSCResourceFullName `
        -ResourceType 'Mof' `
        -TestType 'Unit'
}

function Invoke-TestCleanup
{
    Restore-TestEnvironment -TestEnvironment $script:testEnvironment
}

Invoke-TestSetup

try
{
    InModuleScope -ModuleName $script:DSCResourceFullName -ScriptBlock {
        Describe -Name $Global:SPDscHelper.DescribeHeader -Fixture {
            BeforeAll {
                Invoke-Command -ScriptBlock $Global:SPDscHelper.InitializeScript -NoNewScope

                Mock -CommandName Get-SPDiagnosticsProvider -MockWith {
                    return @{
                        Name                = "job-diagnostics-blocking-query-provider"
                        MaxTotalSizeInBytes = 100000
                        Retention           = 14
                        Enabled             = $true
                    } | Add-Member ScriptMethod Update {
                    } -PassThru
                }

                Mock -CommandName Set-SPDiagnosticsProvider -MockWith { }

                function Add-SPDscEvent
                {
                    param (
                        [Parameter(Mandatory = $true)]
                        [System.String]
                        $Message,

                        [Parameter(Mandatory = $true)]
                        [System.String]
                        $Source,

                        [Parameter()]
                        [ValidateSet('Error', 'Information', 'FailureAudit', 'SuccessAudit', 'Warning')]
                        [System.String]
                        $EntryType,

                        [Parameter()]
                        [System.UInt32]
                        $EventID
                    )
                }
            }

            Context -Name "When the Diagnostics Provider passed doesn't exist" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Name                = "MyFakeProvider"
                        Retention           = 13
                        MaxTotalSizeInBytes = 10000
                        Enabled             = $true
                        Ensure              = "Present"
                    }
                }

                It "Should return false when the Test method is called" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should throw an error about a non-existing provider" {
                    { Set-TargetResource @testParams } | Should -Throw "The specified Diagnostic Provider {MyFakeProvider} could not be found."
                }

                It "Should return absent from the Get method" {
                    (Get-TargetResource @testParams).Ensure | Should -Be "Absent"
                }
            }

            Context -Name "When the Diagnostics Provider exists" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Name                = "job-diagnostics-blocking-query-provider"
                        Retention           = 13
                        MaxTotalSizeInBytes = 10000
                        Enabled             = $true
                        Ensure              = "Present"
                    }
                }

                It "Should return false when the Test method is called" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should properly configure the provider" {
                    Set-TargetResource @testParams
                    Assert-MockCalled Set-SPDiagnosticsProvider
                }

                It "Should return a Retention period of 14 from the Get method" {
                    (Get-TargetResource @testParams).Retention | Should -Be 14
                }
            }

            Context -Name "When using Ensure is Absent" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Name                = "job-diagnostics-blocking-query-provider"
                        Retention           = 13
                        MaxTotalSizeInBytes = 10000
                        Enabled             = $true
                        Ensure              = "Absent"
                    }
                }

                It "Should properly configure the provider" {
                    { Set-TargetResource @testParams } | Should -Throw "This resource cannot remove Diagnostics Provider. Please use ensure equals Present."
                }
            }
        }
    }
}
finally
{
    Invoke-TestCleanup
}
