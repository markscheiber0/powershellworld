# ldagent.ps1 - lets a local LM Studio model operate one LDPlayer phone through a small set of tools.
# Needs: LM Studio local server running with a model loaded, LDPlayer ADB debugging on.
param(
    [int]$Index = 0,
    [string]$Api = "http://localhost:1234/v1",
    [int]$MaxToolCalls = 10,
    [int]$MaxTaps = 2
)

$ld = "C:\LDPlayer\LDPlayer14\ldconsole.exe"
$work = "C:\Emulator\agent"
New-Item -ItemType Directory -Force $work | Out-Null
$log = Join-Path $PSScriptRoot "actions.log"
$script:elements = @()
$script:pwFocused = $false
$script:tapped = @()
# Only these named spots may be tapped; the model never supplies coordinates.
$script:zones = @(([IO.File]::ReadAllText((Join-Path $PSScriptRoot "allowed-taps.json")) | ConvertFrom-Json).zones)

function Write-Log($m) { "{0}  {1}" -f (Get-Date -Format s), $m | Add-Content $log }
function Adb($cmd) { & $ld adb --index $Index --command $cmd 2>&1 | Out-String }

function Read-Screen {
    $f = Join-Path $work "ui.xml"
    Remove-Item $f -ErrorAction SilentlyContinue
    Adb "shell uiautomator dump /sdcard/ui.xml" | Out-Null
    Adb "pull /sdcard/ui.xml $f" | Out-Null
    if (-not (Test-Path $f)) { return "ERROR: could not read the screen (it may be playing video). Wait and try again, or use screenshot." }
    $xml = [xml](Get-Content $f -Raw)
    $script:pwFocused = $false
    $script:elements = @()
    $id = 0
    foreach ($n in $xml.SelectNodes("//node")) {
        if ($n.password -eq "true" -and $n.focused -eq "true") { $script:pwFocused = $true }
        $label = if ($n.text) { $n.text } elseif ($n.'content-desc') { $n.'content-desc' } else { "" }
        if (-not $label -and $n.clickable -ne "true") { continue }
        if ($n.bounds -notmatch '\[(\d+),(\d+)\]\[(\d+),(\d+)\]') { continue }
        $x = [int](([int]$matches[1] + [int]$matches[3]) / 2)
        $y = [int](([int]$matches[2] + [int]$matches[4]) / 2)
        $id++
        if ($label.Length -gt 60) { $label = $label.Substring(0, 60) }
        $script:elements += [pscustomobject]@{ id = $id; label = $label; x = $x; y = $y; tappable = ($n.clickable -eq "true") }
    }
    if (-not $script:elements) { return "Screen has no readable elements. Use screenshot or try again." }
    $lines = $script:elements | Select-Object -First 45 | ForEach-Object {
        "{0} | {1} | ({2},{3}){4}" -f $_.id, $_.label, $_.x, $_.y, $(if ($_.tappable) { " tappable" } else { "" })
    }
    return ($lines -join "`n")
}

function Tap($x, $y) {
    if ($x -lt 0 -or $x -gt 720 -or $y -lt 0 -or $y -gt 1280) { throw "Coordinates outside the 720x1280 screen." }
    Adb "shell input tap $x $y" | Out-Null
}

