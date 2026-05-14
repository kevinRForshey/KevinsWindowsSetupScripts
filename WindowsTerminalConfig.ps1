# ==============================================================
#  Setup-TerminalRice.ps1
#  Full terminal rice setup — Catppuccin + Oh My Posh + PSReadLine
#  Compatible with Windows 10/11 Pro, PowerShell 7+
#  Run as Administrator in PowerShell 7
# ==============================================================

#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]$UserName = $env:USERNAME,
    [switch]$SkipFastfetch,
    [switch]$SkipDadJokes
)

Set-StrictMode -Off
$ErrorActionPreference = "Continue"

# ── Colour helpers ────────────────────────────────────────────
function Write-Header  { param([string]$msg) Write-Host "`n══════════════════════════════════════════" -ForegroundColor DarkCyan; Write-Host "  $msg" -ForegroundColor Cyan; Write-Host "══════════════════════════════════════════" -ForegroundColor DarkCyan }
function Write-Step    { param([string]$msg) Write-Host "  ▶ $msg" -ForegroundColor Yellow }
function Write-Success { param([string]$msg) Write-Host "  ✓ $msg" -ForegroundColor Green }
function Write-Fail    { param([string]$msg) Write-Host "  ✗ $msg" -ForegroundColor Red; $script:Errors += $msg }
function Write-Info    { param([string]$msg) Write-Host "  · $msg" -ForegroundColor DarkGray }

# ── Error collector ───────────────────────────────────────────
$script:Errors = @()

# ── Paths ─────────────────────────────────────────────────────
$OmpDir       = "$env:LOCALAPPDATA\Programs\oh-my-posh\bin"
$OmpThemeDir  = "$env:LOCALAPPDATA\Programs\oh-my-posh\themes"
$OmpExe       = "$OmpDir\oh-my-posh.exe"
$OmpTheme     = "$OmpThemeDir\catppuccin.omp.json"
$ProfilePath  = "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
$WtSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
$FastfetchBase = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages"

# ==============================================================
Write-Header "Step 1 — Prerequisites"
# ==============================================================

# Ensure running as Administrator
Write-Step "Checking for Administrator privileges..."
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Fail "Script must be run as Administrator. Right-click PowerShell and choose 'Run as administrator'."
    exit 1
}
Write-Success "Running as Administrator"

# Ensure PowerShell 7+
Write-Step "Checking PowerShell version..."
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Fail "PowerShell 7+ required. Install from: https://aka.ms/powershell"
    exit 1
}
Write-Success "PowerShell $($PSVersionTable.PSVersion)"

# Set execution policy
Write-Step "Setting execution policy..."
try {
    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    Write-Success "Execution policy set to RemoteSigned"
} catch {
    Write-Fail "Could not set execution policy: $_"
}

# ==============================================================
Write-Header "Step 2 — Install Oh My Posh"
# ==============================================================

Write-Step "Creating Oh My Posh directories..."
try {
    New-Item -ItemType Directory -Path $OmpDir      -Force | Out-Null
    New-Item -ItemType Directory -Path $OmpThemeDir -Force | Out-Null
    Write-Success "Directories created"
} catch {
    Write-Fail "Could not create OMP directories: $_"
}

Write-Step "Downloading Oh My Posh binary..."
try {
    $ompUrl = "https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-windows-amd64.exe"
    Invoke-WebRequest $ompUrl -OutFile $OmpExe -UseBasicParsing
    $size = (Get-Item $OmpExe).Length
    if ($size -gt 1MB) {
        Write-Success "Oh My Posh downloaded ($([math]::Round($size/1MB, 1)) MB)"
    } else {
        Write-Fail "Oh My Posh download seems too small ($size bytes) — may be corrupt"
    }
} catch {
    Write-Fail "Failed to download Oh My Posh: $_"
}

Write-Step "Testing Oh My Posh binary..."
try {
    $ver = & $OmpExe --version 2>&1
    Write-Success "Oh My Posh version: $ver"
} catch {
    Write-Fail "Oh My Posh binary failed to run: $_"
}

# ==============================================================
Write-Header "Step 3 — Install Nerd Font (CaskaydiaCove)"
# ==============================================================

