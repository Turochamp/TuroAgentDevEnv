[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Mocks run in the module scope; shared test state has to be global.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester BeforeAll variables are used in It blocks.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Pester -TestCases parameters.')]
param()

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\scripts\lib\WiFi.psm1') -Force
}

Describe 'ConvertFrom-WifiOrder' {
    It 'parses entries in order, with hotspot and retired flags' {
        $json = '[{"ssid":"HomeNet","secret":"WIFI_HOME"},{"ssid":"Phone AP","secret":"WIFI_PHONE","hotspot":true},{"ssid":"OldNet","retired":true}]'

        $order = ConvertFrom-WifiOrder -Json $json

        $order.Count | Should -Be 3
        $order[0].Ssid | Should -Be 'HomeNet'
        $order[0].Secret | Should -Be 'WIFI_HOME'
        $order[0].Hotspot | Should -BeFalse
        $order[0].Retired | Should -BeFalse
        $order[1].Hotspot | Should -BeTrue
        $order[2].Ssid | Should -Be 'OldNet'
        $order[2].Retired | Should -BeTrue
    }

    It 'accepts the shipped example, config/wifi-order.example.json' {
        $json = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..\config\wifi-order.example.json')

        $order = ConvertFrom-WifiOrder -Json $json

        @($order | Where-Object Hotspot).Count | Should -Be 1
        @($order | Where-Object Retired).Count | Should -Be 1
    }

    It 'parses a one-entry array as a one-entry list' {
        $order = ConvertFrom-WifiOrder -Json '[{"ssid":"HomeNet","secret":"WIFI_HOME"}]'

        $order.Count | Should -Be 1
        $order[0].Ssid | Should -Be 'HomeNet'
    }

    It 'rejects <Case>' -TestCases @(
        @{ Case = 'invalid JSON'; Json = '[{"ssid":'; Message = '*not valid JSON*' }
        @{ Case = 'a non-array'; Json = '{"ssid":"HomeNet","secret":"WIFI_HOME"}'; Message = '*JSON array*' }
        @{ Case = 'an empty SSID'; Json = '[{"ssid":"","secret":"WIFI_HOME"}]'; Message = '*ssid*' }
        @{ Case = 'a missing secret'; Json = '[{"ssid":"HomeNet"}]'; Message = "*HomeNet*secret*" }
        @{ Case = 'a secret name with a colon'; Json = '[{"ssid":"HomeNet","secret":"WIFI:HOME"}]'; Message = '*WIFI:HOME*' }
        @{ Case = 'a lower-case secret name'; Json = '[{"ssid":"HomeNet","secret":"wifi_home"}]'; Message = '*wifi_home*' }
        @{ Case = 'a duplicate SSID'; Json = '[{"ssid":"HomeNet","secret":"WIFI_A"},{"ssid":"HomeNet","retired":true}]'; Message = '*HomeNet*more than once*' }
        @{ Case = 'two hotspots'; Json = '[{"ssid":"A","secret":"WIFI_A","hotspot":true},{"ssid":"B","secret":"WIFI_B","hotspot":true}]'; Message = '*one hotspot*' }
        @{ Case = 'a retired hotspot'; Json = '[{"ssid":"A","retired":true,"hotspot":true}]'; Message = '*A*retired*hotspot*' }
    ) {
        param($Json, $Message)
        { ConvertFrom-WifiOrder -Json $Json } | Should -Throw -ExpectedMessage $Message
    }
}

