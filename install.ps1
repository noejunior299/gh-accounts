<#
.SYNOPSIS
    Install gh-accounts for Windows (PowerShell).
.DESCRIPTION
    Copies gh-accounts module and CLI to $env:ProgramFiles\gh-accounts\
    and adds the directory to the user's PATH.
#>

#Requires -Version 5.1 -RunAsAdministrator

$CLR_GREEN = "$([char]0x1b)[0;32m"
$CLR_CYAN = "$([char]0x1b)[0;36m"
$CLR_RED = "$([char]0x1b)[0;31m"
$CLR_BOLD = "$([char]0x1b)[1m"
$CLR_RESET = "$([char]0x1b)[0m"

function info    { Write-Host "$CLR_CYAN[info]$CLR_RESET    $args" }
function success { Write-Host "$CLR_GREEN[success]$CLR_RESET $args" }
function error   { Write-Host "$CLR_RED[error]$CLR_RESET   $args" -ForegroundColor Red }
function die     { error $args; exit 1 }

# Resolve source directory
$sourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not (Test-Path (Join-Path $sourceDir "bin\gh-accounts.ps1"))) {
    die "Could not find bin\gh-accounts.ps1 in source directory."
}

$installDir = "$env:ProgramFiles\gh-accounts"

Write-Host "$CLR_CYAN"
Write-Host @'
        __                               __
  ___ _/ /  ___ _______ ___  __ _____   / /____
 / _ `/ _ \/ _ `/ __/ __/ _ \/ // / _ \/ __(_-<
 \_, /_//_/\_,_/\__/\__/\___/\_,_/_//_/\__/___/
/___/
'@
Write-Host "$CLR_RESET"
Write-Host "  ${CLR_BOLD}Installer (PowerShell)${CLR_RESET}"
Write-Host ""

info "Installing gh-accounts to $installDir..."

# Remove previous installation
if (Test-Path $installDir) {
    Remove-Item $installDir -Recurse -Force
}

# Create directories
New-Item -ItemType Directory -Path "$installDir\bin" -Force | Out-Null
New-Item -ItemType Directory -Path "$installDir\lib" -Force | Out-Null

# Copy files
Copy-Item "$sourceDir\bin\gh-accounts.ps1" "$installDir\bin\gh-accounts.ps1" -Force
Copy-Item "$sourceDir\lib\GhAccounts.psm1" "$installDir\lib\GhAccounts.psm1" -Force
Copy-Item "$sourceDir\lib\GhAccounts.psd1" "$installDir\lib\GhAccounts.psd1" -Force
if (Test-Path "$sourceDir\VERSION") {
    Copy-Item "$sourceDir\VERSION" "$installDir\VERSION" -Force
}
if (Test-Path "$sourceDir\LICENSE") {
    Copy-Item "$sourceDir\LICENSE" "$installDir\LICENSE" -Force
}

# Add to PATH
$userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
$binPath = "$installDir\bin"
if ($userPath -notlike "*$binPath*") {
    $newPath = if ($userPath) { "$userPath;$binPath" } else { $binPath }
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
    info "Added $binPath to user PATH."
} else {
    info "$binPath is already in PATH."
}

# Also add to current session
$env:Path = "$env:Path;$binPath"

Write-Host ""
success "gh-accounts installed successfully!"
Write-Host ""
Write-Host "  Run:  gh-accounts help"
$versionFile = "$installDir\VERSION"
if (Test-Path $versionFile) {
    $v = (Get-Content $versionFile -Raw).Trim()
    Write-Host "  Version: $v"
}
Write-Host ""
Write-Host "  ${CLR_YELLOW}Note:${CLR_RESET} You may need to restart your terminal for PATH changes to take effect."
Write-Host "  ${CLR_YELLOW}Note:${CLR_RESET} OpenSSH Client is required. Install with:"
Write-Host "    Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0"
Write-Host ""
