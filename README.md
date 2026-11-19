# DriverLoom

Check hardware updates from official sources in one simple Windows app.

**[Download for Windows](https://github.com/SJB-gif/DriverLoom/releases/latest/download/DriverLoom-Setup.exe)** · [Release notes](https://github.com/SJB-gif/DriverLoom/releases/latest) · [Supported hardware](docs/COVERAGE.md)

Windows 10/11 x64. One installer, installed for the current user. The installer is currently unsigned.

**Latest source/test version: 0.1.14.** The public release is still **0.1.8**. Newer installers are available from [GitHub Actions builds](https://github.com/SJB-gif/DriverLoom/actions/workflows/build.yml). Release publishing and signing setup are on hold.

## Code signing policy

[SignPath Foundation](https://signpath.org/) is the planned route for free open-source signing. No application has been submitted and signing is not enabled. See the [code signing policy](CODE_SIGNING_POLICY.md) for the intended process and privacy details.

## Get started

1. Download and run **DriverLoom-Setup.exe**. Setup closes running DriverLoom windows and tray copies before upgrading. Finish any active driver installation first. Your settings are kept.
2. Choose whether to add **Start menu** and **Desktop** shortcuts.
3. Open **DriverLoom**. By default, it checks on opening. Use the refresh arrow to check again.
4. When updates are found, **Update All** opens a review list. Eligible Windows Update drivers can be installed together after confirmation. **Review update** opens the official manufacturer page for packages requiring manual installation.

## Features

- Installed and available versions, with clear update status.
- Checks for supported NVIDIA, AMD, Intel, ASUS and Samsung hardware.
- Names the software used to update devices that need another app, with official web links.
- Show or hide items without automatic checks in the hardware list.
- Windows Update shortcuts in Settings and the diagnostic lists.
- Dark, light and system themes, plus an optional BIOS/USB preparation guide.
- Bundled manufacturer logos, with hardware category icons as fallbacks.
- Startup and manual checks for published DriverLoom updates.

Open the gear for Settings, About and Help. Double-click a device for details.

Devices remain visible after a successful check. Green **Up to date** means the installed version matches or exceeds the checked source; **Vendor details** keeps the official link available. **Update available** identifies a newer version. Failed or ambiguous comparisons show **Check unavailable**, with the reason in device details.

The list opens in **Device A–Z** order. Click Device to switch A–Z/Z–A, or Status for **updates first**, then up-to-date devices, then application names A–Z. Unavailable checks follow those groups. Installed, Available and Action do not change the sorting. Your selected order stays in place as results refresh.

Enable **Show items without automatic checks** in Settings to include devices managed by other software or a manual support page. Their status names where to go: for example, **CORSAIR iCUE**, **CORSAIR SSD Toolbox** or **Microsoft Gaming Services**. Use **Open update page** for the official website. These labels do not mean an update is available. Unknown software owners are not assigned guessed download links.

Settings save when you click back onto the main window or press **Esc**. BIOS and firmware options are on the right; background options are on the left.

## Checks and background operation

In Settings, choose **Manual**, **On opening** (default), **Daily** or **Weekly**. Daily and weekly checks respect the last check time and run only while DriverLoom is open or kept in the tray. Checks never install drivers automatically.

**Keep running in the tray** and **Start with Windows** are both off by default. With tray mode enabled, closing the window hides it; use the tray icon to reopen, check or exit. Windows startup opens the window unless tray mode is also enabled. DriverLoom does not install a background service or wake the PC to check.

## DriverLoom updates

DriverLoom checks its own latest stable GitHub release on opening. Turn **Check app updates on opening** off in Settings to disable that check, or use **Check app updates** whenever you choose. App checks are separate from the hardware-check schedule and optional source catalog.

When a newer published version is available, a popup offers **Download installer** and **Release notes**. The download opens in your browser; run the downloaded installer to upgrade. Setup closes DriverLoom safely and keeps its preferences. An active driver installation blocks the upgrade. Copies in another Windows session, or an instance setup cannot safely identify, need to be closed manually. A tray startup defers the popup until you reopen DriverLoom.

Only published stable releases are offered. Test installers from Actions can be newer than the public release and will not be downgraded.

## Current limits

Automatic installation supports eligible **Windows Update drivers only**. Manufacturer packages require manual installation. Coverage varies by device; see the [coverage guide](docs/COVERAGE.md). DriverLoom does not flash firmware or restart your PC automatically.

## Privacy

DriverLoom requires no account and contains no analytics, advertising or usage tracking.

- **Local data:** hardware inventory, preferences, saved sources and diagnostic logs are stored on your PC in `%LOCALAPPDATA%\HardwareUpdateLauncher`. DriverLoom does not automatically upload these files.
- **Copy list:** copies the displayed device or package names and reasons to the Windows clipboard when you select it.
- **Update checks:** checks contact Windows Update and manufacturer sites at the frequency you select, or when you use refresh. Some manufacturer lookups include hardware-model and Windows-version details.
- **App update checks:** the startup check contacts the public DriverLoom GitHub release API without an account, hardware details or diagnostic files. You can disable it in Settings. Manual app checks contact the same API.
- **Optional catalogs and links:** catalog metadata is fetched if you configure a repository. Opening a vendor, installer or repository link visits that site in your browser. Manufacturer logos are bundled locally and make no network requests.

External services can see normal connection information, including your connection's public IP address, and apply their own privacy policies. Windows Update's data handling is governed by Windows and Microsoft.

## Support

DriverLoom is a personal, volunteer-maintained project, provided as-is. **No individual support is provided.** Downloading or using the app does not include a support service or a promise of a reply, fix or ongoing maintenance.

Optional bug reports belong in [GitHub Issues](https://github.com/SJB-gif/DriverLoom/issues). Reports may not be reviewed or answered. Please do not contact the maintainer through personal email or social accounts. Keep reports free of serial numbers, hardware IDs and other personal information; review any copied diagnostic details before posting. No public support email is provided.

## Build from source

Use **64-bit Windows PowerShell 5.1** and **NSIS 3.11 or later**:

```powershell
.\Build.ps1 -MakeNSIS 'C:\Program Files (x86)\NSIS\makensis.exe'
```

The build runs the checks and creates `dist\DriverLoom-Setup.exe` plus its SHA-256 checksum. See the [development guide](docs/DEVELOPMENT.md) for installer testing, diagnostics and source catalogs.

## License

[MIT](LICENSE). See [artwork credits](assets/ATTRIBUTION.md).
