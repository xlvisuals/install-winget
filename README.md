# Install-Winget.ps1

Installs **winget** (Windows Package Manager / App Installer) on Windows editions that don't ship with it, such as Windows 11 IoT Enterprise LTSC and Enterprise LTSC.

The script automates the manual process: download the release files from the [winget-cli releases](https://github.com/microsoft/winget-cli/releases), install the dependencies, then provision the App Installer bundle with its license.

## Requirements

- Windows 10/11 (including LTSC / IoT LTSC)
- PowerShell 5.1 or later
- An **elevated** PowerShell (Run as Administrator)
- Internet access to `api.github.com` and GitHub release downloads

## Usage

Open PowerShell as Administrator, then:

```powershell
cd C:\path\to\script
powershell.exe -ExecutionPolicy Bypass -File .\Install-Winget.ps1
```

### Why is `powershell.exe -ExecutionPolicy Bypass` needed?

Windows editions default to the `Restricted` execution policy, which blocks all `.ps1` files. `powershell.exe -ExecutionPolicy Bypass` allows execution for the `.ps1` file passed with the `-File` parameter.


### Parameters

| Parameter | Default | Description |
|---|---|---|
| `-WorkDir` | `%TEMP%\winget-install` | Folder for downloads and extracted files. |
| `-SkipSignatureCheck` | off | Skip the Authenticode signature check on the packages. Only use this if you accept the risk. |
| `-AcceptSourceAgreements` | off | After install, run `winget source update --accept-source-agreements` to accept the msstore agreement for you. |

### Examples

```powershell
# Default run
.\Install-Winget.ps1

# Keep the downloaded files in a folder of your choice and accept source agreements
.\Install-Winget.ps1 -WorkDir C:\Users\admin\Downloads\winget -AcceptSourceAgreements
```

## What the script does

1. Checks it is running as Administrator and detects the CPU architecture (x64, x86 or arm64).
2. Looks up the latest winget-cli release and downloads:
   - `Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle`
   - `DesktopAppInstaller_Dependencies.zip`
   - `*_License1.xml`
3. Extracts the dependencies zip and picks the folder matching your architecture.
4. Verifies the Authenticode signature of the bundle and dependency packages.
5. Installs each dependency `.appx` with `Add-AppxPackage`.
6. Provisions the bundle with `Add-AppxProvisionedPackage -Online`, using the license file.
7. Runs `winget --version` to confirm it works.

## After installing

On first use, winget asks you to accept the `msstore` source agreement:

```powershell
winget upgrade
```

Answer `Y` (or use `-AcceptSourceAgreements` on the script). Then you can run:

```powershell
winget upgrade          # list available updates
winget upgrade --all    # update everything
```

If `winget` isn't found right after install, sign out and back in (or open a new session) so PATH picks it up.

## Behaviour notes

- **Fails closed:** any error, missing release asset, empty download or failed signature check stops the script before anything is installed.
- **Always latest:** the script installs the newest release, not a pinned version.
- **Dependencies:** every `.appx` in the architecture folder of the dependencies zip is installed (e.g. VCLibs and UI.Xaml).
- **Not accepted for you:** source agreements are only accepted if you pass `-AcceptSourceAgreements`.

## Troubleshooting

| Problem | Fix |
|---|---|
| "must be run from an elevated PowerShell" | Reopen PowerShell with Run as Administrator. |
| Signature check fails | Check the download wasn't interrupted or tampered with and retry. Use `-SkipSignatureCheck` only if you accept the risk. |
| "Expected exactly one release asset matching ..." | The release layout changed. Download the files manually from the releases page and follow the manual steps. |
| Download errors | Confirm the machine can reach `api.github.com` and GitHub downloads (proxy or firewall). |
| `winget` not recognised after install | Sign out and back in, then run `winget --version`. |

## Manual steps (what the script replaces)

1. Download `DesktopAppInstaller_Dependencies.zip`, the `.msixbundle` and the `*_License1.xml` from the winget-cli releases page.
2. Unzip the dependencies and, in an elevated PowerShell, run `Add-AppxPackage` on each `.appx` in the folder for your architecture.
3. Run `Add-AppxProvisionedPackage -Online -PackagePath <bundle> -LicensePath <license> -Verbose`.
4. Run `winget --version`, then `winget upgrade` and accept the agreement.
