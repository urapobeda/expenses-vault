param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$dailyPath = Join-Path $Root 'Daily'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$counts = @{ 'важно' = 0; 'неважно' = 0; 'требует уточнения' = 0 }

function Get-Importance([string]$block) {
    $text = $block.ToLowerInvariant()

    if ($text -match '\*\*категория:\*\*\s*(транспорт|образование|здоровье|медицина|семейная помощь|семья|долги)' -or
        $text -match 'лекарств|экзамен sat|продукты домой|продукты для дома|мясо домой|маме|родител|брату|возврат долга|укоротить штаны|сахарозаменител' -or
        $text -match 'cola zero и хлеб|два майонеза и жвачка' -or
        $text -match '\*\*подкатегория:\*\*\s*(хлеб и выпечка|яйца|мясо)') {
        return 'важно'
    }

    return 'неважно'
}

Get-ChildItem -LiteralPath $dailyPath -Filter '*.md' | Sort-Object Name | ForEach-Object {
    $relativePath = 'Daily/' + $_.Name
    try {
        $content = [System.IO.File]::ReadAllText($_.FullName)
    }
    catch {
        $content = (& git -C $Root show "HEAD:$relativePath" 2>$null) -join "`n"
        if (-not $content) {
            throw "Не удалось прочитать $relativePath"
        }
        $content += "`n"
    }

    $changed = $false
    $updated = [regex]::Replace($content, '(?ms)^### .*?(?=^### |\z)', {
        param($match)
        $block = $match.Value
        if ($block -notmatch '(?m)^- \*\*Тип:\*\* expense\s*$' -or
            $block -match '(?m)^- \*\*Важность:\*\*') {
            return $block
        }

        $importance = Get-Importance $block
        $script:counts[$importance]++
        $script:changed = $true
        return [regex]::Replace(
            $block,
            '(?m)(^- \*\*Счёт:\*\*[^\r\n]+\r?\n)',
            "`$1- **Важность:** $importance`n",
            1
        )
    })

    if ($changed) {
        [System.IO.File]::WriteAllText($_.FullName, $updated, $utf8NoBom)
    }
}

[pscustomobject]@{
    Important = $counts['важно']
    Unimportant = $counts['неважно']
    NeedsClarification = $counts['требует уточнения']
} | ConvertTo-Json
