<#
.SYNOPSIS
    Installs winget (App Installer) on Windows editions that don't ship with it,
    e.g. Windows 11 IoT Enterprise LTSC / Enterprise LTSC.

.DESCRIPTION
    1. Downloads the latest winget-cli release assets from GitHub:
         - DesktopAppInstaller_Dependencies.zip
         - Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle
         - <id>_License1.xml
    2. Installs the architecture-matching dependency .appx packages
       (VCLibs, UI.Xaml, ...).
    3. Provisions the App Installer bundle with its license.
    4. Verifies that winget runs.

    Any error stops the script (fail closed). Nothing is installed unless every
    required file was downloaded and its signature is valid.

.PARAMETER WorkDir
    Folder used for downloads and extraction. Default: %TEMP%\winget-install

.PARAMETER SkipSignatureCheck
    Skip the Authenticode check of the downloaded packages. Off by default.

.PARAMETER AcceptSourceAgreements
    After install, run "winget source update --accept-source-agreements" to
    accept the msstore agreement for you. Off by default; without it you are
    told to accept the prompt yourself on first use.

.EXAMPLE
    .\Install-Winget.ps1

.EXAMPLE
    .\Install-Winget.ps1 -WorkDir C:\Users\admin\Downloads\winget -AcceptSourceAgreements
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$WorkDir = (Join-Path $env:TEMP 'winget-install'),
    [switch]$SkipSignatureCheck,
    [switch]$AcceptSourceAgreements
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # much faster Invoke-WebRequest on PS 5.1
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ReleaseApi = 'https://api.github.com/repos/microsoft/winget-cli/releases/latest'

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

# --- 0. Preconditions (deny if not satisfied) -------------------------------
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'This script must be run from an elevated (Administrator) PowerShell.'
}

if ([string]::IsNullOrWhiteSpace($WorkDir)) {
    throw 'WorkDir is empty; refusing to continue.'
}

# Map OS architecture to the folder name inside the dependencies zip.
$archFolder = switch ($env:PROCESSOR_ARCHITECTURE) {
    'AMD64' { 'x64' }
    'ARM64' { 'arm64' }
    'x86'   { 'x86' }
    default { throw "Unsupported processor architecture: '$($env:PROCESSOR_ARCHITECTURE)'" }
}
Write-Step "Architecture: $archFolder"

# --- 1. Find and download release assets ------------------------------------
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

Write-Step 'Querying latest winget-cli release'
$release = Invoke-RestMethod -Uri $ReleaseApi -Headers @{ 'User-Agent' = 'Install-Winget.ps1' }
if (-not $release.assets) { throw 'Release has no assets; cannot continue.' }
Write-Host "    Release: $($release.tag_name)"

function Get-Asset([string]$Pattern) {
    $found = @($release.assets | Where-Object { $_.name -like $Pattern })
    if ($found.Count -ne 1) {
        throw "Expected exactly one release asset matching '$Pattern' but found $($found.Count)."
    }
    $found[0]
}

$assets = @{
    Bundle  = Get-Asset 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
    Deps    = Get-Asset 'DesktopAppInstaller_Dependencies.zip'
    License = Get-Asset '*_License1.xml'
}

$paths = @{}
foreach ($key in $assets.Keys) {
    $a    = $assets[$key]
    $dest = Join-Path $WorkDir $a.name
    Write-Step "Downloading $($a.name)"
    Invoke-WebRequest -Uri $a.browser_download_url -OutFile $dest -UseBasicParsing
    if (-not (Test-Path -LiteralPath $dest) -or (Get-Item -LiteralPath $dest).Length -eq 0) {
        throw "Download of $($a.name) failed or produced an empty file."
    }
    $paths[$key] = $dest
}

# --- 2. Extract dependencies -------------------------------------------------
$depsDir = Join-Path $WorkDir 'DesktopAppInstaller_Dependencies'
if (Test-Path -LiteralPath $depsDir) { Remove-Item -LiteralPath $depsDir -Recurse -Force }
Write-Step 'Extracting dependencies'
Expand-Archive -LiteralPath $paths.Deps -DestinationPath $depsDir -Force

$archDir = Join-Path $depsDir $archFolder
if (-not (Test-Path -LiteralPath $archDir)) {
    throw "Dependency folder for '$archFolder' not found in the zip: $archDir"
}
$depPackages = @(Get-ChildItem -LiteralPath $archDir -Filter *.appx -File)
if ($depPackages.Count -eq 0) { throw "No .appx dependency packages found in $archDir" }

# --- 3. Verify signatures (fail closed) -------------------------------------
if (-not $SkipSignatureCheck) {
    Write-Step 'Verifying package signatures'
    $toCheck = @($paths.Bundle) + @($depPackages | ForEach-Object { $_.FullName })
    foreach ($file in $toCheck) {
        $sig = Get-AuthenticodeSignature -LiteralPath $file
        if ($sig.Status -ne 'Valid') {
            throw "Signature check failed for $(Split-Path $file -Leaf): $($sig.Status). Use -SkipSignatureCheck only if you accept this risk."
        }
    }
}

# --- 4. Install dependencies -------------------------------------------------
foreach ($pkg in $depPackages) {
    Write-Step "Installing dependency $($pkg.Name)"
    Add-AppxPackage -Path $pkg.FullName
}

# --- 5. Provision App Installer (winget) ------------------------------------
Write-Step 'Provisioning Microsoft.DesktopAppInstaller'
Add-AppxProvisionedPackage -Online `
    -PackagePath $paths.Bundle `
    -LicensePath $paths.License `
    -Verbose | Out-Null

# --- 6. Verify ---------------------------------------------------------------
Write-Step 'Verifying winget'
$winget = Get-Command winget.exe -ErrorAction SilentlyContinue
if (-not $winget) {
    Write-Warning 'Provisioning succeeded but winget is not on PATH in this session. Sign out and back in (or open a new session) and run "winget --version".'
    exit 1
}
Write-Host "    winget version: $(& $winget.Source --version)" -ForegroundColor Green

if ($AcceptSourceAgreements) {
    Write-Step 'Accepting source agreements and updating sources'
    & $winget.Source source update --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw "winget source update failed with exit code $LASTEXITCODE" }
}
else {
    Write-Host ''
    Write-Host 'On first use (e.g. "winget upgrade") answer Y to accept the msstore source agreement.'
}

Write-Host ''
Write-Host 'Done. You can now run "winget upgrade" and "winget upgrade --all".' -ForegroundColor Green
