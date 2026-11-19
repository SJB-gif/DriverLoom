# DriverLoom

Check hardware updates from official sources in one simple Windows app.

**[Download for Windows](https://github.com/SJB-gif/DriverLoom/releases/latest/download/DriverLoom-Setup.exe)** · [Release notes](https://github.com/SJB-gif/DriverLoom/releases/latest) · [Supported hardware](docs/COVERAGE.md)

Windows 10/11 x64. One installer, installed for the current user. The installer is currently unsigned.

## Get started

1. Download and run **DriverLoom-Setup.exe**. Close DriverLoom first if you are upgrading; your settings are kept.
2. Choose whether to add **Start menu** and **Desktop** shortcuts.
3. Open **DriverLoom**. It checks automatically. Use the refresh arrow to check again.
4. When updates are found, **Update All** opens a review list. Eligible Windows Update drivers can be installed together after confirmation. **Review update** opens the official manufacturer page for packages requiring manual installation.

## Features

- Installed and available versions, with clear update status.
- Checks for supported NVIDIA, AMD, Intel, ASUS and Samsung hardware.
- Unsupported devices and excluded offers explained in Settings.
- Dark, light and system themes, plus an optional BIOS/USB preparation guide.

Open the gear for Settings, About and Help. Double-click a device for details.

## Current limits

Automatic installation supports eligible **Windows Update drivers only**. Manufacturer packages require manual installation. Coverage varies by device; see the [coverage guide](docs/COVERAGE.md). DriverLoom does not flash firmware or restart your PC automatically.

## Privacy

DriverLoom requires no account and contains no analytics, advertising or usage tracking.

- **Local data:** hardware inventory, preferences, saved sources and diagnostic logs are stored on your PC in `%LOCALAPPDATA%\HardwareUpdateLauncher`. DriverLoom does not automatically upload these files.
- **Update checks:** opening the app starts checks with Windows Update and manufacturer sites. Some manufacturer lookups include hardware-model and Windows-version details.
- **Optional GitHub access:** catalog and release metadata are fetched only if you configure a repository. Opening a vendor or repository link visits that site in your browser.

External services can see normal connection information, including your connection's public IP address, and apply their own privacy policies. Windows Update's data handling is governed by Windows and Microsoft.

## Build from source

Use **64-bit Windows PowerShell 5.1** and **NSIS 3.11 or later**:

```powershell
.\Build.ps1 -MakeNSIS 'C:\Program Files (x86)\NSIS\makensis.exe'
```

The build runs the checks and creates `dist\DriverLoom-Setup.exe` plus its SHA-256 checksum. See the [development guide](docs/DEVELOPMENT.md) for installer testing, diagnostics and source catalogs.

## License

[MIT](LICENSE). See [artwork credits](assets/ATTRIBUTION.md).