Write-Step "Downloading CaskaydiaCove Nerd Font..."
try {
    $fontUrl = "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaCode.zip"
    $fontZip = "$env:TEMP\CascadiaCode.zip"
    $fontDir = "$env:TEMP\CascadiaCode"
    Invoke-WebRequest $fontUrl -OutFile $fontZip -UseBasicParsing
    Write-Success "Font archive downloaded"

    Write-Step "Extracting fonts..."
    Expand-Archive $fontZip -DestinationPath $fontDir -Force

    Write-Step "Installing fonts to system..."
    $installed = 0
    Get-ChildItem $fontDir -Recurse -Filter "*.ttf" | ForEach-Object {
        try {
            $dest = "C:\Windows\Fonts\$($_.Name)"
            Copy-Item $_.FullName $dest -Force
            New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" `
                -Name $_.BaseName -Value $_.Name -PropertyType String -Force | Out-Null
            $installed++
        } catch {
            Write-Fail "Could not install font $($_.Name): $_"
        }
    }
    Write-Success "Installed $installed font files"

    # Cleanup
    Remove-Item $fontZip -Force -ErrorAction SilentlyContinue
    Remove-Item $fontDir -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    Write-Fail "Font installation failed: $_"
}

# ==============================================================
Write-Header "Step 4 — Install PowerShell Modules"
# ==============================================================

$modules = @("PSReadLine", "Terminal-Icons", "posh-git")
foreach ($mod in $modules) {
    Write-Step "Installing $mod..."
    try {
        $params = @{ Name = $mod; Force = $true; ErrorAction = "Stop" }
        if ($mod -eq "PSReadLine")      { $params["SkipPublisherCheck"] = $true }
        if ($mod -eq "posh-git")        { $params["Scope"] = "CurrentUser" }
        if ($mod -eq "Terminal-Icons")  { $params["Repository"] = "PSGallery" }
        Install-Module @params
        Write-Success "$mod installed"
    } catch {
        Write-Fail "Failed to install ${mod}: $_"
    }
}

# ==============================================================
Write-Header "Step 5 — Install Fastfetch"
# ==============================================================

if (-not $SkipFastfetch) {
    Write-Step "Installing Fastfetch via winget..."
    try {
        $result = winget install fastfetch-cli.fastfetch --accept-source-agreements --accept-package-agreements 2>&1
        Write-Info $result
        Write-Success "Fastfetch install attempted"
    } catch {
        Write-Fail "Fastfetch install failed: $_"
    }
} else {
    Write-Info "Skipping Fastfetch (--SkipFastfetch flag set)"
}

# Find fastfetch exe
$FastfetchExe = $null
Write-Step "Locating Fastfetch executable..."
try {
    $ffDir = Get-ChildItem $FastfetchBase -Filter "*Fastfetch*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($ffDir) {
        $ffExe = Get-ChildItem $ffDir.FullName -Recurse -Filter "fastfetch.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($ffExe) {
            $FastfetchExe = $ffExe.FullName
            Write-Success "Fastfetch found at: $FastfetchExe"
        } else {
            Write-Fail "fastfetch.exe not found inside $($ffDir.FullName)"
        }
    } else {
        Write-Fail "Fastfetch package directory not found in WinGet packages"
    }
} catch {
    Write-Fail "Error locating Fastfetch: $_"
}

# ==============================================================
Write-Header "Step 6 — Write Oh My Posh Theme"
# ==============================================================