function Invoke-Tool($name, $a) {
    Write-Log "$name $($a | ConvertTo-Json -Compress)"
    $exposed = @("list_screen", "list_zones", "tap_zone", "screenshot", "phone_status", "wait")
    if ($exposed -notcontains $name) { return "REFUSED: tool '$name' is not allowed." }
    Start-Sleep -Seconds 1
    switch ($name) {
        "list_screen" { return Read-Screen }
        "list_zones" { return (($script:zones | ForEach-Object { "$($_.name): $($_.description)" }) -join "`n") }
        "tap_zone" {
            $z = $script:zones | Where-Object { $_.name -eq $a.name } | Select-Object -First 1
            if (-not $z) { return "REFUSED: unknown zone. Allowed zones: $(($script:zones.name) -join ', ')." }
            # Gate in code: the user's own message must name this zone (underscore or space), whatever the model decides.
            if ($script:userText -notmatch ($z.name -replace '_', '[ _]')) { return "REFUSED: the user did not ask for zone '$($z.name)'. Do not tap. Tell the user." }
            if ($script:tapped -contains $z.name) { return "REFUSED: zone '$($z.name)' was already tapped for this request. Report to the user and stop." }
            if ($script:tapped.Count -ge $MaxTaps) { return "REFUSED: tap limit ($MaxTaps) reached for this request. Report to the user and stop." }
            $tx = $z.x; $ty = $z.y
            if ($z.requires_text) {
                $ar = $z.area
                $hit = $null
                # The screen read can fail briefly on busy video, so try up to 3 times before refusing.
                for ($try = 1; $try -le 3 -and -not $hit; $try++) {
                    if ($try -gt 1) { Start-Sleep -Seconds 1 }
                    [void](Read-Screen)
                    $hit = $script:elements | Where-Object {
                        $_.label -like "*$($z.requires_text)*" -and $_.x -ge $ar.x_min -and $_.x -le $ar.x_max -and $_.y -ge $ar.y_min -and $_.y -le $ar.y_max
                    } | Select-Object -First 1
                }
                if (-not $hit) { return "REFUSED: '$($z.requires_text)' is not on screen in the expected area, so '$($z.name)' was not tapped. Tell the user." }
                $tx = $hit.x; $ty = $hit.y
            }
            Tap $tx $ty
            $script:tapped += $z.name
            return "Tapped zone '$($z.name)'."
        }
        "tap_element" {
            $e = $script:elements | Where-Object { $_.id -eq $a.id } | Select-Object -First 1
            if (-not $e) { return "No element $($a.id). Call list_screen first." }
            Tap $e.x $e.y
            return "Tapped '$($e.label)'."
        }
        "tap" { Tap ([int]$a.x) ([int]$a.y); return "Tapped ($($a.x),$($a.y))." }
        "swipe" {
            Adb "shell input swipe $([int]$a.x1) $([int]$a.y1) $([int]$a.x2) $([int]$a.y2) 300" | Out-Null
            return "Swiped."
        }
        "type_text" {
            Read-Screen | Out-Null
            if ($script:pwFocused) { return "REFUSED: a password field is focused. The user must type passwords themselves." }
            if ($a.text -notmatch '^[A-Za-z0-9 .,@_!?:/-]+$') { return "REFUSED: text contains unsupported characters." }
            Adb "shell input text $($a.text -replace ' ', '%s')" | Out-Null
            return "Typed."
        }
        "press_key" {
            $codes = @{ back = 4; home = 3; enter = 66 }
            if (-not $codes.ContainsKey([string]$a.key)) { return "Key must be back, home or enter." }
            Adb "shell input keyevent $($codes[[string]$a.key])" | Out-Null
            return "Pressed $($a.key)."
        }
        "screenshot" {
            $p = Join-Path $work "screen.png"
            Adb "shell screencap -p /sdcard/screen.png" | Out-Null
            Adb "pull /sdcard/screen.png $p" | Out-Null
            return "Saved screenshot to $p (the user can open it; you cannot see images)."
        }
        "open_app" {
            if ($a.package -notmatch '^[A-Za-z0-9._]+$') { return "Invalid package name." }
            Adb "shell monkey -p $($a.package) -c android.intent.category.LAUNCHER 1" | Out-Null
            return "Launched $($a.package)."
        }
        "list_apps" { return (Adb "shell pm list packages -3") }
        "wait" { Start-Sleep -Seconds ([math]::Min([int]$a.seconds, 5)); return "Waited." }
        "phone_status" { return (& $ld list2 | Out-String) }
        "launch_phone" { & $ld launch --index $Index | Out-Null; return "Launching. Wait about 60 seconds." }
        "quit_phone" { & $ld quit --index $Index | Out-Null; return "Phone shut down." }
        default { return "Unknown tool $name." }
    }
}

function New-Tool($name, $desc, $props = @{}, $required = @()) {
    @{ type = "function"; function = @{ name = $name; description = $desc
            parameters = @{ type = "object"; properties = $props; required = @($required) } } }
}

