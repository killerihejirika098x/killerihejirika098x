$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$user = 'killerihejirika098x'
$outDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'assets'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

$headers = @{
    'Authorization' = "Bearer $env:GH_TOKEN"
    'User-Agent'    = 'profile-cards-generator'
    'Accept'        = 'application/vnd.github+json'
}

function Esc([string]$s) {
    if ($null -eq $s) { $s = '' }
    return $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
}

function Fmt([object]$n) {
    return '{0:N0}' -f $n
}

# ---- data via GraphQL ----
$query = @"
query {
  user(login: "$user") {
    followers { totalCount }
    repositories(first: 100, ownerAffiliations: OWNER) {
      totalCount
      nodes {
        name
        stargazerCount
        forkCount
        primaryLanguage { name color }
        languages(first: 10, orderBy: {field: SIZE, direction: DESC}) {
          edges { size node { name color } }
        }
      }
    }
  }
}
"@
$gqlBody = @{ query = $query } | ConvertTo-Json -Depth 10 -Compress
$gql = Invoke-RestMethod -Method Post -Uri 'https://api.github.com/graphql' -Headers $headers -Body $gqlBody -ContentType 'application/json'
$u = $gql.data.user

$stars = [long]0
$forks = [long]0
$langTotal = @{}
$langColor = @{}
foreach ($node in @($u.repositories.nodes)) {
    $stars += [long]$node.stargazerCount
    $forks += [long]$node.forkCount
    foreach ($edge in @($node.languages.edges)) {
        $ln = $edge.node.name
        $lc = $edge.node.color
        if ($langTotal.ContainsKey($ln)) { $langTotal[$ln] += [long]$edge.size } else { $langTotal[$ln] = [long]$edge.size }
        if ($lc) { $langColor[$ln] = $lc }
    }
}
$followers = [long]$u.followers.totalCount
$repoCount = [long]$u.repositories.totalCount

$langSum = 0
foreach ($v in $langTotal.Values) { $langSum += $v }
$langPairs = @($langTotal.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 5)

$font = 'Segoe UI,Roboto,Helvetica,Arial,sans-serif'
$mono = 'Fira Code,Consolas,Menlo,monospace'
$bg = '#0d1117'
$txt = '#a9fef7'
$dim = '#8b8fa3'
$accent = '#00d9ff'
$accent2 = '#fe428e'

# ---- svg builders ----
function Card-Open([string]$w, [string]$h) {
    "<svg xmlns='http://www.w3.org/2000/svg' width='$w' height='$h' viewBox='0 0 $w $h'>"
}

function Stat-Card {
    $rows = @(
        @('total stars earned', $stars, $accent),
        @('total forks', $forks, $accent2),
        @('public repositories', $repoCount, $accent2),
        @('followers', $followers, $accent)
    )
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine((Card-Open '380' '290'))
    [void]$sb.AppendLine("<rect x='0' y='0' width='380' height='290' rx='14' fill='$bg' stroke='#1f2430'/>")
    [void]$sb.AppendLine("<text x='28' y='52' font-family='$mono' font-size='17' font-weight='bold' fill='$accent2'>@killerihejirika098x</text>")
    [void]$sb.AppendLine("<text x='30' y='74' font-family='$font' font-size='10' fill='$dim'>system stats :: refreshed daily via workflow</text>")
    $y = 112
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $row = $rows[$i]
        [void]$sb.AppendLine("<circle cx='34' cy='$($y - 6)' r='4' fill='$($row[2])'/>")
        [void]$sb.AppendLine("<text x='48' y='$y' font-family='$font' font-size='13' fill='$dim'>$($row[0])</text>")
        [void]$sb.AppendLine("<text x='352' y='$y' text-anchor='end' font-family='$mono' font-size='15' font-weight='bold' fill='$txt'>$(Fmt $row[1])</text>")
        if ($i -lt $rows.Count - 1) {
            [void]$sb.AppendLine("<line x1='30' y1='$($y + 10)' x2='350' y2='$($y + 10)' stroke='#1b2130' stroke-width='1'/>")
        }
        $y += 29
    }
    [void]$sb.AppendLine('</svg>')
    return $sb.ToString()
}

function Lang-Card {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine((Card-Open '380' '250'))
    [void]$sb.AppendLine("<rect x='0' y='0' width='380' height='250' rx='14' fill='$bg' stroke='#1f2430'/>")
    [void]$sb.AppendLine("<text x='28' y='52' font-family='$mono' font-size='16' font-weight='bold' fill='$accent2'>Most Used Languages</text>")
    [void]$sb.AppendLine("<text x='30' y='72' font-family='$font' font-size='10' fill='$dim'>byte-weighted across public repos</text>")
    $y = 108
    foreach ($l in $langPairs) {
        $name = $l.Key
        $color = $langColor[$name]
        if (-not $color) { $color = '#8b949e' }
        [void]$sb.AppendLine("<circle cx='34' cy='$($y - 5)' r='5' fill='$color'/>")
        [void]$sb.AppendLine("<text x='48' y='$y' font-family='$font' font-size='13' fill='$txt'>$(Esc $name)</text>")
        [void]$sb.AppendLine("<text x='352' y='$y' text-anchor='end' font-family='$mono' font-size='12' fill='$accent'>$(Fmt ([long]$l.Value)) B</text>")
        $barW = [math]::Max(2, [math]::Round(320.0 * [long]$l.Value / [math]::Max($langSum, 1)))
        [void]$sb.AppendLine("<rect x='30' y='$($y + 8)' width='320' height='6' rx='3' fill='#151b27'/>")
        [void]$sb.AppendLine("<rect x='30' y='$($y + 8)' width='$barW' height='6' rx='3' fill='$color'/>")
        $y += 38
    }
    [void]$sb.AppendLine('</svg>')
    return $sb.ToString()
}

