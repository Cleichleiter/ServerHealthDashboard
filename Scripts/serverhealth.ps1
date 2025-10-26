[CmdletBinding()]
param(
    [string]$ConfigFile       = ".\servers.json",
    [string]$HtmlOut          = ".\Output\Report.html",
    [string]$CsvOut           = ".\Output\Report.csv",
    [string]$JsonOut          = ".\Output\Report.json",
    [string]$LogFile          = ".\Output\ServerHealth.log",
    [int]   $WarnDiskFreePct  = 15,   # warn when free% < 15
    [int]   $CritDiskFreePct  = 5     # critical when free% < 5
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts`t$Message" | Out-File -FilePath $LogFile -Append -Encoding utf8
}

function Test-IsLocal {
    param([string]$Name)
    $up = ($Name ?? "").ToUpper()
    return ($up -eq "LOCALHOST" -or $up -eq $env:COMPUTERNAME.ToUpper())
}

function Get-CimLocalOrRemote {
    param(
        [string]$ClassName,
        [string]$ComputerName,
        [string]$Filter
    )
    if (Test-IsLocal $ComputerName) {
        if ($Filter) { Get-CimInstance -ClassName $ClassName -Filter $Filter }
        else         { Get-CimInstance -ClassName $ClassName }
    } else {
        if ($Filter) { Get-CimInstance -ClassName $ClassName -ComputerName $ComputerName -Filter $Filter }
        else         { Get-CimInstance -ClassName $ClassName -ComputerName $ComputerName }
    }
}

# --- Read config / prepare output dir ---
if (-not (Test-Path $ConfigFile)) { throw "Config file not found: $ConfigFile" }
$cfg      = Get-Content $ConfigFile -Raw | ConvertFrom-Json
$servers  = $cfg.Servers
$services = $cfg.ServicesToCheck
$title    = $cfg.ReportTitle
$outDir   = Split-Path $HtmlOut
if (-not (Test-Path $outDir)) { New-Item $outDir -ItemType Directory | Out-Null }

Write-Verbose "Collecting data for: $($servers -join ', ')" -Verbose
Write-Log    "Collecting data for: $($servers -join ', ')"

$results = foreach ($s in $servers) {
    try {
        # --- Ping / latency ---
        $pingMs = $null
        $reachable = $false
        try {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $ok = Test-Connection -ComputerName $s -Count 1 -Quiet -ErrorAction Stop
            $sw.Stop()
            $reachable = [bool]$ok
            if ($ok) { $pingMs = [int]$sw.Elapsed.TotalMilliseconds }
        } catch {
            $reachable = $false
        }

        # --- OS & uptime ---
        $os = Get-CimLocalOrRemote -ClassName Win32_OperatingSystem -ComputerName $s
        $uptimeDays = [int]((Get-Date) - $os.LastBootUpTime).TotalDays

        # --- Disks ---
        $disksRaw = Get-CimLocalOrRemote -ClassName Win32_LogicalDisk -ComputerName $s -Filter "DriveType=3"
        $disks = $disksRaw | ForEach-Object {
            $freeGB  = [math]::Round($_.FreeSpace/1GB,2)
            $totalGB = [math]::Round($_.Size/1GB,2)
            $pctFree = if ($_.Size) { [math]::Round(($_.FreeSpace / $_.Size) * 100, 1) } else { 0 }
            $level   = if ($pctFree -lt $CritDiskFreePct) { "crit" }
                       elseif ($pctFree -lt $WarnDiskFreePct) { "warn" }
                       else { "ok" }
            [pscustomobject]@{
                DeviceID = $_.DeviceID
                FreeGB   = $freeGB
                TotalGB  = $totalGB
                FreePct  = $pctFree
                Level    = $level
            }
        }

        # --- Services ---
        $svc = foreach ($name in $services) {
            if (Test-IsLocal $s) {
                $o = Get-Service -Name $name -ErrorAction SilentlyContinue
            } else {
                $o = Get-Service -ComputerName $s -Name $name -ErrorAction SilentlyContinue
            }
            $status = if ($o) { [string]$o.Status } else { "NotFound" }
            $level  = switch ($status) {
                "Running" { "ok" }
                "Stopped" { "crit" }
                default   { "warn" }  # NotFound or others
            }
            [pscustomobject]@{ Service=$name; Status=$status; Level=$level }
        }

        # Summary counts
        $diskCrit = ($disks | Where-Object Level -eq 'crit').Count
        $diskWarn = ($disks | Where-Object Level -eq 'warn').Count
        $svcCrit  = ($svc   | Where-Object Level -eq 'crit').Count
        $svcWarn  = ($svc   | Where-Object Level -eq 'warn').Count
        $minPct   = ($disks.FreePct | Measure-Object -Minimum).Minimum

        [pscustomobject]@{
            Server        = $s
            Reachable     = $reachable
            PingMs        = $pingMs
            OS            = $os.Caption
            UptimeDays    = $uptimeDays
            MinDiskFreePct= $minPct
            DiskWarnCount = $diskWarn
            DiskCritCount = $diskCrit
            SvcWarnCount  = $svcWarn
            SvcCritCount  = $svcCrit
            Disks         = $disks
            Services      = $svc
            Collected     = Get-Date
        }
    }
    catch {
        Write-Log "Failed on ${s}: $($_.Exception.Message)"
        [pscustomobject]@{
            Server        = $s
            Reachable     = $false
            PingMs        = $null
            OS            = "Error"
            UptimeDays    = 0
            MinDiskFreePct= $null
            DiskWarnCount = $null
            DiskCritCount = $null
            SvcWarnCount  = $null
            SvcCritCount  = $null
            Disks         = @()
            Services      = @()
            Collected     = Get-Date
        }
    }
}

# --- Save CSV + JSON ---
$results |
    Select-Object Server,Reachable,PingMs,OS,UptimeDays,MinDiskFreePct,DiskWarnCount,DiskCritCount,SvcWarnCount,SvcCritCount,Collected |
    Export-Csv -NoTypeInformation -Path $CsvOut

($results | ConvertTo-Json -Depth 6) | Out-File -FilePath $JsonOut -Encoding utf8

# --- Build HTML with CSS + details ---
$css = @"
<style>
body { font-family: Segoe UI, Arial, sans-serif; margin: 24px; color:#111; }
h1 { margin-bottom: 4px; }
small { color:#555; }
table { border-collapse: collapse; width: 100%; margin-top: 12px; }
th, td { border: 1px solid #e5e7eb; padding: 8px 10px; text-align: left; }
th { background:#f3f4f6; font-weight:600; }
.badge { padding:2px 8px; border-radius:999px; font-size:12px; font-weight:600; }
.ok   { background:#e8f5e9; color:#1b5e20; }
.warn { background:#fff8e1; color:#e65100; }
.crit { background:#ffebee; color:#b71c1c; }
.dim  { color:#6b7280; }
details { margin: 10px 0 22px 0; }
summary { cursor:pointer; font-weight:600; }
.kv { font-size: 13px; color:#6b7280; }
.right { text-align:right; }
</style>
"@

# Summary table rows
$summaryRows = $results | ForEach-Object {
    $reach = if ($_.Reachable) { '<span class="badge ok">Reachable</span>' } else { '<span class="badge crit">No ping</span>' }
    $minPct = if ($_.MinDiskFreePct -ne $null) { [string]$_.MinDiskFreePct + '%' } else { '<span class="dim">n/a</span>' }
    @"
<tr>
  <td>$($_.Server)</td>
  <td>$reach</td>
  <td class="right">$($_.PingMs ?? '—')</td>
  <td>$($_.OS)</td>
  <td class="right">$($_.UptimeDays)</td>
  <td class="right">$minPct</td>
  <td class="right"><span class="badge warn">$($_.DiskWarnCount)</span></td>
  <td class="right"><span class="badge crit">$($_.DiskCritCount)</span></td>
  <td class="right"><span class="badge warn">$($_.SvcWarnCount)</span></td>
  <td class="right"><span class="badge crit">$($_.SvcCritCount)</span></td>
  <td>$($_.Collected)</td>
</tr>
"@
} | Out-String

# Per-server details
$detailBlocks = foreach ($r in $results) {
    $diskRows = if ($r.Disks.Count -gt 0) {
        ($r.Disks | ForEach-Object {
            $cls = $_.Level
            @"
<tr>
  <td>$($_.DeviceID)</td>
  <td class="right">$($_.FreeGB)</td>
  <td class="right">$($_.TotalGB)</td>
  <td class="right"><span class="badge $cls">$($_.FreePct)%</span></td>
</tr>
"@
        }) -join "`n"
    } else {
        '<tr><td colspan="4" class="dim">No disk data</td></tr>'
    }

    $svcRows = if ($r.Services.Count -gt 0) {
        ($r.Services | ForEach-Object {
            $cls = $_.Level
            @"
<tr>
  <td>$($_.Service)</td>
  <td><span class="badge $cls">$($_.Status)</span></td>
</tr>
"@
        }) -join "`n"
    } else {
        '<tr><td colspan="2" class="dim">No service data</td></tr>'
    }

    @"
