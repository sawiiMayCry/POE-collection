param(
    [string]$OutputDir = (Join-Path $PSScriptRoot '../data'),
    [string]$League = 'Allflame',
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Contact,
    [switch]$SkipIfCollectedToday
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Contact)) { throw 'Contact is required.' }
if ([string]::IsNullOrWhiteSpace($League)) { throw 'League is required.' }

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$now = [DateTime]::UtcNow
$stamp = $now.ToString("yyyy-MM-dd_HHmmss'Z'")
$leaguePart = $League -replace '[^a-zA-Z0-9_-]', '_'

if ($SkipIfCollectedToday) {
    # One collection per evening window, including retries delayed past midnight.
    # Compare actual UTC timestamps; preserve those timestamps in the filenames.
    $zagreb = [TimeZoneInfo]::FindSystemTimeZoneById('Europe/Zagreb')
    $localNow = [TimeZoneInfo]::ConvertTimeFromUtc($now, $zagreb)
    $windowStartLocal = $localNow.Date.AddHours(21).AddMinutes(30)
    if ($localNow -lt $windowStartLocal) { $windowStartLocal = $windowStartLocal.AddDays(-1) }
    $windowStartUtc = [TimeZoneInfo]::ConvertTimeToUtc($windowStartLocal, $zagreb)
    $windowEndUtc = [TimeZoneInfo]::ConvertTimeToUtc($windowStartLocal.AddDays(1), $zagreb)
    foreach ($file in Get-ChildItem -LiteralPath $OutputDir -Filter "*_${leaguePart}_currency.json" -File) {
        if ($file.Name -notmatch '^(\d{4}-\d{2}-\d{2}_\d{6}Z)_') { continue }
        $fileUtc = [DateTime]::MinValue
        $validTime = [DateTime]::TryParseExact(
            $Matches[1], "yyyy-MM-dd_HHmmss'Z'", [Globalization.CultureInfo]::InvariantCulture,
            ([Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal),
            [ref]$fileUtc
        )
        if (-not $validTime -or $fileUtc -lt $windowStartUtc -or $fileUtc -ge $windowEndUtc) { continue }
        $pairedName = $file.Name -replace '_currency\.json$', '_unique_accessories.json'
        if (Test-Path -LiteralPath (Join-Path $OutputDir $pairedName) -PathType Leaf) {
            Write-Output "A complete collection already exists for the window starting $($windowStartLocal.ToString('yyyy-MM-dd HH:mm')) Europe/Zagreb."
            return
        }
    }
}

$encodedLeague = [uri]::EscapeDataString($League)
$headers = @{ 'User-Agent' = "PI-Allflame-Collector/1.0 (contact: $Contact)" }
$requests = @(
    @{
        Name = 'currency'
        Url = "https://poe.ninja/poe1/api/economy/stash/current/currency/overview?league=$encodedLeague&type=Currency"
    },
    @{
        Name = 'unique_accessories'
        Url = "https://poe.ninja/poe1/api/economy/stash/current/item/overview?league=$encodedLeague&type=UniqueAccessory"
    }
)

# Fetch and validate both responses before saving either file.
$downloads = foreach ($request in $requests) {
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $response = Invoke-WebRequest -Uri $request.Url -Headers $headers -TimeoutSec 45 -UseBasicParsing
            $data = $response.Content | ConvertFrom-Json
            if ($null -eq $data.lines -or @($data.lines).Count -eq 0) {
                throw "No data lines returned for $($request.Name)."
            }
            [pscustomobject]@{
                Name = $request.Name
                Content = $response.Content
                Count = @($data.lines).Count
            }
            break
        }
        catch {
            if ($attempt -eq 3) { throw }
            Write-Warning "Request $($request.Name) failed (attempt $attempt/3); retrying."
            Start-Sleep -Seconds (5 * $attempt)
        }
    }
}

foreach ($download in $downloads) {
    $name = "${stamp}_${leaguePart}_$($download.Name).json"
    $path = Join-Path $OutputDir $name
    [System.IO.File]::WriteAllText($path, $download.Content, [System.Text.UTF8Encoding]::new($false))
    Write-Output "$path ($($download.Count) lines)"
}
