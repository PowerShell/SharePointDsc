[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "")]
param
(
    [Parameter()]
    [string]
    $SharePointCmdletModule = (Join-Path -Path $PSScriptRoot `
            -ChildPath "..\Stubs\SharePoint\15.0.4805.1000\Microsoft.SharePoint.PowerShell.psm1" `
            -Resolve)
)

$script:DSCModuleName = 'SharePointDsc'
$script:DSCResourceName = 'SPSiteUrl'
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
                Invoke-Command -Scriptblock $Global:SPDscHelper.InitializeScript -NoNewScope

                # Mocks for all contexts
                Mock -CommandName Remove-SPSiteUrl -MockWith { }
                Mock -CommandName Set-SPSiteUrl -MockWith { }
                Mock -CommandName Get-SPSiteUrl -MockWith {
                    if ($global:SpDscSPSiteUrlRanOnce -eq $false)
                    {
                        $global:SpDscSPSiteUrlRanOnce = $true
                        return @(
                            @{
                                Url  = "http://sharepoint.contoso.intra"
                                Zone = "Default"
                            },
                            @{
                                Url  = "http://sharepoint.contoso.com"
                                Zone = "Intranet"
                            },
                            @{
                                Url  = "https://sharepoint.contoso.com"
                                Zone = "Internet"
                            }
                        )
                    }
                    else
                    {
                        return $null
                    }
                }
                $global:SpDscSPSiteUrlRanOnce = $false

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

            # Test contexts
            Context -Name "No zones specified" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Url = "http://sharepoint.contoso.intra"
                    }

                    Mock -CommandName Get-SPSite -MockWith { return $null }
                }

                It "Should return null for Intranet zone from the get method" {
                    (Get-TargetResource @testParams).Intranet | Should -BeNullOrEmpty
                }

                It "Should create a new site from the set method" {
                    { Set-TargetResource @testParams } | Should -Throw "No zone specified. Please specify a zone"
                }
            }

            Context -Name "The site collection does not exist" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Url      = "http://site.sharepoint.com"
                        Intranet = "http://sharepoint.contoso.com"
                    }

                    Mock -CommandName Get-SPSite -MockWith {
                        return $null
                    }
                }

                It "Should return null for Intranet zone from the get method" {
                    (Get-TargetResource @testParams).Intranet | Should -BeNullOrEmpty
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should return true from the test method" {
                    { Set-TargetResource @testParams } | Should -Throw "Specified site $($testParams.Url) does not exist"
                }
            }

            Context -Name "The site is not a host named site collection" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Url      = "http://sharepoint.contoso.intra"
                        Intranet = "http://sharepoint.contoso.com"
                    }

                    Mock -CommandName Get-SPSite -MockWith {
                        return @{
                            HostHeaderIsSiteName = $false
                        }
                    }
                }

                It "Should return null for Intranet zone from the get method" {
                    (Get-TargetResource @testParams).Intranet | Should -BeNullOrEmpty
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should throw exception from the set method" {
                    { Set-TargetResource @testParams } | Should -Throw "Specified site $($testParams.Url) is not a Host Named Site Collection"
                }
            }

            Context -Name "The site exists, but the specified Intranet is already in use" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Url      = "http://sharepoint.contoso.intra"
                        Intranet = "http://sharepoint.contoso.com"
                        Internet = "http://custom.contoso.com"
                    }

                    Mock -CommandName Get-SPSite -MockWith {
                        return @{
                            HostHeaderIsSiteName = $true
                        }
                    }

                    Mock -CommandName Get-SPSiteUrl -MockWith {
                        return @(
                            @{
                                Url  = "http://sharepoint.contoso.intra"
                                Zone = "Default"
                            }
                        )
                    }
                }

                It "Should throw an exception in the set method" {
                    { Set-TargetResource @testParams } | Should -Throw "Specified URL $($testParams.Intranet) (Zone: Intranet) is already assigned to a site collection"
                }
            }

            Context -Name "The site exists, but the specified Internet is already in use" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Url      = "http://sharepoint.contoso.intra"
                        Internet = "http://custom.contoso.com"
                    }

                    Mock -CommandName Get-SPSite -MockWith {
                        return @{
                            HostHeaderIsSiteName = $true
                        }
                    }

                    Mock -CommandName Get-SPSiteUrl -MockWith {
                        return @(
                            @{
                                Url  = "http://sharepoint.contoso.intra"
                                Zone = "Default"
                            }
                        )
                    }
                }

                It "Should throw an exception in the set method" {
                    { Set-TargetResource @testParams } | Should -Throw "Specified URL $($testParams.Internet) (Zone: Internet) is already assigned to a site collection"
                }
            }

            Context -Name "The site exists, but the specified Extranet is already in use" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Url      = "http://sharepoint.contoso.intra"
                        Extranet = "http://sharepoint.contoso.com"
                    }

                    Mock -CommandName Get-SPSite -MockWith {
                        return @{
                            HostHeaderIsSiteName = $true
                        }
                    }

                    Mock -CommandName Get-SPSiteUrl -MockWith {
                        return @(
                            @{
                                Url  = "http://sharepoint.contoso.intra"
                                Zone = "Default"
                            }
                        )
                    }
                }

                It "Should throw an exception in the set method" {
                    { Set-TargetResource @testParams } | Should -Throw "Specified URL $($testParams.Extranet) (Zone: Extranet) is already assigned to a site collection"
                }
            }

            Context -Name "The site exists, but the specified Custom is already in use" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Url    = "http://sharepoint.contoso.intra"
                        Custom = "http://sharepoint.contoso.com"
                    }

                    Mock -CommandName Get-SPSite -MockWith {
                        return @{
                            HostHeaderIsSiteName = $true
                        }
                    }

                    Mock -CommandName Get-SPSiteUrl -MockWith {
                        return @(
                            @{
                                Url  = "http://sharepoint.contoso.intra"
                                Zone = "Default"
                            }
                        )
                    }
                }

                It "Should throw an exception in the set method" {
                    { Set-TargetResource @testParams } | Should -Throw "Specified URL $($testParams.Custom) (Zone: Custom) is already assigned to a site collection"
                }
            }

            Context -Name "The site exists and the Internet zone should not be configured" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Url      = "http://sharepoint.contoso.intra"
                        Intranet = "http://sharepoint.contoso.com"
                    }

                    Mock -CommandName Get-SPSite -MockWith {
                        return @{
                            HostHeaderIsSiteName = $true
                        }
                    }
                }

                It "Should return values for the Intranet and Internet zones from the get method" {
                    $result = Get-TargetResource @testParams
                    $result.Intranet | Should -Be "http://sharepoint.contoso.com"
                    $result.Internet | Should -Be "https://sharepoint.contoso.com"
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should configure the specified values in the set method" {
                    $global:SpDscSPSiteUrlRanOnce = $false
                    Set-TargetResource @testParams
                    Assert-MockCalled Remove-SPSiteUrl
                }
            }

            Context -Name "The site exists, but the Internet and Intranet zones are not configured" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Url      = "http://sharepoint.contoso.intra"
                        Intranet = "http://sharepoint.contoso.com"
                        Internet = "http://custom.contoso.com"
                    }

                    Mock -CommandName Get-SPSite -MockWith {
                        return @{
                            HostHeaderIsSiteName = $true
                        }
                    }

                    Mock -CommandName Get-SPSiteUrl -MockWith {
                        if ($global:SpDscSPSiteUrlRanOnce -eq $false)
                        {
                            $global:SpDscSPSiteUrlRanOnce = $true
                            return @(
                                @{
                                    Url  = "http://sharepoint.contoso.intra"
                                    Zone = "Default"
                                },
                                @{
                                    Url  = "http://sharepoint.contoso.com"
                                    Zone = "Extranet"
                                },
                                @{
                                    Url  = "https://sharepoint.contoso.com"
                                    Zone = "Custom"
                                }
                            )
                        }
                        else
                        {
                            return $null
                        }
                    }
                }

                It "Should return values for the Intranet and Internet zones from the get method" {
                    $global:SpDscSPSiteUrlRanOnce = $false
                    $result = Get-TargetResource @testParams
                    $result.Extranet | Should -Be "http://sharepoint.contoso.com"
                    $result.Custom | Should -Be "https://sharepoint.contoso.com"
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should configure the specified values in the set method" {
                    $global:SpDscSPSiteUrlRanOnce = $false
                    Set-TargetResource @testParams
                    Assert-MockCalled Remove-SPSiteUrl
                    Assert-MockCalled Set-SPSiteUrl
                }
            }

            Context -Name "The site exists, but the Extranet and Custom zones are not configured" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Url      = "http://sharepoint.contoso.intra"
                        Extranet = "http://sharepoint.contoso.com"
                        Custom   = "http://custom.contoso.com"
                    }

                    Mock -CommandName Get-SPSite -MockWith {
                        return @{
                            HostHeaderIsSiteName = $true
                        }
                    }

                    Mock -CommandName Get-SPSiteUrl -MockWith {
                        if ($global:SpDscSPSiteUrlRanOnce -eq $false)
                        {
                            $global:SpDscSPSiteUrlRanOnce = $true
                            return @(
                                @{
                                    Url  = "http://sharepoint.contoso.intra"
                                    Zone = "Default"
                                },
                                @{
                                    Url  = "http://sharepoint.contoso.com"
                                    Zone = "Intranet"
                                },
                                @{
                                    Url  = "https://sharepoint.contoso.com"
                                    Zone = "Internet"
                                }
                            )
                        }
                        else
                        {
                            return $null
                        }
                    }
                }

                It "Should return values for the Intranet and Internet zones from the get method" {
                    $global:SpDscSPSiteUrlRanOnce = $false
                    $result = Get-TargetResource @testParams
                    $result.Intranet | Should -Be "http://sharepoint.contoso.com"
                    $result.Internet | Should -Be "https://sharepoint.contoso.com"
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should configure the specified values in the set method" {
                    $global:SpDscSPSiteUrlRanOnce = $false
                    Set-TargetResource @testParams
                    Assert-MockCalled Remove-SPSiteUrl
                    Assert-MockCalled Set-SPSiteUrl
                }
            }

            Context -Name "The site exists and all zones are configured correctly" -Fixture {
                BeforeAll {
                    $testParams = @{
                        Url      = "http://sharepoint.contoso.intra"
                        Intranet = "http://sharepoint.contoso.com"
                        Internet = "https://sharepoint.contoso.com"
                    }

                    Mock -CommandName Get-SPSite -MockWith {
                        return @{
                            HostHeaderIsSiteName = $true
                        }
                    }
                }

                It "Should return values for the Intranet and Internet zones from the get method" {
                    $global:SpDscSPSiteUrlRanOnce = $false
                    $result = Get-TargetResource @testParams
                    $result.Intranet | Should -Be "http://sharepoint.contoso.com"
                    $result.Internet | Should -Be "https://sharepoint.contoso.com"
                }

                It "Should return true from the test method" {
                    $global:SpDscSPSiteUrlRanOnce = $false
                    Test-TargetResource @testParams | Should -Be $true
                }
            }

            Context -Name "Running ReverseDsc Export" -Fixture {
                BeforeAll {
                    Import-Module (Join-Path -Path (Split-Path -Path (Get-Module SharePointDsc -ListAvailable).Path -Parent) -ChildPath "Modules\SharePointDSC.Reverse\SharePointDSC.Reverse.psm1")

                    Mock -CommandName Write-Host -MockWith { }

                    Mock -CommandName Get-TargetResource -MockWith {
                        return @{
                            Url      = "http://sharepoint.contoso.intra"
                            Intranet = "http://sharepoint.contoso.com"
                            Internet = "https://sharepoint.contoso.com"
                        }
                    }

                    if ($null -eq (Get-Variable -Name 'spFarmAccount' -ErrorAction SilentlyContinue))
                    {
                        $mockPassword = ConvertTo-SecureString -String "password" -AsPlainText -Force
                        $Global:spFarmAccount = New-Object -TypeName System.Management.Automation.PSCredential ("contoso\spfarm", $mockPassword)
                    }

                    $result = @'
        SPSiteUrl [0-9A-Fa-f]{8}[-][0-9A-Fa-f]{4}[-][0-9A-Fa-f]{4}[-][0-9A-Fa-f]{4}[-][0-9A-Fa-f]{12}
        {
            Internet             = "https://sharepoint.contoso.com";
            Intranet             = "http://sharepoint.contoso.com";
            PsDscRunAsCredential = \$Credsspfarm;
            Url                  = "http://sharepoint.contoso.intra";
        }

'@
                }

                It "Should return valid DSC block from the Export method" {
                    Export-TargetResource -Url "http://sharepoint.contoso.intra" | Should -Match $result
                }
            }
        }
    }
}
finally
{
    Invoke-TestCleanup
}
