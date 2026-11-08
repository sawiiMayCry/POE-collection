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
$day = $now.ToString('yyyy-MM-dd')
$leaguePart = $League -replace '[^a-zA-Z0-9_-]', '_'

if ($SkipIfCollectedToday) {
    # Only a pair with the same collection timestamp counts as complete.
    foreach ($file in Get-ChildItem -LiteralPath $OutputDir -Filter "${day}_*_${leaguePart}_currency.json" -File) {
        $pairedName = $file.Name -replace '_currency\.json$', '_unique_accessories.json'
        if (Test-Path -LiteralPath (Join-Path $OutputDir $pairedName) -PathType Leaf) {
            Write-Output "A complete collection already exists for $day (UTC)."
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
