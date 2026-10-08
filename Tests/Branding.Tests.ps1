BeforeAll {
    $script:BrandingRoot = Split-Path -Parent $PSScriptRoot
    $script:Branding = Get-Content -LiteralPath (Join-Path $script:BrandingRoot 'assets\branding.json') -Raw | ConvertFrom-Json
}

Describe 'Shared project banner and package naming contract' {
    It 'reproduces both banner files with the shared generator' {
        { & (Join-Path $script:BrandingRoot 'build\Update-Banners.ps1') -Check } | Should -Not -Throw
    }

    It 'keeps the same dimensions, radius, owner label, footer, and bare script name' {
        foreach ($Variant in @(
                @{ Name = 'banner.svg'; Width = '1280'; X = '64' },
                @{ Name = 'banner-compact.svg'; Width = '640'; X = '32' }
            )) {
            $Svg = ([xml](Get-Content -LiteralPath (Join-Path $script:BrandingRoot ('assets\' + $Variant.Name)) -Raw)).DocumentElement
            $Svg.GetAttribute('width') | Should -BeExactly $Variant.Width
            $Svg.GetAttribute('height') | Should -BeExactly '360'
            $Svg.SelectSingleNode("*[local-name()='rect']").GetAttribute('rx') | Should -BeExactly '24'
            $Texts = @($Svg.SelectNodes("*[local-name()='text']"))
            $Texts[0].InnerText | Should -BeExactly 'VARTAXE / CONFIGMGR OSD'
            $Texts[-1].InnerText | Should -BeExactly 'Windows PowerShell 5.1 / MIT licensed'
            foreach ($Text in $Texts) { $Text.GetAttribute('x') | Should -BeExactly $Variant.X }
            $FileLabel = $Svg.SelectSingleNode("*[local-name()='text' and @class='script-name']")
            $FileLabel.InnerText | Should -BeExactly $script:Branding.script
            $FileLabel.InnerText | Should -Not -Match '[\\/]'
            ($Texts.InnerText -join ' ') | Should -Not -Match '(?i)release v|validation pending'
        }
    }

    It 'uses a cache-versioned compact banner at the shared breakpoint' {
        $Version = (Get-Content -LiteralPath (Join-Path $script:BrandingRoot 'VERSION') -Raw).Trim()
        $Readme = Get-Content -LiteralPath (Join-Path $script:BrandingRoot 'README.md') -Raw
        $Readme | Should -Match ('<source media="\(max-width: 720px\)" srcset="assets/banner-compact\.svg\?v=' +
            [regex]::Escape($Version) + '" width="640">')
        $Readme | Should -Match ('src="assets/banner\.svg\?v=' + [regex]::Escape($Version) + '"')
    }

    It 'avoids fixed HTML heights in responsive GitHub pictures' -Tag 'ResponsivePictures' {
        $PicturesChecked = 0
        foreach ($File in Get-ChildItem -LiteralPath $script:BrandingRoot -Filter '*.md' -File -Recurse) {
            $Content = Get-Content -LiteralPath $File.FullName -Raw
            foreach ($Picture in [regex]::Matches($Content, '(?s)<picture\b.*?</picture>')) {
                $Picture.Value | Should -Not -Match '\bheight=' -Because 'responsive SVG geometry belongs in the SVG, not a fixed GitHub HTML height'
                $Picture.Value | Should -Match '\bwidth="[1-9]\d*"'
                $PicturesChecked++
            }
        }
        $PicturesChecked | Should -BeGreaterThan 2
    }

    It 'uses the Scripts folder as package source and only the filename in the step field' {
        $Deployment = Get-Content -LiteralPath (Join-Path $script:BrandingRoot 'docs\deployment.md') -Raw
        $Deployment | Should -Match 'Package source:.*Scripts'
        $Deployment | Should -Match ('(?m)^Script name: ' + [regex]::Escape($script:Branding.script) + '\r?$')
        $Deployment | Should -Not -Match '(?m)^Script name:.*[\\/]'
    }

    It 'keeps the shared README outline, badge order, and filename-only operator labels' {
        $Readme = Get-Content -LiteralPath (Join-Path $script:BrandingRoot 'README.md') -Raw
        $Headings = @([regex]::Matches($Readme, '(?m)^## (.+?)\r?$') |
            ForEach-Object { $_.Groups[1].Value })
        $Expected = @('Requirements', 'Quick start', 'Outputs and results', 'Documentation',
            'Validation and rollout', 'Maintainer', 'Related projects', 'License')
        ($Headings -join '|') | Should -BeExactly ($Expected -join '|')
        $Readme | Should -Match '(?s)\[!\[Release v.*\[!\[CI - main push.*!\[Windows PowerShell 5\.1\].*\[!\[MIT license\]'
        $Readme | Should -Match ('\*\*Script name\*\* to `' + [regex]::Escape($script:Branding.script) + '`')
        $Readme | Should -Not -Match '\.\\Scripts\\|## Community|\[!\[Sponsor'
        $Readme | Should -Match 'Script[s]?` folder as the ConfigMgr package source'
    }

    It 'uses matching guide titles and navigation immediately after the heading' {
        foreach ($Directory in 'docs', 'examples') {
            foreach ($File in Get-ChildItem -LiteralPath (Join-Path $script:BrandingRoot $Directory) -Filter '*.md' -File) {
                $Content = (Get-Content -LiteralPath $File.FullName -Raw).Replace("`r`n", "`n")
                $Title = [regex]::Match($Content, '(?m)^title: (.+)$').Groups[1].Value
                $Title | Should -Not -BeNullOrEmpty
                $Content | Should -Match ('(?m)^# ' + [regex]::Escape($Title) +
                    '\n\n\[Documentation home\]\(\.\./index\.md\) \| \[Development\]')
                ([regex]::Matches($Content, '\[Documentation home\]')).Count | Should -Be 1
            }
        }
    }

    It 'runs editor validation tasks through the explicit Windows PowerShell executable' {
        $Configuration = Get-Content -LiteralPath (Join-Path $script:BrandingRoot '.vscode\tasks.json') -Raw | ConvertFrom-Json
        @($Configuration.tasks).Count | Should -Be 2
        foreach ($Task in $Configuration.tasks) {
            $Task.type | Should -BeExactly 'process'
            $Task.command | Should -BeExactly '${env:windir}\System32\WindowsPowerShell\v1.0\powershell.exe'
            $Task.args | Should -Contain '-NonInteractive'
            $Task.options.cwd | Should -BeExactly '${workspaceFolder}'
        }
    }

    It 'detects a stale generated banner without changing the source artwork' {
        $Root = Join-Path $TestDrive 'banner-fixture'
        foreach ($Directory in 'Scripts', 'assets', 'build') {
            New-Item -ItemType Directory -Path (Join-Path $Root $Directory) | Out-Null
        }
        foreach ($Relative in @('assets\branding.json', 'assets\banner.svg',
                'assets\banner-compact.svg', 'build\Update-Banners.ps1', ('Scripts\' + $script:Branding.script))) {
            Copy-Item -LiteralPath (Join-Path $script:BrandingRoot $Relative) -Destination (Join-Path $Root $Relative)
        }
        $Before = (Get-FileHash -LiteralPath (Join-Path $script:BrandingRoot 'assets\banner.svg')).Hash
        Add-Content -LiteralPath (Join-Path $Root 'assets\banner.svg') -Value ' '
        { & (Join-Path $Root 'build\Update-Banners.ps1') -Check } | Should -Throw '*Banner is out of date*'
        (Get-FileHash -LiteralPath (Join-Path $script:BrandingRoot 'assets\banner.svg')).Hash | Should -BeExactly $Before
    }
}