function Pin-Card($repoName) {
    $node = $null
    foreach ($n in @($u.repositories.nodes)) {
        if ($n.name -eq $repoName) { $node = $n; break }
    }
    if ($null -eq $node) {
        return "<svg xmlns='http://www.w3.org/2000/svg' width='340' height='168'><rect width='340' height='168' rx='14' fill='#141321'/><text x='22' y='46' font-family='$mono' font-size='14' fill='$accent2'>build$repoName</text><text x='22' y='78' font-family='$font' font-size='11' fill='$dim'>repo unavailable</text></svg>"
    }
    $lang = 'Unknown'
    $color = '#8b949e'
    if ($node.primaryLanguage) {
        $lang = $node.primaryLanguage.name
        if ($node.primaryLanguage.color) { $color = $node.primaryLanguage.color }
    }
    $desc = [string]$node.description
    if (-not $desc) { $desc = 'automation module ~ Node.js runtime' }
    if ($desc.Length -gt 46) { $desc = $desc.Substring(0, 46).TrimEnd() + '...' }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine((Card-Open '340' '168'))
    [void]$sb.AppendLine("<rect x='0' y='0' width='340' height='168' rx='14' fill='#141321' stroke='#fe428e' stroke-opacity='0.45'/>")
    [void]$sb.AppendLine("<text x='22' y='46' font-family='$mono' font-size='14' font-weight='bold' fill='$accent2'>&gt; $(Esc $repoName)</text>")
    [void]$sb.AppendLine("<text x='22' y='78' font-family='$font' font-size='11' fill='$dim'>$(Esc $desc)</text>")
    [void]$sb.AppendLine("<circle cx='28' cy='122' r='5' fill='$color'/>")
    [void]$sb.AppendLine("<text x='40' y='127' font-family='$font' font-size='12' fill='$txt'>$(Esc $lang)</text>")
    [void]$sb.AppendLine("<text x='168' y='127' font-family='$mono' font-size='12' fill='$txt'>* $(Fmt ([long]$node.stargazerCount))</text>")
    [void]$sb.AppendLine("<text x='228' y='127' font-family='$mono' font-size='12' fill='$txt'>^ $(Fmt ([long]$node.forkCount))</text>")
    [void]$sb.AppendLine("<text x='22' y='152' font-family='$font' font-size='9' fill='#3d4457'>// pinned build</text>")
    [void]$sb.AppendLine('</svg>')
    return $sb.ToString()
}

function Achievements-Card {
    $chips = @(
        @('STARS', $stars, $accent),
        @('FORKS', $forks, $accent2),
        @('REPOS', $repoCount, $accent),
        @('FOLLOWERS', $followers, $accent2)
    )
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine((Card-Open '620' '92'))
    $x = 14
    foreach ($c in $chips) {
        $fill = $accent
        if ($c[2] -eq $accent2) { $fill = $accent2 }
        [void]$sb.AppendLine("<rect x='$x' y='22' width='140' height='48' rx='10' fill='#141321' stroke='$fill' stroke-opacity='0.6'/>")
        [void]$sb.AppendLine("<text x='$($x + 70)' y='42' text-anchor='middle' font-family='$mono' font-size='10' letter-spacing='2' fill='$dim'>$($c[0])</text>")
        [void]$sb.AppendLine("<text x='$($x + 70)' y='62' text-anchor='middle' font-family='$mono' font-size='15' font-weight='bold' fill='$fill'>$(Fmt $c[1])</text>")
        $x += 148
    }
    [void]$sb.AppendLine('</svg>')
    return $sb.ToString()
}

# ---- write files ----
Set-Content -Path (Join-Path $outDir 'stats.svg') -Value (Stat-Card) -Encoding UTF8
Set-Content -Path (Join-Path $outDir 'langs.svg') -Value (Lang-Card) -Encoding UTF8
Set-Content -Path (Join-Path $outDir 'achievements.svg') -Value (Achievements-Card) -Encoding UTF8
foreach ($pinned in @('PATRON-MD3', 'Knightbot-MD', 'IMMU-MD')) {
    Set-Content -Path (Join-Path $outDir "pin-$pinned.svg") -Value (Pin-Card $pinned) -Encoding UTF8
}

Write-Output "cards generated: stats, langs, achievements + 3 pins -> $outDir"
