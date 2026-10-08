BeforeDiscovery {
    $Root = Split-Path -Parent $PSScriptRoot
    $script:DocumentCases = @(
        Get-ChildItem -LiteralPath $Root -Filter '*.md' -File
        Get-ChildItem -LiteralPath (Join-Path $Root 'docs') -Filter '*.md' -File
        Get-ChildItem -LiteralPath (Join-Path $Root 'examples') -Filter '*.md' -File
    ) | ForEach-Object { @{ Path = $_.FullName; Name = $_.FullName.Substring($Root.Length + 1) } }
    $script:SvgCases = Get-ChildItem -LiteralPath (Join-Path $Root 'assets') -Filter '*.svg' -File |
        ForEach-Object { @{ Path = $_.FullName; Name = $_.Name } }
}

BeforeAll {
    $script:Root = Split-Path -Parent $PSScriptRoot

    function Get-DocumentTarget {
        param([string]$DocumentPath, [string]$Link)

        if ($Link -match '^[a-z][a-z0-9+.-]*:|^//') { return }
        $Parts = $Link -split '#', 2
        $RelativePath = [uri]::UnescapeDataString(($Parts[0] -split '\?', 2)[0])
        $Target = $DocumentPath
        if ($RelativePath) {
            $Target = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $DocumentPath) $RelativePath.Replace('/', '\')))
        }
        [pscustomobject]@{
            Path = $Target
            Fragment = if ($Parts.Count -eq 2) { [uri]::UnescapeDataString($Parts[1]) } else { '' }
        }
    }

    function Get-RelativeLuminance {
        param([string]$Color)

        $Channels = @(0, 2, 4 | ForEach-Object {
                $Channel = [Convert]::ToInt32($Color.TrimStart('#').Substring($_, 2), 16) / 255.0
                if ($Channel -le 0.04045) { $Channel / 12.92 }
                else { [math]::Pow(($Channel + 0.055) / 1.055, 2.4) }
            })
        return 0.2126 * $Channels[0] + 0.7152 * $Channels[1] + 0.0722 * $Channels[2]
    }
}