Describe 'New-WlanProfileXml' {
    BeforeAll {
        $ns = @{ w = 'http://www.microsoft.com/networking/WLAN/profile/v1' }
        function Select-ProfileValue([string]$Xml, [string]$XPath) {
            (Select-Xml -Content $Xml -XPath $XPath -Namespace $ns).Node.InnerText
        }
    }

    It 'sets the hex SSID from the UTF-8 bytes of a non-ASCII name' {
        $roor = "R$([char]0x00D8)$([char]0x00D8)R"   # R, O-slash, O-slash, R; char codes so the file's encoding cannot matter
        $xml = New-WlanProfileXml -Ssid $roor -Password 'pw-12345'

        Select-ProfileValue $xml '/w:WLANProfile/w:SSIDConfig/w:SSID/w:hex' | Should -Be '52C398C39852'
        Select-ProfileValue $xml '/w:WLANProfile/w:SSIDConfig/w:SSID/w:name' | Should -Be $roor
        Select-ProfileValue $xml '/w:WLANProfile/w:name' | Should -Be $roor
    }

    It 'XML-escapes the SSID and the password' {
        $xml = New-WlanProfileXml -Ssid 'Cafe & <Bar>' -Password 'a<b&c"d'

        Select-ProfileValue $xml '/w:WLANProfile/w:name' | Should -Be 'Cafe & <Bar>'
        Select-ProfileValue $xml '/w:WLANProfile/w:SSIDConfig/w:SSID/w:hex' | Should -Be '436166652026203C4261723E'
        Select-ProfileValue $xml '//w:sharedKey/w:keyMaterial' | Should -Be 'a<b&c"d'
    }

    It 'is a WPA2-Personal AES passphrase profile that connects automatically' {
        $xml = New-WlanProfileXml -Ssid 'HomeNet' -Password 'pw-12345'

        Select-ProfileValue $xml '//w:authEncryption/w:authentication' | Should -Be 'WPA2PSK'
        Select-ProfileValue $xml '//w:authEncryption/w:encryption' | Should -Be 'AES'
        Select-ProfileValue $xml '//w:sharedKey/w:keyType' | Should -Be 'passPhrase'
        Select-ProfileValue $xml '//w:sharedKey/w:protected' | Should -Be 'false'
        Select-ProfileValue $xml '/w:WLANProfile/w:connectionType' | Should -Be 'ESS'
        Select-ProfileValue $xml '/w:WLANProfile/w:connectionMode' | Should -Be 'auto'
    }
}