Write-Step "Writing Catppuccin Mocha powerline theme..."
$themeJson = @'
{
  "version": 2,
  "final_space": true,
  "console_title_template": "{{ .Shell }} · {{ .Folder }}",
  "blocks": [
    {
      "type": "prompt",
      "alignment": "left",
      "newline": true,
      "segments": [
        {
          "type": "session",
          "style": "powerline",
          "powerline_symbol": "",
          "foreground": "#1e1e2e",
          "background": "#cba6f7",
          "template": "  {{ .UserName }} "
        },
        {
          "type": "path",
          "style": "powerline",
          "powerline_symbol": "",
          "foreground": "#1e1e2e",
          "background": "#89b4fa",
          "template": "  {{ .Path }} ",
          "properties": {
            "style": "agnoster_short",
            "max_depth": 3
          }
        },
        {
          "type": "git",
          "style": "powerline",
          "powerline_symbol": "",
          "foreground": "#1e1e2e",
          "background": "#a6e3a1",
          "background_templates": [
            "{{ if .Working.Changed }}#f9e2af{{ end }}",
            "{{ if .Staging.Changed }}#fab387{{ end }}",
            "{{ if gt .Ahead 0 }}#89dceb{{ end }}",
            "{{ if gt .Behind 0 }}#f38ba8{{ end }}"
          ],
          "template": "   {{ .HEAD }} {{ if .Staging.Changed }}+{{ .Staging.String }} {{ end }}{{ if .Working.Changed }}!{{ .Working.String }} {{ end }}{{ if gt .Ahead 0 }}\u21e1{{ .Ahead }} {{ end }}{{ if gt .Behind 0 }}\u21e3{{ .Behind }} {{ end }}{{ if and (not .Working.Changed) (not .Staging.Changed) }}\u2713 {{ end }}",
          "properties": {
            "fetch_status": true,
            "fetch_upstream_icon": true,
            "branch_icon": " "
          }
        },
        {
          "type": "dotnet",
          "style": "powerline",
          "powerline_symbol": "",
          "foreground": "#1e1e2e",
          "background": "#cba6f7",
          "template": "  {{ .Full }} "
        },
        {
          "type": "node",
          "style": "powerline",
          "powerline_symbol": "",
          "foreground": "#1e1e2e",
          "background": "#a6e3a1",
          "template": "  {{ .Full }} "
        },
        {
          "type": "python",
          "style": "powerline",
          "powerline_symbol": "",
          "foreground": "#1e1e2e",
          "background": "#89dceb",
          "template": "  {{ .Full }}{{ if .Venv }} ({{ .Venv }}){{ end }} "
        },
        {
          "type": "executiontime",
          "style": "powerline",
          "powerline_symbol": "",
          "foreground": "#1e1e2e",
          "background": "#f9e2af",
          "template": " \udb85\udebf {{ .FormattedMs }} ",
          "properties": {
            "threshold": 2000,
            "style": "austin"
          }
        },
        {
          "type": "text",
          "style": "powerline",
          "powerline_symbol": "",
          "foreground": "#313244",
          "background": "#1e1e2e",
          "template": " "
        }
      ]
    },
    {
      "type": "prompt",
      "alignment": "left",
      "newline": true,
      "segments": [
        {
          "type": "status",
          "style": "plain",
          "foreground_templates": [
            "{{ if .Error }}#f38ba8{{ else }}#a6e3a1{{ end }}"
          ],
          "template": "\u276f ",
          "properties": {
            "always_enabled": true
          }
        }
      ]
    }
  ]
}
'@

try {
    $themeJson | Set-Content -Path $OmpTheme -Encoding UTF8 -Force
    Write-Success "Theme written to $OmpTheme"
} catch {
    Write-Fail "Failed to write theme file: $_"
}

# ==============================================================
Write-Header "Step 7 — Write PowerShell Profile"
# ==============================================================

Write-Step "Creating profile directory if needed..."
$profileDir = Split-Path $ProfilePath
New-Item -ItemType Directory -Path $profileDir -Force | Out-Null

Write-Step "Writing PowerShell profile..."

