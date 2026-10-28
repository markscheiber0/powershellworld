# retry-loop.ps1 - repeats named tap zones every few minutes until too many failures in a row.
# Save in the same folder as ldagent.ps1 and allowed-taps.json.
# Usage:  .\retry-loop.ps1   (defaults to giveaway_box then enter_giveaway)
param(
    # Note: not named $Zones, because ldagent.ps1 uses $script:zones and PowerShell names are case-insensitive.
    [string[]]$Steps = @("giveaway_box", "enter_giveaway"),
    [int]$WaitMinutes = 5,
    [int]$MaxFailures = 3,  # stop after this many failed cycles in a row
    [int]$Index = 0,
    [int]$MaxCycles = 0     # 0 means no cap on total cycles
)

$stepList = @($Steps)

# Load the functions from ldagent.ps1 without starting the chat.
. (Join-Path $PSScriptRoot "ldagent.ps1") -Index $Index -MaxTaps $stepList.Count

# Make sure every requested step exists as a zone before starting.
$knownNames = @($script:zones | ForEach-Object { $_.name })
$missing = @($stepList | Where-Object { $knownNames -notcontains $_ })
if ($missing.Count -gt 0) {
    Write-Host "Unknown zone(s): $($missing -join ', ')"
    Write-Host "Zones in allowed-taps.json: $($knownNames -join ', ')"
    return
}

$cycle = 0
$failStreak = 0
while ($true) {
    $cycle++
    Write-Host ("[{0}] Cycle {1}" -f (Get-Date -Format "HH:mm:ss"), $cycle)

    # Reset the per-request limits that ldagent.ps1 normally resets for each chat message.
    $script:tapped = @()
    $failed = $false

    foreach ($step in $stepList) {
        # The tap gate requires the "user message" to name the zone, so set it here.
        $script:userText = "tap $step"
        try { $result = Invoke-Tool "tap_zone" ([pscustomobject]@{ name = $step }) }
        catch { $result = "ERROR: $($_.Exception.Message)" }

        Write-Host ("  {0}: {1}" -f $step, ($result -split "`n")[0])
        if ($result -notlike "Tapped zone*") {
            Write-Log "retry-loop: $step failed on cycle $cycle ($result)"
            $failed = $true
            break
        }
        Start-Sleep -Seconds 3
    }

    if ($failed) {
        $failStreak++
        Write-Host "  Failed $failStreak of $MaxFailures in a row."
        if ($failStreak -ge $MaxFailures) {
            Write-Host "Stopping after $MaxFailures failures in a row."
            Write-Log "retry-loop stopped after $MaxFailures failures in a row (cycle $cycle)"
            break
        }
    }
    else {
        $failStreak = 0
        Write-Host "  Both steps worked."
    }

    if ($MaxCycles -gt 0 -and $cycle -ge $MaxCycles) { Write-Host "Reached $MaxCycles cycles. Done."; break }

    Write-Host "  Waiting $WaitMinutes minutes (Ctrl+C to stop)..."
    Start-Sleep -Seconds ($WaitMinutes * 60)
}
