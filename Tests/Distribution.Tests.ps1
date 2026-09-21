BeforeAll {
    $script:DistributionRoot = Split-Path -Parent $PSScriptRoot
    $script:GistPattern = 'https://gist\.github\.com/vartaxe/[a-f0-9]{32}(?![a-f0-9])'
}

Describe 'Standalone script distribution contract' {
    It 'uses one matching owner-hosted gist across the README, landing page, and distribution guide' {
        $Expected = $null
        foreach ($Relative in 'README.md', 'index.md', 'docs\distribution.md') {
            $Content = Get-Content -LiteralPath (Join-Path $script:DistributionRoot $Relative) -Raw
            $Links = @([regex]::Matches($Content, $script:GistPattern).Value | Sort-Object -Unique)
            $Links.Count | Should -Be 1
            if ($null -eq $Expected) {
                $Expected = $Links[0]
            }
            $Links[0] | Should -BeExactly $Expected
        }
    }

    It 'retains the software license and explains snapshot checksums without a remote execution shortcut' {
        $License = Get-Content -LiteralPath (Join-Path $script:DistributionRoot 'LICENSE') -Raw
        $License | Should -Match '^MIT License'
        $Guide = Get-Content -LiteralPath (Join-Path $script:DistributionRoot 'docs\distribution.md') -Raw
        foreach ($Required in 'SHA256SUMS.txt', 'LICENSE', 'snapshot', 'task sequence') {
            $Guide | Should -Match ([regex]::Escape($Required))
        }
        $Guide | Should -Not -Match '(?i)\biex\b|Invoke-Expression'
    }
}