# Build fastfetch line dynamically based on whether we found it
$fastfetchLine = if ($FastfetchExe -and -not $SkipFastfetch) {
    "& `"$FastfetchExe`""
} else {
    "# fastfetch not found — install manually and add path here"
}

$dadJokeBlock = if (-not $SkipDadJokes) {
@'
# ── Dad Joke + Cowsay ─────────────────────────────
function Show-Cowsay {
    param([string]$message)
    $width = 60
    $words = $message -split ' '
    $lines = @()
    $line  = ""
    foreach ($word in $words) {
        if (("$line $word").Trim().Length -le $width) {
            $line = "$line $word".Trim()
        } else {
            $lines += $line
            $line   = $word
        }
    }
    $lines += $line
    $maxLen = ($lines | Measure-Object -Property Length -Maximum).Maximum
    $border = "-" * ($maxLen + 2)
    Write-Host ""
    Write-Host " $border" -ForegroundColor Cyan
    foreach ($l in $lines) {
        $pad = " " * ($maxLen - $l.Length)
        Write-Host " | $l$pad |" -ForegroundColor Cyan
    }
    Write-Host " $border" -ForegroundColor Cyan
    Write-Host "        \   ^__^"           -ForegroundColor Yellow
    Write-Host "         \  (oo)\_______"   -ForegroundColor Yellow
    Write-Host "            (__)\       )\/" -ForegroundColor Yellow
    Write-Host "                ||----w |"  -ForegroundColor Yellow
    Write-Host "                ||     ||"  -ForegroundColor Yellow
    Write-Host ""
}

try {
    $joke = (Invoke-RestMethod -Uri "https://icanhazdadjoke.com/" -Headers @{Accept="application/json"} -TimeoutSec 3).joke
    Show-Cowsay $joke
} catch {
    Show-Cowsay "Why don't scientists trust atoms? Because they make up everything!"
}
'@
} else { "# Dad jokes disabled" }

$profileContent = @"
# ==============================================================
#  PowerShell Profile — Catppuccin Rice
#  Generated by Setup-TerminalRice.ps1
# ==============================================================

# ── Fastfetch ─────────────────────────────────────
$fastfetchLine

$dadJokeBlock

# ── Modules ───────────────────────────────────────
Import-Module Terminal-Icons -ErrorAction SilentlyContinue
Import-Module posh-git       -ErrorAction SilentlyContinue

# ── Oh My Posh ────────────────────────────────────
& "$OmpExe" init pwsh --config "$OmpTheme" | Invoke-Expression

# ── PSReadLine ────────────────────────────────────
Set-PSReadLineOption -PredictionSource HistoryAndPlugin
Set-PSReadLineOption -PredictionViewStyle ListView
Set-PSReadLineOption -EditMode Windows
Set-PSReadLineOption -BellStyle None
Set-PSReadLineOption -HistorySearchCursorMovesToEnd
Set-PSReadLineKeyHandler -Key RightArrow -Function ForwardChar
Set-PSReadLineKeyHandler -Key Ctrl+f     -Function ForwardWord
Set-PSReadLineKeyHandler -Key UpArrow    -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow  -Function HistorySearchForward
Set-PSReadLineKeyHandler -Key Ctrl+d     -Function DeleteCharOrExit
Set-PSReadLineOption -Colors @{
    Command                = '#89b4fa'
    Parameter              = '#cba6f7'
    String                 = '#a6e3a1'
    Variable               = '#f38ba8'
    Comment                = '#6c7086'
    InlinePrediction       = '#45475a'
    ListPrediction         = '#313244'
    ListPredictionSelected = '#cba6f7'
}

# ── Git aliases ───────────────────────────────────
function gs    { git status -sb }
function ga    { git add `$args }
function gc    { git commit -m `$args }
function gp    { git push `$args }
function gpl   { git pull --rebase }
function gco   { git checkout `$args }
function glog  { git log --oneline --graph --decorate -20 }
function gnb   { git checkout -b `$args }
function gundo { git reset --soft HEAD~1 }

# ── .NET / Blazor ─────────────────────────────────
function dw   { dotnet watch `$args }
function dr   { dotnet run `$args }
function dt   { dotnet test --logger:"console;verbosity=minimal" `$args }
function db   { dotnet build `$args }
function ef   { dotnet ef `$args }
function efm  { dotnet ef migrations add `$args }
function efu  { dotnet ef database update }

# ── Node / Next.js ────────────────────────────────
function nrd  { npm run dev `$args }
function nrb  { npm run build `$args }
function ni   { npm install `$args }

# ── Python ────────────────────────────────────────
function venv     { python -m venv .venv; .\.venv\Scripts\Activate.ps1 }
function activate { .\.venv\Scripts\Activate.ps1 }

# ── Quality of life ───────────────────────────────
function ll     { Get-ChildItem -Force `$args }
function touch  { New-Item -ItemType File `$args }
function reload { . `$PROFILE }
function c.     { code . }
function e.     { explorer . }
function which  { Get-Command `$args | Select-Object -ExpandProperty Source }
function path   { `$env:PATH -split ';' | Sort-Object }
"@

try {
    $profileContent | Set-Content -Path $ProfilePath -Encoding UTF8 -Force
    Write-Success "Profile written to $ProfilePath"
} catch {
    Write-Fail "Failed to write profile: $_"
}

# ==============================================================
Write-Header "Step 8 — Configure Windows Terminal"
# ==============================================================

