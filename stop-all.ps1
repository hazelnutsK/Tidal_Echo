# Tidal Echo stop-all: relay(:3011) + api_loop(:3020) + cloudflared
# Does NOT kill CC - close the CC terminal window yourself.
# ASCII only: PS 5.1 reads BOM-less .ps1 as GBK and chokes on UTF-8 Chinese.

foreach ($port in 3011, 3020) {
    try {
        $conns = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction Stop
        foreach ($p in ($conns.OwningProcess | Sort-Object -Unique)) {
            $proc = Get-Process -Id $p -ErrorAction SilentlyContinue
            if ($proc) {
                Write-Host ("stopped {0} (pid {1}, port {2})" -f $proc.ProcessName, $p, $port)
                Stop-Process -Id $p -Force
            }
        }
    } catch { Write-Host "port $port : nothing listening" }
}

$cf = Get-Process cloudflared -ErrorAction SilentlyContinue
if ($cf) { $cf | Stop-Process -Force; Write-Host "cloudflared stopped" }
else { Write-Host "cloudflared not running" }

Write-Host ""
Write-Host "Done. Close the CC window manually, then run start-all."