Describe 'Documentation links and artwork' {
    It 'resolves local Markdown links and heading fragments in <Name>' -ForEach $script:DocumentCases {
        $Content = Get-Content -LiteralPath $Path -Raw
        foreach ($Match in [regex]::Matches($Content, '\[[^\]]*\]\(([^)\s]+)\)')) {
            $Target = Get-DocumentTarget -DocumentPath $Path -Link $Match.Groups[1].Value
            if ($null -eq $Target) { continue }
            $Target.Path.StartsWith($script:Root + '\', [StringComparison]::OrdinalIgnoreCase) |
                Should -BeTrue -Because 'documentation must not reference files outside this repository'
            Test-Path -LiteralPath $Target.Path -PathType Leaf |
                Should -BeTrue -Because "$Name links to $($Match.Groups[1].Value)"
            if ($Target.Fragment -and [IO.Path]::GetExtension($Target.Path) -eq '.md') {
                $Headings = @(
                    foreach ($Heading in [regex]::Matches((Get-Content -LiteralPath $Target.Path -Raw), '(?m)^#{1,6}\s+(.+?)\s*$')) {
                        ($Heading.Groups[1].Value.ToLowerInvariant() -replace '[^\w\s-]', '' -replace '\s', '-')
                    }
                )
                $Headings | Should -Contain $Target.Fragment -Because "$Name links to this heading"
            }
            if ($Name -ne 'README.md') {
                $Target.Path | Should -Not -Be (Join-Path $script:Root 'README.md') -Because 'the root README is excluded from Pages'
                $Target.Path | Should -Not -Be (Join-Path $script:Root '.gitattributes') -Because 'Jekyll does not publish dotfiles'
            }
        }
    }

    It 'keeps valid, named, dimensioned SVG artwork in <Name>' -ForEach $script:SvgCases {
        $Document = [xml](Get-Content -LiteralPath $Path -Raw)
        $Svg = $Document.DocumentElement
        $Svg.LocalName | Should -BeExactly 'svg'
        $Svg.NamespaceURI | Should -BeExactly 'http://www.w3.org/2000/svg'
        $Svg.GetAttribute('role') | Should -BeExactly 'img'
        $Svg.GetAttribute('width') | Should -Match '^\d+$'
        $Svg.GetAttribute('height') | Should -Match '^\d+$'
        $Svg.GetAttribute('viewBox') | Should -BeExactly ("0 0 {0} {1}" -f $Svg.GetAttribute('width'), $Svg.GetAttribute('height'))
        $Labels = @($Svg.GetAttribute('aria-labelledby') -split '\s+')
        $Labels.Count | Should -Be 2
        foreach ($Label in $Labels) {
            $Node = $Document.SelectSingleNode("//*[@id='$Label']")
            $Node | Should -Not -BeNullOrEmpty
            $Node.InnerText | Should -Not -BeNullOrEmpty
        }
        $Document.SelectNodes("//*[local-name()='script' or local-name()='animate']").Count | Should -Be 0
    }

    It 'keeps responsive picture sizes fluid and other image dimensions explicit in <Name>' -ForEach $script:DocumentCases {
        $Content = Get-Content -LiteralPath $Path -Raw
        $Pictures = [regex]::Matches($Content, '(?s)<picture\b.*?</picture>')
        foreach ($Match in [regex]::Matches($Content, '<(?:img|source)\b[^>]+>')) {
            $Element = [xml]($Match.Value.TrimEnd('>') + '/>')
            $Node = $Element.DocumentElement
            $Link = if ($Node.LocalName -eq 'img') { $Node.GetAttribute('src') } else { $Node.GetAttribute('srcset') }
            $Target = Get-DocumentTarget -DocumentPath $Path -Link $Link
            Test-Path -LiteralPath $Target.Path -PathType Leaf | Should -BeTrue
            $Svg = ([xml](Get-Content -LiteralPath $Target.Path -Raw)).DocumentElement
            $Node.GetAttribute('width') | Should -BeExactly $Svg.GetAttribute('width')
            $InPicture = @($Pictures | Where-Object {
                    $_.Index -le $Match.Index -and $Match.Index -lt ($_.Index + $_.Length)
                }).Count -gt 0
            if ($InPicture) {
                $Node.HasAttribute('height') | Should -BeFalse -Because 'GitHub keeps a fixed HTML height when it shrinks the width'
            }
            else {
                $Node.GetAttribute('height') | Should -BeExactly $Svg.GetAttribute('height')
            }
            if ($Node.LocalName -eq 'img') {
                $Node.HasAttribute('alt') | Should -BeTrue
                if ($Node.GetAttribute('aria-hidden') -eq 'true') {
                    $Node.GetAttribute('alt') | Should -BeExactly ''
                }
                else {
                    $Node.GetAttribute('alt').Length | Should -BeGreaterThan 0
                }
            }
        }
    }

    It 'keeps banner text contrast above WCAG AA in both themes' {
        foreach ($Background in '#155799', '#117865', '#0d2e4c', '#103d38') {
            (1.05 / ((Get-RelativeLuminance $Background) + 0.05)) | Should -BeGreaterOrEqual 4.5
        }
        foreach ($Name in 'banner.svg', 'banner-compact.svg') {
            $Content = Get-Content -LiteralPath (Join-Path $script:Root "assets\$Name") -Raw
            foreach ($Color in '#155799', '#117865', '#0d2e4c', '#103d38') {
                $Content | Should -Match ([regex]::Escape($Color))
            }
        }
    }
}

Describe 'Pages and release presentation contract' {
    It 'keeps explicit front matter for the <Name> policy page' -Tag 'MaintenanceRegression' -ForEach @(
        @{ Name = 'CONTRIBUTING.md'; Title = 'Contributing' }
        @{ Name = 'CODE_OF_CONDUCT.md'; Title = 'Code of conduct' }
    ) {
        $Content = Get-Content -LiteralPath (Join-Path $script:Root $Name) -Raw
        $Content | Should -Match ('\A---\r?\ntitle: ' + [regex]::Escape($Title) + '\r?\n---\r?\n')
    }

    It 'requests diagnostic versions and private reporting in <Name>' -Tag 'MaintenanceRegression' -ForEach @(
        @{ Name = 'bug_report.yml' }
        @{ Name = 'compatibility_report.yml' }
    ) {
        $Content = Get-Content -LiteralPath (Join-Path $script:Root ".github\ISSUE_TEMPLATE\$Name") -Raw
        foreach ($RequiredText in 'Script version', 'ConfigMgr version', 'Windows version',
            'Windows PowerShell version', 'private vulnerability reporting', 'vartaxe@outlook.com') {
            $Content | Should -Match ([regex]::Escape($RequiredText))
        }
    }

    It 'asks bug reporters for reproduction steps and an exit code' -Tag 'MaintenanceRegression' {
        $Content = Get-Content -LiteralPath (Join-Path $script:Root '.github\ISSUE_TEMPLATE\bug_report.yml') -Raw
        $Content | Should -Match '(?m)^    id: reproduction\r?$'
        $Content | Should -Match '(?i)reproduction steps'
        $Content | Should -Match '(?i)expected/actual results'
        $Content | Should -Match '(?i)exit code'
    }

    It 'uses the repository base URL and built-in Pages plugins' {
        $Config = (Get-Content -LiteralPath (Join-Path $script:Root '_config.yml') -Raw).Replace("`r`n", "`n")
        $Config | Should -Match '(?m)^theme: jekyll-theme-cayman$'
        $Config | Should -Match '(?m)^url: https://vartaxe\.github\.io$'
        $Config | Should -Match '(?m)^baseurl: /ConfigMgr-OSD-AddComputerToADGroup$'
        $Config | Should -Match '(?m)^repository: vartaxe/ConfigMgr-OSD-AddComputerToADGroup$'
        $Config | Should -Match '(?m)^show_downloads: false$'
        foreach ($Plugin in 'jekyll-relative-links', 'jekyll-optional-front-matter', 'jekyll-seo-tag') {
            $Config | Should -Match "(?m)^  - $Plugin$"
        }
        $Config | Should -Match '(?m)^relative_links:\r?\n  enabled: true$'
        $Config | Should -Match '(?m)^      layout: default$'
        $Config | Should -Match '(?m)^    url: /docs/deployment\.html$'
        $Config | Should -Not -Match '(?m)^\s+url: .*\.md(?:#.*)?$'
        $Examples = (Get-Content -LiteralPath (Join-Path $script:Root 'examples\README.md') -Raw).Replace("`r`n", "`n")
        $Examples | Should -Match '\A---\r?\n'
        $Examples | Should -Match '(?m)^permalink: /examples/$'
    }

    It 'keeps the current version, live-validation scope, and reciprocal links' {
        $Version = (Get-Content -LiteralPath (Join-Path $script:Root 'VERSION') -Raw).Trim()
        foreach ($Name in 'README.md', 'index.md') {
            $Content = (Get-Content -LiteralPath (Join-Path $script:Root $Name) -Raw).Replace("`r`n", "`n")
            $Content | Should -Match ([regex]::Escape("Current version: $Version"))
            $Content | Should -Match ([regex]::Escape("releases/tag/v$Version"))
            $Content | Should -Match '(?is)live.*testing was not\s+(?:>\s*)?executed'
            $Content | Should -Not -Match '(?i)\breissue\b|actions/runs/\d+'
            $Content | Should -Match '(?m)^## Related projects$'
            $Content | Should -Match 'https://vartaxe\.github\.io/vartaxe/'
            $Content | Should -Match 'https://vartaxe\.github\.io/ConfigMgr-OSD-CopyOSDLogToFileShare/'
        }
        $Landing = Get-Content -LiteralPath (Join-Path $script:Root 'index.md') -Raw
        $Landing | Should -Not -Match 'include_relative|include README'
        $Readme = Get-Content -LiteralPath (Join-Path $script:Root 'README.md') -Raw
        $Readme | Should -Match 'badge\.svg\?branch=main&event=push'
        $Readme | Should -Match '<source media="\(max-width: 720px\)" srcset="assets/banner-compact\.svg\?v='
    }

    It 'requires downloaded-asset verification and separate maintainer approval before promotion' {
        $Process = Get-Content -LiteralPath (Join-Path $script:Root 'docs\release-process.md') -Raw
        $Process | Should -Match '(?m)^## Stage 1: Publish the prerelease candidate\r?$'
        $Process | Should -Match '(?m)^## Stage 2: Verify assets and approve promotion\r?$'
        $Process | Should -Match '(?i)workflow does not perform the promotion'
        $Process | Should -Match '(?i)downloaded ZIP'
        $Process | Should -Match '(?i)Any failed check blocks promotion'
        $Process | Should -Match '(?i)explicit maintainer approval'
        $Process | Should -Match 'https://docs\.github\.com/en/rest/releases/releases#update-a-release'
        $Process | Should -Match '`prerelease` to `false` and `make_latest` to `"true"`'
        $Process | Should -Match '(?i)Do not broaden access, switch identities, change the tag, or replace asset bytes'
    }

    It 'keeps one current-version section in the changelog and release notes' {
        $Version = (Get-Content -LiteralPath (Join-Path $script:Root 'VERSION') -Raw).Trim()
        foreach ($Name in 'CHANGELOG.md', 'RELEASE-NOTES.md') {
            $Content = Get-Content -LiteralPath (Join-Path $script:Root $Name) -Raw
            $Sections = [regex]::Matches($Content, '(?m)^##[ \t]+v(\d+\.\d+\.\d+)[ \t]*\r?$')
            $Sections.Count | Should -Be 1
            $Sections[0].Groups[1].Value | Should -BeExactly $Version
            $Content | Should -Match '(?is)live.*testing was not executed'
            $Content | Should -Not -Match '(?i)\breissue\b|actions/runs/\d+'
        }
    }
}

Describe 'Shared Pages accessibility regressions' {
    BeforeAll {
        $script:Layout = Get-Content -LiteralPath (Join-Path $script:Root '_layouts\default.html') -Raw
        $script:Styles = Get-Content -LiteralPath (Join-Path $script:Root 'assets\css\style.scss') -Raw
    }

    It 'makes generated <Opening> scroll regions keyboard-focusable with a visible focus ring' -ForEach @(
        @{ Opening = '<pre>'; Focusable = '<pre tabindex="0">'; Selector = 'pre' }
        @{ Opening = '<pre class="highlight">'; Focusable = '<pre class="highlight" tabindex="0">'; Selector = 'pre' }
        @{ Opening = '<table>'; Focusable = '<table tabindex="0">'; Selector = 'table' }
    ) {
        $Filter = "| replace: '$Opening', '$Focusable'"
        $script:Layout | Should -Match ([regex]::Escape($Filter))
        $script:Styles | Should -Match ("(?s)\.main-content {0}:focus-visible[^{{]*\{{[^}}]*outline:\s*3px solid var\(--focus\)" -f $Selector)
        $script:Styles | Should -Match ("(?s)\.main-content {0}\s*\{{[^}}]*overflow-x:\s*auto" -f $Selector)
        $script:Layout | Should -Not -Match '(?i)<script\b'
    }

    It 'overrides inherited Cayman code colors and supplies a readable fallback for syntax tokens' {
        $script:Styles | Should -Match '(?s)\.main-content pre code\s*\{\s*color:\s*inherit;\s*background:\s*transparent;'
        $script:Styles | Should -Match '(?s)\.main-content \.highlight span\s*\{\s*color:\s*var\(--ink\);\s*background-color:\s*transparent;'
        $script:Styles | Should -Match '(?s)\.main-content \.highlight \.ow\s*\{\s*color:\s*var\(--link\);'
        $script:Styles | Should -Match '(?s)\.main-content \.highlight \[class\^="s"\]\s*\{\s*color:\s*var\(--accent\);'
        $script:Styles | Should -Match '(?s)\.main-content \.highlight \.sd\s*\{\s*color:\s*var\(--muted\);'
        $script:Styles.IndexOf('@import') | Should -BeLessThan $script:Styles.IndexOf('.main-content pre code')
    }

    It 'keeps every code palette color above 4.5:1 on its panel in the <Theme> theme' -ForEach @(
        @{ Theme = 'light'; PaletteIndex = 0 }
        @{ Theme = 'dark'; PaletteIndex = 1 }
    ) {
        $Palettes = [regex]::Matches($script:Styles, '(?s):root\s*\{([^}]+)\}')
        $Palettes.Count | Should -Be 2
        $Palette = @{}
        foreach ($Match in [regex]::Matches($Palettes[$PaletteIndex].Groups[1].Value, '--([\w-]+):\s*(#[a-fA-F0-9]{6});')) {
            $Palette[$Match.Groups[1].Value] = $Match.Groups[2].Value
        }
        $Palette['panel'] | Should -Not -BeNullOrEmpty
        $Background = Get-RelativeLuminance $Palette['panel']
        foreach ($Name in 'ink', 'muted', 'link', 'accent') {
            $Palette[$Name] | Should -Not -BeNullOrEmpty
            $Foreground = Get-RelativeLuminance $Palette[$Name]
            $Contrast = ([math]::Max($Foreground, $Background) + 0.05) / ([math]::Min($Foreground, $Background) + 0.05)
            $Contrast | Should -BeGreaterOrEqual 4.5 -Because "$Theme code color $Name must be readable on the code panel"
        }
    }

    It 'versions the stylesheet by the Pages build revision while retaining the repository base URL' {
        $script:Layout | Should -Match ([regex]::Escape("{{ '/assets/css/style.css?v=' | append: site.github.build_revision | relative_url }}"))
        ([regex]::Matches($script:Layout, 'rel="stylesheet"')).Count | Should -Be 1
    }
}
