# Tidal Echo start-all: relay backend + cloudflared tunnel + api_loop + CC (channel)
# Run via qidong.cmd / right-click "Run with PowerShell".
# CC will show a "WARNING: Loading development channels" dialog -> press Enter once.
# ASCII only: PS 5.1 reads BOM-less .ps1 as GBK and chokes on UTF-8 Chinese.

$repo = $PSScriptRoot
if (-not $repo) { $repo = 'C:\Users\sxc\Tidal_Echo' }

# 1) relay backend (minimized window; closing the window stops it)
Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $repo 'backend\start.ps1') -WindowStyle Minimized

# 2) cloudflared tunnel
Start-Process cloudflared -ArgumentList 'tunnel','run','tidal-echo' -WindowStyle Minimized

# 3) api_loop (API body; phone can switch Desktop/API in settings)
Start-Process (Join-Path $repo 'backend\.venv\Scripts\python.exe') -ArgumentList (Join-Path $repo 'examples\api_loop.py') -WindowStyle Minimized -WorkingDirectory (Join-Path $repo 'examples')

# 4) wait for relay
foreach ($i in 1..15) {
    try { Invoke-RestMethod http://127.0.0.1:3011/relay/healthz -TimeoutSec 2 | Out-Null; break }
    catch { Start-Sleep -Seconds 1 }
}

# 5) CC in foreground with the companion channel (press Enter at the dialog)
Set-Location $env:USERPROFILE
claude --dangerously-skip-permissions --dangerously-load-development-channels server:companion