Write-Step "Locating Windows Terminal settings..."
if (Test-Path $WtSettingsPath) {
    Write-Success "Found settings at $WtSettingsPath"
    try {
        $wtSettings = Get-Content $WtSettingsPath -Raw | ConvertFrom-Json -Depth 20

        # Add Catppuccin colour scheme
        $catppuccinScheme = @{
            name                = "Catppuccin Mocha"
            background          = "#1E1E2E"
            foreground          = "#CDD6F4"
            cursorColor         = "#F5E0DC"
            selectionBackground = "#585B70"
            black               = "#45475A"
            blue                = "#89B4FA"
            cyan                = "#89DCEB"
            green               = "#A6E3A1"
            purple              = "#CBA6F7"
            red                 = "#F38BA8"
            white               = "#BAC2DE"
            yellow              = "#F9E2AF"
            brightBlack         = "#585B70"
            brightBlue          = "#89B4FA"
            brightCyan          = "#A6E3A1"
            brightGreen         = "#A6E3A1"
            brightPurple        = "#CBA6F7"
            brightRed           = "#F38BA8"
            brightWhite         = "#A6ADC8"
            brightYellow        = "#F9E2AF"
        }

        # Remove existing Catppuccin scheme if present and re-add
        if ($null -eq $wtSettings.schemes) {
            $wtSettings | Add-Member -MemberType NoteProperty -Name "schemes" -Value @() -Force
        }
        $wtSettings.schemes = @($wtSettings.schemes | Where-Object { $_.name -ne "Catppuccin Mocha" }) + $catppuccinScheme

        # Set defaults for all profiles
        if ($null -eq $wtSettings.profiles.defaults) {
            $wtSettings.profiles | Add-Member -MemberType NoteProperty -Name "defaults" -Value ([PSCustomObject]@{}) -Force
        }
        $defaults = $wtSettings.profiles.defaults
        $defaults | Add-Member -MemberType NoteProperty -Name "colorScheme"      -Value "Catppuccin Mocha"         -Force
        $defaults | Add-Member -MemberType NoteProperty -Name "font"             -Value @{ face = "CaskaydiaCove NF"; size = 13 } -Force
        $defaults | Add-Member -MemberType NoteProperty -Name "opacity"          -Value 90                         -Force
        $defaults | Add-Member -MemberType NoteProperty -Name "useAcrylic"       -Value $true                      -Force
        $defaults | Add-Member -MemberType NoteProperty -Name "cursorShape"      -Value "bar"                      -Force
        $defaults | Add-Member -MemberType NoteProperty -Name "scrollbarState"   -Value "hidden"                   -Force
        $defaults | Add-Member -MemberType NoteProperty -Name "padding"          -Value "10"                       -Force

        $wtSettings | ConvertTo-Json -Depth 20 | Set-Content $WtSettingsPath -Encoding UTF8 -Force
        Write-Success "Windows Terminal settings updated"
    } catch {
        Write-Fail "Failed to update Windows Terminal settings: $_"
    }
} else {
    Write-Info "Windows Terminal settings not found at expected path."
    Write-Info "If you haven't installed Windows Terminal yet, run:"
    Write-Info "  winget install Microsoft.WindowsTerminal"
    Write-Info "Then re-run this script."
}

# ==============================================================
Write-Header "Setup Complete!"
# ==============================================================

Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Cyan
Write-Host "  1. Fully close and reopen Windows Terminal" -ForegroundColor White
Write-Host "  2. Your Catppuccin prompt should appear immediately" -ForegroundColor White
Write-Host "  3. Open a git repo folder to see branch indicators" -ForegroundColor White
Write-Host ""

# ── Print any errors collected ────────────────────────────────
if ($script:Errors.Count -gt 0) {
    Write-Host "══════════════════════════════════════════" -ForegroundColor DarkRed
    Write-Host "  $($script:Errors.Count) error(s) occurred during setup:" -ForegroundColor Red
    Write-Host "══════════════════════════════════════════" -ForegroundColor DarkRed
    $i = 1
    foreach ($err in $script:Errors) {
        Write-Host "  $i. $err" -ForegroundColor Red
        $i++
    }
    Write-Host ""
    Write-Host "  Everything else completed successfully." -ForegroundColor Yellow
    Write-Host "  Review the errors above and fix manually if needed." -ForegroundColor Yellow
} else {
    Write-Host "  No errors! All steps completed successfully." -ForegroundColor Green
}

Write-Host ""