$int = @{ type = "integer" }
$tools = @(
    (New-Tool "list_screen" "Read the phone screen as a numbered list of labels with center coordinates. Call it first and after every action.")
    (New-Tool "tap_element" "Tap a numbered element from the latest list_screen." @{ id = $int } @("id"))
    (New-Tool "tap" "Tap at coordinates. The screen is 720 wide and 1280 tall." @{ x = $int; y = $int } @("x", "y"))
    (New-Tool "swipe" "Swipe from one point to another, for example to scroll." @{ x1 = $int; y1 = $int; x2 = $int; y2 = $int } @("x1", "y1", "x2", "y2"))
    (New-Tool "type_text" "Type plain text into the focused field." @{ text = @{ type = "string" } } @("text"))
    (New-Tool "press_key" "Press back, home or enter." @{ key = @{ type = "string"; enum = @("back", "home", "enter") } } @("key"))
    (New-Tool "screenshot" "Save a screenshot for the user to view.")
    (New-Tool "open_app" "Open an app by package name." @{ package = @{ type = "string" } } @("package"))
    (New-Tool "list_apps" "List installed third-party app package names.")
    (New-Tool "wait" "Wait up to 5 seconds." @{ seconds = $int } @("seconds"))
    (New-Tool "phone_status" "Show whether the phone is running.")
    (New-Tool "launch_phone" "Start the phone.")
    (New-Tool "quit_phone" "Shut the phone down cleanly.")
)

# Strict mode: the model sees only these tools. Taps are possible only through named zones.
$tools = @(
    (New-Tool "list_screen" "Read the phone screen as text. Use only when the user asks what is on screen.")
    (New-Tool "list_zones" "List the only spots you are allowed to tap, by name.")
    (New-Tool "tap_zone" "Tap one allowed zone by name. Only when the user's latest message asks for it." @{ name = @{ type = "string"; enum = @($script:zones.name) } } @("name"))
    (New-Tool "screenshot" "Save a screenshot for the user to view.")
    (New-Tool "phone_status" "Show whether the phone is running.")
    (New-Tool "wait" "Wait up to 5 seconds." @{ seconds = $int } @("seconds"))
)

function Start-Agent {
    $model = (Invoke-RestMethod "$Api/models").data[0].id
    Write-Host "Using model: $model  (type 'exit' to quit; actions are logged to $log)"
    # ReadAllText gives a plain string; Get-Content -Raw output carries extra properties that ConvertTo-Json expands into a huge body.
    $system = [IO.File]::ReadAllText((Join-Path $PSScriptRoot "system-prompt.txt"))
    $messages = New-Object System.Collections.ArrayList
    [void]$messages.Add(@{ role = "system"; content = $system })
    while ($true) {
        $u = Read-Host "You"
        if ($u -eq "exit") { break }
        [void]$messages.Add(@{ role = "user"; content = $u })
        $calls = 0
        $script:tapped = @()
        $script:userText = $u
        while ($true) {
            $body = @{ model = $model; messages = $messages; tools = $tools; temperature = 0.2 } | ConvertTo-Json -Depth 12
            try {
                $resp = Invoke-RestMethod "$Api/chat/completions" -Method Post -ContentType "application/json" -Body ([Text.Encoding]::UTF8.GetBytes($body))
            }
            catch {
                # A bad conversation state makes every later request fail too, so start over from the system prompt.
                Write-Host "Model server error: $($_.ErrorDetails.Message). Conversation reset; ask again."
                $messages.Clear()
                [void]$messages.Add(@{ role = "system"; content = $system })
                break
            }
            $msg = $resp.choices[0].message
            [void]$messages.Add($msg)
            if (-not $msg.tool_calls) { Write-Host "`nModel: $($msg.content)`n"; break }
            foreach ($tc in $msg.tool_calls) {
                $calls++
                $a = if ($tc.function.arguments) { $tc.function.arguments | ConvertFrom-Json } else { [pscustomobject]@{} }
                if ($calls -gt $MaxToolCalls) {
                    $result = "REFUSED: tool call limit reached for this request. Tell the user what you did and stop."
                }
                else {
                    try { $result = Invoke-Tool $tc.function.name $a } catch { $result = "ERROR: $($_.Exception.Message)" }
                }
                Write-Host ("  [{0}] {1}" -f $tc.function.name, ($result -split "`n")[0])
                Write-Log ("  result of {0}: {1}" -f $tc.function.name, ($result -split "`n")[0])
                [void]$messages.Add(@{ role = "tool"; tool_call_id = $tc.id; content = [string]$result })
            }
            if ($calls -gt ($MaxToolCalls + 3)) { Write-Host "Stopped: too many tool calls."; break }
        }
    }
}

# Dot-sourcing this file (. .\ldagent.ps1) loads the functions without starting the chat.
if ($MyInvocation.InvocationName -ne ".") { Start-Agent }