Describe 'Get-WifiPlan' {
    BeforeAll {
        $order = ConvertFrom-WifiOrder -Json (@'
[
  {"ssid":"HomeNet","secret":"WIFI_HOME"},
  {"ssid":"WorkNet","secret":"WIFI_WORK"},
  {"ssid":"Phone AP","secret":"WIFI_PHONE","hotspot":true},
  {"ssid":"OldPhone AP","retired":true}
]
'@)
        $secrets = @{ WIFI_HOME = 'pw-home-1'; WIFI_WORK = 'pw-work-1'; WIFI_PHONE = 'pw-phone-1' }
        function Format-Plan($Plan) {
            @($Plan | ForEach-Object {
                    if ($_.Action -eq 'SetPriority') { "SetPriority $($_.Ssid)=$($_.Priority)" }
                    else { "$($_.Action) $($_.Ssid)" }
                })
        }
    }

    It 'creates every listed profile on a machine that has none, then orders them' {
        $plan = Get-WifiPlan -Order $order -Existing @('CoffeeShop') -Secrets $secrets

        Format-Plan $plan | Should -Be @(
            'Create HomeNet'
            'Create WorkNet'
            'Create Phone AP'
            'SetPriority HomeNet=1'
            'SetPriority WorkNet=2'
            'SetPriority Phone AP=3'
            'SetHotspot Phone AP'
        )
        ($plan | Where-Object Action -EQ 'Create')[0].Secret | Should -Be 'WIFI_HOME'
    }

    It 'plans nothing but the hotspot settings when the machine already matches' {
        $plan = Get-WifiPlan -Order $order -Existing @('HomeNet', 'WorkNet', 'Phone AP', 'CoffeeShop') -Secrets $secrets

        Format-Plan $plan | Should -Be @('SetHotspot Phone AP')
    }

    It 'plans nothing at all when the machine matches and no hotspot is listed' {
        $noHotspot = ConvertFrom-WifiOrder -Json '[{"ssid":"HomeNet","secret":"WIFI_HOME"},{"ssid":"WorkNet","secret":"WIFI_WORK"}]'

        $plan = Get-WifiPlan -Order $noHotspot -Existing @('HomeNet', 'WorkNet', 'CoffeeShop') -Secrets @{}

        $plan.Count | Should -Be 0
    }

    It 'deletes a retired profile that is present and still counts the rest as in order' {
        $plan = Get-WifiPlan -Order $order -Existing @('HomeNet', 'OldPhone AP', 'WorkNet', 'Phone AP') -Secrets $secrets

        Format-Plan $plan | Should -Be @('Delete OldPhone AP', 'SetHotspot Phone AP')
    }

    It 'reorders every listed profile when they are out of order, leaving unlisted ones alone' {
        $plan = Get-WifiPlan -Order $order -Existing @('CoffeeShop', 'WorkNet', 'HomeNet', 'Phone AP') -Secrets $secrets

        Format-Plan $plan | Should -Be @(
            'SetPriority HomeNet=1'
            'SetPriority WorkNet=2'
            'SetPriority Phone AP=3'
            'SetHotspot Phone AP'
        )
    }

    It 'warns and skips a missing profile with no password, closing the gap in priorities' {
        $plan = Get-WifiPlan -Order $order -Existing @('HomeNet', 'Phone AP') -Secrets @{ WIFI_HOME = 'pw-home-1' }

        Format-Plan $plan | Should -Be @(
            'Warn WorkNet'
            'SetHotspot Phone AP'
        )
        ($plan | Where-Object Action -EQ 'Warn').Message | Should -BeLike '*WorkNet*WIFI_WORK*'
    }

    It 'never puts a password into the plan' {
        $plan = Get-WifiPlan -Order $order -Existing @() -Secrets $secrets

        $values = $plan | ForEach-Object { $_.PSObject.Properties.Value }
        $values | Should -Not -Contain 'pw-home-1'
        $values | Should -Not -Contain 'pw-work-1'
        $values | Should -Not -Contain 'pw-phone-1'
    }
}

Describe 'ConvertFrom-NetshProfileList' {
    It 'returns user profiles in priority order and ignores group policy profiles' {
        $text = @'

Profiles on interface Wi-Fi 2:

Group policy profiles (read only)
---------------------------------
    All User Profile     : CorpPolicyNet

User profiles
-------------
    All User Profile     : HomeNet
    All User Profile     : Phone AP
    All User Profile     : Cafe: Upstairs

'@
        ConvertFrom-NetshProfileList -Text $text | Should -Be @('HomeNet', 'Phone AP', 'Cafe: Upstairs')
    }

    It 'returns an empty list when there are no user profiles' {
        $text = @'
Profiles on interface Wi-Fi:

Group policy profiles (read only)
---------------------------------
    <None>

User profiles
-------------
    <None>
'@
        @(ConvertFrom-NetshProfileList -Text $text).Count | Should -Be 0
    }
}

Describe 'ConvertFrom-NetshInterfaceList' {
    It 'returns each interface name, whatever it is called' {
        $text = @'

There are 2 interfaces on the system:

    Name                   : WLAN 3
    Description            : Example Wireless Adapter
    GUID                   : 00000000-0000-0000-0000-000000000001
    State                  : connected

    Name                   : Wi-Fi 2
    Description            : Example USB Adapter
    GUID                   : 00000000-0000-0000-0000-000000000002
    State                  : disconnected

'@
        ConvertFrom-NetshInterfaceList -Text $text | Should -Be @('WLAN 3', 'Wi-Fi 2')
    }
}

Describe 'Invoke-WifiSync' {
    BeforeAll {
        function Get-TestCertificatePem {
            $key = [Security.Cryptography.ECDsa]::Create()
            $request = [Security.Cryptography.X509Certificates.CertificateRequest]::new(
                'CN=Example Test Root', $key, [Security.Cryptography.HashAlgorithmName]::SHA256)
            $cert = $request.CreateSelfSigned([DateTimeOffset]::Now.AddDays(-1), [DateTimeOffset]::Now.AddDays(1))
            [pscustomobject]@{
                Thumbprint = $cert.Thumbprint
                Pem        = "-----BEGIN CERTIFICATE-----`n" +
                [Convert]::ToBase64String($cert.RawData, 'InsertLineBreaks') +
                "`n-----END CERTIFICATE-----`n"
            }
        }
        $script:testCert = Get-TestCertificatePem
    }

    BeforeEach {
        $global:WifiTest = @{
            Netsh      = [Collections.Generic.List[string]]::new()
            Infisical  = [Collections.Generic.List[string]]::new()
            ProfileXml = $null
            TempFile   = $null
            Env        = @{
                WORKSTATION_INFISICAL_URL        = 'https://secrets.example.test'
                WORKSTATION_INFISICAL_PROJECT_ID = '00000000-aaaa-bbbb-cccc-000000000000'
                WORKSTATION_CA_SOURCE            = 'example-owner/example-repo/ca/root.crt'
            }
            Stored     = @{}
            Profiles   = @('CoffeeShop', 'OldPhone AP', 'WorkNet', 'Phone AP')
            Export     = @(
                @{ key = 'WIFI_ORDER'; value = '[{"ssid":"HomeNet","secret":"WIFI_HOME"},{"ssid":"WorkNet","secret":"WIFI_WORK"},{"ssid":"Phone AP","secret":"WIFI_PHONE","hotspot":true},{"ssid":"OldPhone AP","retired":true}]' }
                @{ key = 'WIFI_HOME'; value = 'pw-home-secret' }
            ) | ConvertTo-Json -Compress
            ExportExit = 0
            LoginOk    = $true
            LoggedIn   = $false
        }

        Mock -ModuleName WiFi Get-UserEnvironmentValue { $global:WifiTest.Env[$Name] }
        Mock -ModuleName WiFi Set-UserEnvironmentValue { $global:WifiTest.Stored[$Name] = $Value }
        Mock -ModuleName WiFi Read-ConfigValue { throw "unexpected prompt: $Prompt" }
        Mock -ModuleName WiFi Test-CommandAvailable { $true }
        Mock -ModuleName WiFi Install-InfisicalCli { }
        Mock -ModuleName WiFi Test-TrustedRoot { $false }
        Mock -ModuleName WiFi Add-TrustedRoot { }
        Mock -ModuleName WiFi Invoke-Gh {
            if ($ArgumentList[0] -eq 'auth') { return [pscustomobject]@{ ExitCode = 0; Output = 'Logged in'; Error = '' } }
            $b64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($script:testCert.Pem), 'InsertLineBreaks')
            [pscustomobject]@{ ExitCode = 0; Output = $b64; Error = '' }
        }
        Mock -ModuleName WiFi Invoke-InfisicalLogin { if ($global:WifiTest.LoginOk) { $global:WifiTest.LoginDone = $true; 0 } else { 1 } }
        Mock -ModuleName WiFi Invoke-Infisical {
            $global:WifiTest.Infisical.Add(($ArgumentList -join ' '))
            switch ($ArgumentList[0]) {
                'login' {
                    $ok = $global:WifiTest.LoggedIn -or $global:WifiTest.ContainsKey('LoginDone')
                    [pscustomobject]@{ ExitCode = $(if ($ok) { 0 } else { 1 }); Output = ''; Error = '' }
                }
                'export' { [pscustomobject]@{ ExitCode = $global:WifiTest.ExportExit; Output = $global:WifiTest.Export; Error = '' } }
            }
        }
        Mock -ModuleName WiFi Invoke-Netsh {
            $line = $ArgumentList -join ' '
            $global:WifiTest.Netsh.Add($line)
            if ($line -eq 'wlan show interfaces') {
                return [pscustomobject]@{ ExitCode = 0; Output = "There is 1 interface on the system:`n`n    Name                   : WLAN 3`n    State                  : connected`n"; Error = '' }
            }
            if ($line -like 'wlan show profiles*') {
                $body = ($global:WifiTest.Profiles | ForEach-Object { "    All User Profile     : $_" }) -join "`n"
                return [pscustomobject]@{ ExitCode = 0; Output = "Profiles on interface WLAN 3:`n`nUser profiles`n-------------`n$body`n"; Error = '' }
            }
            if ($line -like 'wlan add profile*') {
                $file = ($ArgumentList | Where-Object { $_ -like 'filename=*' }) -replace '^filename=', ''
                $global:WifiTest.TempFile = $file
                $global:WifiTest.ProfileXml = Get-Content -LiteralPath $file -Raw
            }
            [pscustomobject]@{ ExitCode = 0; Output = 'ok'; Error = '' }
        }
    }

    AfterEach {
        Remove-Variable -Name WifiTest -Scope Global -ErrorAction SilentlyContinue
    }

    It 'trusts the CA, logs in, and applies the plan through netsh on the detected interface' {
        Invoke-WifiSync -WarningVariable warnings -WarningAction SilentlyContinue

        Should -Invoke -ModuleName WiFi Add-TrustedRoot -Times 1 -Exactly -ParameterFilter { $Certificate.Thumbprint -eq $script:testCert.Thumbprint }
        Should -Invoke -ModuleName WiFi Invoke-InfisicalLogin -Times 1 -Exactly -ParameterFilter { $Domain -eq 'https://secrets.example.test' }
        $global:WifiTest.Infisical | Should -Contain 'export --projectId 00000000-aaaa-bbbb-cccc-000000000000 --env prod --path /workstation/wifi --format json --domain https://secrets.example.test --silent'

        $global:WifiTest.Netsh | Should -Be @(
            'wlan show interfaces'
            'wlan show profiles interface=WLAN 3'
            'wlan delete profile name=OldPhone AP interface=WLAN 3'
            "wlan add profile filename=$($global:WifiTest.TempFile) interface=WLAN 3 user=current"
            'wlan set profileorder name=HomeNet interface=WLAN 3 priority=1'
            'wlan set profileorder name=WorkNet interface=WLAN 3 priority=2'
            'wlan set profileorder name=Phone AP interface=WLAN 3 priority=3'
            'wlan set profileparameter name=Phone AP interface=WLAN 3 connectionmode=auto autoSwitch=yes cost=Fixed'
        )
        $global:WifiTest.ProfileXml | Should -BeLike '*<name>HomeNet</name>*pw-home-secret*'
        Test-Path -LiteralPath $global:WifiTest.TempFile | Should -BeFalse
        $warnings | Should -BeNullOrEmpty
    }

    It 'warns and changes nothing when Infisical is unreachable' {
        $global:WifiTest.ExportExit = 1

        Invoke-WifiSync -WarningVariable warnings -WarningAction SilentlyContinue

        $warnings | Should -BeLike '*export failed*'
        $global:WifiTest.Netsh.Count | Should -Be 0
    }

    It 'warns and changes nothing when login is cancelled' {
        $global:WifiTest.LoginOk = $false

        Invoke-WifiSync -WarningVariable warnings -WarningAction SilentlyContinue

        $warnings | Should -BeLike '*login failed or cancelled*'
        $global:WifiTest.Infisical | Should -Not -Contain 'export*'
        @($global:WifiTest.Infisical | Where-Object { $_ -like 'export*' }).Count | Should -Be 0
        $global:WifiTest.Netsh.Count | Should -Be 0
    }

    It 'skips login when already logged in, and skips the CA when already trusted' {
        $global:WifiTest.LoggedIn = $true
        Mock -ModuleName WiFi Test-TrustedRoot { $true }

        Invoke-WifiSync -WarningAction SilentlyContinue

        Should -Invoke -ModuleName WiFi Invoke-InfisicalLogin -Times 0 -Exactly
        Should -Invoke -ModuleName WiFi Add-TrustedRoot -Times 0 -Exactly
    }

    It 'warns and changes nothing when gh is not logged in' {
        Mock -ModuleName WiFi Invoke-Gh { [pscustomobject]@{ ExitCode = 1; Output = ''; Error = '' } }

        Invoke-WifiSync -WarningVariable warnings -WarningAction SilentlyContinue

        $warnings | Should -BeLike '*gh auth login*'
        $global:WifiTest.Infisical.Count | Should -Be 0
        $global:WifiTest.Netsh.Count | Should -Be 0
    }

    It 'warns and changes nothing when WIFI_ORDER is <Case>' -TestCases @(
        @{ Case = 'missing'; Export = '[{"key":"WIFI_HOME","value":"pw-home-secret"}]'; Message = '*WIFI_ORDER not found*' }
        @{ Case = 'invalid'; Export = '[{"key":"WIFI_ORDER","value":"[{\"ssid\":\"\"}]"}]'; Message = '*without an ssid*' }
    ) {
        param($Export, $Message)
        $global:WifiTest.Export = $Export

        Invoke-WifiSync -WarningVariable warnings -WarningAction SilentlyContinue

        $warnings | Should -BeLike $Message
        $global:WifiTest.Netsh.Count | Should -Be 0
    }

    It 'only reads under -WhatIf: no profile, CA or environment changes' {
        $global:WifiTest.Env.Clear()
        Mock -ModuleName WiFi Read-ConfigValue { 'example-value/x/y' }

        Invoke-WifiSync -WhatIf -WarningAction SilentlyContinue

        $global:WifiTest.Netsh | Where-Object { $_ -notlike 'wlan show *' } | Should -BeNullOrEmpty
        Should -Invoke -ModuleName WiFi Add-TrustedRoot -Times 0 -Exactly
        Should -Invoke -ModuleName WiFi Set-UserEnvironmentValue -Times 0 -Exactly
    }

    It 'warns on a failed netsh step and carries on with the rest' {
        Mock -ModuleName WiFi Invoke-Netsh {
            $line = $ArgumentList -join ' '
            $global:WifiTest.Netsh.Add($line)
            if ($line -eq 'wlan show interfaces') { return [pscustomobject]@{ ExitCode = 0; Output = "    Name : WLAN 3`n"; Error = '' } }
            if ($line -like 'wlan show profiles*') { return [pscustomobject]@{ ExitCode = 0; Output = "-----`n    All User Profile : OldPhone AP`n    All User Profile : HomeNet`n    All User Profile : Phone AP`n"; Error = '' } }
            if ($line -like 'wlan delete*') { return [pscustomobject]@{ ExitCode = 1; Output = 'Profile is in use.'; Error = '' } }
            [pscustomobject]@{ ExitCode = 0; Output = 'ok'; Error = '' }
        }

        Invoke-WifiSync -WarningVariable warnings -WarningAction SilentlyContinue

        ($warnings -join "`n") | Should -BeLike "*Delete 'OldPhone AP' failed*in use*"
        $global:WifiTest.Netsh[-1] | Should -BeLike 'wlan set profileparameter name=Phone AP*'
    }

    It 'prompts for missing settings on first run and stores them as user variables' {
        $global:WifiTest.Env.Clear()
        $global:WifiTest.Answers = @{
            'Infisical URL*'        = 'https://secrets.example.test'
            'Infisical project ID*' = 'proj-0001'
            'Root CA*'              = 'example-owner/example-repo/ca/root.crt'
        }
        Mock -ModuleName WiFi Read-ConfigValue {
            foreach ($k in $global:WifiTest.Answers.Keys) { if ($Prompt -like $k) { return $global:WifiTest.Answers[$k] } }
        }

        Invoke-WifiSync -WarningAction SilentlyContinue

        $global:WifiTest.Stored.WORKSTATION_INFISICAL_URL | Should -Be 'https://secrets.example.test'
        $global:WifiTest.Stored.WORKSTATION_INFISICAL_PROJECT_ID | Should -Be 'proj-0001'
        $global:WifiTest.Stored.WORKSTATION_CA_SOURCE | Should -Be 'example-owner/example-repo/ca/root.crt'
    }

    It 'warns and changes nothing when a prompt is left blank' {
        $global:WifiTest.Env.Clear()
        Mock -ModuleName WiFi Read-ConfigValue { '' }

        Invoke-WifiSync -WarningVariable warnings -WarningAction SilentlyContinue

        $warnings | Should -BeLike '*WORKSTATION_INFISICAL_URL not set*'
        $global:WifiTest.Netsh.Count | Should -Be 0
    }

    It 'installs the Infisical CLI when it is missing' {
        $global:WifiTest.InfisicalInstalled = $false
        Mock -ModuleName WiFi Test-CommandAvailable { $Name -ne 'infisical' -or $global:WifiTest.InfisicalInstalled }
        Mock -ModuleName WiFi Install-InfisicalCli { $global:WifiTest.InfisicalInstalled = $true }

        Invoke-WifiSync -WarningAction SilentlyContinue

        Should -Invoke -ModuleName WiFi Install-InfisicalCli -Times 1 -Exactly
        @($global:WifiTest.Infisical | Where-Object { $_ -like 'export*' }).Count | Should -Be 1
    }

    It 'never writes a password to any output stream' {
        $global:WifiTest.Export = @(
            @{ key = 'WIFI_ORDER'; value = '[{"ssid":"HomeNet","secret":"WIFI_HOME"},{"ssid":"Phone AP","secret":"WIFI_PHONE","hotspot":true}]' }
            @{ key = 'WIFI_HOME'; value = 'pw-home-secret' }
            @{ key = 'WIFI_PHONE'; value = 'pw-phone-secret' }
        ) | ConvertTo-Json -Compress
        $global:WifiTest.Profiles = @()

        $all = Invoke-WifiSync -Verbose *>&1 | Out-String

        $all | Should -Not -BeLike '*pw-home-secret*'
        $all | Should -Not -BeLike '*pw-phone-secret*'
        $all | Should -BeLike "*Create 'HomeNet'*"
    }
}