<details>
  <summary>$($r.Server) &nbsp;<span class="kv">(OS: $($r.OS), Uptime: $($r.UptimeDays)d)</span></summary>
  <table>
    <thead>
      <tr><th colspan="4">Disks</th></tr>
      <tr><th>Drive</th><th class="right">Free (GB)</th><th class="right">Total (GB)</th><th class="right">Free %</th></tr>
    </thead>
    <tbody>
      $diskRows
    </tbody>
  </table>
  <table>
    <thead>
      <tr><th colspan="2">Services</th></tr>
      <tr><th>Name</th><th>Status</th></tr>
    </thead>
    <tbody>
      $svcRows
    </tbody>
  </table>
</details>
"@
}

$detailsHtml = ($detailBlocks -join "`n")

# Final HTML
$generated = Get-Date
$html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8" />
<title>$title</title>
$css
</head>
<body>
  <h1>$title</h1>
  <small>Generated: $generated</small>

  <table>
    <thead>
      <tr>
        <th>Server</th>
        <th>Ping</th>
        <th class="right">Latency (ms)</th>
        <th>OS</th>
        <th class="right">Uptime (days)</th>
        <th class="right">Min disk free %</th>
        <th class="right">Disk WARN</th>
        <th class="right">Disk CRIT</th>
        <th class="right">Svc WARN</th>
        <th class="right">Svc CRIT</th>
        <th>Collected</th>
      </tr>
    </thead>
    <tbody>
      $summaryRows
    </tbody>
  </table>

  <h2 style="margin-top:28px;">Details</h2>
  $detailsHtml
</body>
</html>
"@

$html | Out-File -FilePath $HtmlOut -Encoding utf8
Write-Log "Done: HTML=$HtmlOut CSV=$CsvOut JSON=$JsonOut"
"HTML: $HtmlOut`nCSV : $CsvOut`nJSON: $JsonOut"
