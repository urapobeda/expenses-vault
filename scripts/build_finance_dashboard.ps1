param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'sites\finance-dashboard\dist\data.js')
)

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Get-Field([string]$block, [string]$name) {
    $pattern = '(?m)^- \*\*' + [regex]::Escape($name) + ':\*\*\s*(.+?)\s*$'
    $match = [regex]::Match($block, $pattern)
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    return $null
}

function Convert-Amount([string]$value) {
    if (-not $value) { return 0.0 }
    $clean = $value -replace '[^0-9,\.\-+]', ''
    $clean = $clean -replace ',', '.'
    return [double]::Parse($clean, [Globalization.CultureInfo]::InvariantCulture)
}

$transactions = @()
Get-ChildItem -LiteralPath (Join-Path $Root 'Daily') -Filter '*.md' | Sort-Object Name | ForEach-Object {
    $date = $_.BaseName
    $content = [IO.File]::ReadAllText($_.FullName)
    $parts = [regex]::Split($content, '(?m)^### ')

    foreach ($part in $parts | Select-Object -Skip 1) {
        $lines = $part -split "`r?`n", 2
        $title = ($lines[0] -replace '^\d{2}:\d{2}\s+—\s+', '').Trim()
        $type = Get-Field $part 'Тип'
        if (-not $type) { continue }

        $rawAmount = Get-Field $part 'Сумма'
        if ($type -eq 'adjustment') { $rawAmount = Get-Field $part 'Изменение' }
        $currencyMatch = [regex]::Match([string]$rawAmount, '(RUB|KZT|USD|EUR)')
        $currency = if ($currencyMatch.Success) { $currencyMatch.Value } else { 'KZT' }

        $transactions += [ordered]@{
            date = $date
            title = $title
            type = $type
            amount = Convert-Amount $rawAmount
            currency = $currency
            account = Get-Field $part 'Счёт'
            fromAccount = Get-Field $part 'Со счёта'
            toAccount = Get-Field $part 'На счёт'
            importance = Get-Field $part 'Важность'
            category = Get-Field $part 'Категория'
            subcategory = Get-Field $part 'Подкатегория'
            counterparty = Get-Field $part 'Магазин / получатель / источник'
            description = Get-Field $part 'Описание'
            reason = Get-Field $part 'Причина'
        }
    }
}

$accounts = @()
$accountsPath = Join-Path $Root 'Accounts.md'
Get-Content -LiteralPath $accountsPath | ForEach-Object {
    if ($_ -notmatch '^\|[^-].*\|$' -or $_ -match '^\|\s*Название счёта') { return }
    $cells = $_.Trim('|').Split('|') | ForEach-Object { $_.Trim() }
    if ($cells.Count -lt 6) { return }
    $accounts += [ordered]@{
        name = $cells[0]
        type = $cells[1]
        currency = $cells[2]
        initialBalance = Convert-Amount $cells[3]
        initialDate = ($cells[4] -split ' ')[0]
        note = $cells[5]
        balance = Convert-Amount $cells[3]
    }
}

foreach ($transaction in $transactions) {
    foreach ($account in $accounts) {
        if ($transaction.date -lt $account.initialDate) { continue }
        if ($transaction.type -eq 'income' -and $transaction.account -eq $account.name) {
            $account.balance += $transaction.amount
        }
        elseif ($transaction.type -eq 'expense' -and $transaction.account -eq $account.name) {
            $account.balance -= $transaction.amount
        }
        elseif ($transaction.type -eq 'transfer') {
            if ($transaction.fromAccount -eq $account.name) { $account.balance -= $transaction.amount }
            if ($transaction.toAccount -eq $account.name) { $account.balance += $transaction.amount }
        }
        elseif ($transaction.type -eq 'adjustment' -and $transaction.account -eq $account.name) {
            $account.balance += $transaction.amount
        }
    }
}

$payload = [ordered]@{
    generatedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
    currency = 'KZT'
    transactions = $transactions
    accounts = $accounts
}

$directory = Split-Path -Parent $OutputPath
[IO.Directory]::CreateDirectory($directory) | Out-Null
$json = $payload | ConvertTo-Json -Depth 8 -Compress
[IO.File]::WriteAllText($OutputPath, "window.FINANCE_DATA = $json;`n", $utf8NoBom)

[pscustomobject]@{
    Transactions = $transactions.Count
    Income = ($transactions | Where-Object type -eq 'income').Count
    Expenses = ($transactions | Where-Object type -eq 'expense').Count
    Output = $OutputPath
} | ConvertTo-Json
