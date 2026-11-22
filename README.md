# DriverLoom

Check hardware updates from official sources in one simple Windows app.

**[Download for Windows](https://github.com/SJB-gif/DriverLoom/releases/latest/download/DriverLoom-Setup.exe)** · [Release notes](https://github.com/SJB-gif/DriverLoom/releases/latest) · [Supported hardware](docs/COVERAGE.md)

Windows 10/11 x64. One installer, installed for the current user. The installer is currently unsigned.

**Latest release: [0.1.22](https://github.com/SJB-gif/DriverLoom/releases/tag/v0.1.22).** Development installers are available from [GitHub Actions builds](https://github.com/SJB-gif/DriverLoom/actions/workflows/build.yml). Code signing remains on hold.

## Code signing policy

[SignPath Foundation](https://signpath.org/) is the planned route for free open-source signing. No application has been submitted and signing is not enabled. See the [code signing policy](CODE_SIGNING_POLICY.md) for the intended process and privacy details.

## Get started

1. Download and run **DriverLoom-Setup.exe**. Setup closes running DriverLoom windows and tray copies before upgrading. Finish any active driver installation first. Your settings are kept.
2. Choose whether to add **Start menu** and **Desktop** shortcuts.
3. Open **DriverLoom**. By default, it checks on opening. Use the refresh arrow to check again.
4. When updates are found, **Update All** opens a review list. Eligible Windows Update drivers can be installed together after confirmation. **Download update** saves a supported manufacturer package; **Install update** opens its verified installer when you choose. Other devices use the indicated app or official website.

## Features

- Installed and available versions, with clear update status.
- Checks for supported NVIDIA, AMD, Intel, ASUS and Samsung hardware.
- Names the software used to update devices that need another app, with official web links.
- Show or hide items without automatic checks in the hardware list.
- Windows Update shortcuts in Settings and the diagnostic lists.
- Dark, light and system themes, plus an optional BIOS/USB preparation guide.
- Bundled manufacturer logos, with hardware category icons as fallbacks.
- Startup and manual checks for published DriverLoom updates.
- Open supported, verified installed vendor apps directly from device actions.
- Hardware categories such as Graphics, Storage and Audio & media, with individual device versions and actions.
- Download, verify and open DriverLoom's own update installer without using a browser.
- Managed downloads for matched AMD chipset, Radeon Adrenalin WHQL Recommended and desktop NVIDIA WHQL packages.
- Verified ASUS board-specific LAN, Wi-Fi, Bluetooth and audio downloads, with automatic unpacking and ASUS setup handoff.

Open the gear for Settings, About and Help. Double-click a device for details.

Devices remain visible after a successful check. Green **Up to date** means the installed version matches or exceeds the checked source; **Vendor details** keeps the official link available. **Update available** identifies a newer version. Failed or ambiguous comparisons show **Check unavailable**, with the reason in device details.

The list is grouped by **hardware type**. Click Device for A–Z/Z–A within categories, or Status for **updates first**, then up-to-date devices, then application names A–Z. Status sorting puts categories containing updates first and keeps each heading with its devices. Unavailable checks follow other statuses. Installed, Available and Action do not change the sorting. Your selected order stays in place as results refresh.

Enable **Show items without automatic checks** in Settings to include devices managed by other software or a manual support page. Their status names where to go: for example, **CORSAIR iCUE**, **CORSAIR SSD Toolbox** or **Microsoft Gaming Services**. Use **Open update page** for the official website. These labels do not mean an update is available. Unknown software owners are not assigned guessed download links.

Settings save when you click back onto the main window or press **Esc**. BIOS and firmware options are on the right; background options are on the left.

## Installed vendor apps

When a supported app is detected, its action becomes **Open iCUE**, **Open NVIDIA App**, **Open AMD Install Manager** or the corresponding app name. DriverLoom reads local installation registrations and standard program locations on opening and during hardware checks, verifies the executable's vendor signature and checks it again before opening. Custom local installation folders can be discovered through their registrations. Apps open only when you select an Open action; no update command or silent installation is sent.

Supported launchers are AMD Install Manager, AMD Software as a graphics-only fallback, NVIDIA App, CORSAIR iCUE, CORSAIR SSD Toolbox and Samsung Magician. Other devices retain their official website actions.

Devices stay in their hardware category even when they share an app. Each keeps its own installed/available version, status and action. Double-click a device for details; right-click for its official website. App-managed firmware is not labelled up to date without a verified comparison.

## Manufacturer downloads

For a verified newer **AMD chipset**, **Radeon Adrenalin WHQL Recommended**, **desktop NVIDIA WHQL** or supported **ASUS board-specific driver** package, the action becomes **Download update**, including when a vendor app is installed. DriverLoom refreshes the device and official offer, downloads from the matching official source with progress on the action button and Cancel, and validates the package. The button then becomes **Install update**. Setup opens only when you select Install update. DriverLoom hands off to the external vendor installer with its normal Windows prompts; it does not run installation inside DriverLoom or show a completion dialog. You can close DriverLoom while the vendor setup continues. Refresh afterward to read the installed version. You do not need to visit the download page or find the downloaded file.

Radeon downloads appear on the **AMD Software: Adrenalin Edition** row, where installed and available package versions can be compared. The exact Radeon GPU and its Windows product page determine the package, including for supported discrete Radeon cards on Intel systems and desktop Ryzen integrated graphics. The individual GPU driver row keeps its own display-driver version and details. Optional/beta packages, ambiguous GPU matches and Windows versions older than Windows 10 21H2 are excluded from managed Radeon downloads.

ASUS downloads initially cover matched **Intel I225/I226 LAN**, **MediaTek/RZ616 Wi-Fi and Bluetooth**, and **Realtek USB audio** on supported ASUS motherboards. The exact board and Windows feed supplies the ZIP. DriverLoom checks a published ASUS checksum when available, extracts it with file and size bounds, verifies the ASUS setup signature, and requires an x64 INF with the exact device ID and driver version verified against its trusted Windows catalog. Every extracted file is hashed and checked again before setup starts. Some older ASUS feeds do not publish ZIP checksums; those downloads rely on the official HTTPS source plus the driver/catalog and setup checks. A matching title or version alone is insufficient. Unsupported layouts are rejected; the official website remains available.

Complete or cancel the vendor setup, then use the refresh arrow in DriverLoom. Versions are read again; opening an installer is never reported as a successful driver update. Windows security prompts, licence review, installation options and restart instructions remain with the vendor installer. Downloads and installations start only from your explicit action, one package at a time.

NVIDIA notebook packages, unsupported Radeon/ASUS variants, other OEM bundles, BIOS and storage/peripheral firmware retain their app or official website action. No serial-number portal, account, forced restart or silent driver-install switch is sent by DriverLoom. ASUS setup controls its own bundled installation steps. If source matching, download bounds or signature validation fails, the package is not run. Official links remain available from the device's context menu.

## Backups and rollback

Manufacturer downloads are saved under `%LOCALAPPDATA%\HardwareUpdateLauncher\drivers`. They remain available after closing DriverLoom. Installation is a separate action; downloading never starts setup. Saved files, publisher signatures and the current device/board are checked again before use. A device's context menu can download the update again if a saved copy is unusable.

In Settings, **Back up installed drivers** exports the currently installed **third-party Windows driver packages** locally, using Windows PnPUtil. It does not try to reconstruct unavailable old installers from the internet. The first successful export is kept as the original backup. Backup is a separate Settings action; Install update does not run a backup first. Backups do not include vendor apps, their settings, BIOS, peripheral/SSD firmware or Windows inbox drivers. Windows Update remains the source for inbox components.

**Rollback** opens a device dropdown and its saved versions. A saved vendor package opens its normal installer, which controls whether reinstallation or downgrading is supported. For exported **network, Bluetooth, audio and display** packages, Restore selects the exact saved driver for the same present device through Windows. It validates the catalog and all saved files, backs up the current version, and stages a protected copy before asking Windows to install the selected compatible driver. Other driver classes open Device Manager and the saved files for manual recovery. DriverLoom never removes an active driver or forces a restart.

Backups are stored under `%LOCALAPPDATA%\HardwareUpdateLauncher\backups`. Retention keeps at most three saved packages per device: the original backup, a previous saved version and the latest downloaded installer. With fewer versions, it keeps fewer copies. Each saved version can include its ZIP and complete extracted setup folder. Setup folders opened during the current Windows boot are protected from moving or deletion so vendor child processes can finish, even after DriverLoom closes. Startup maintenance after a reboot removes obsolete preparation folders and resumes retention; the newest extracted folder for each retained version stays available. This can temporarily keep extra copies. If the boot session cannot be verified, launched setup folders are preserved. Existing downloads cannot recreate installers for versions that were never saved. The original means the first successful backup, not a guarantee of the factory or Windows-preferred version.

Export and Windows restore request administrator permission for the same Windows account. Cancelling permission leaves installation untouched. Check the reported backup failures before relying on a saved version. A restore can interrupt the affected device and may require a restart; DriverLoom reports Windows' result and refreshes the installed version.

## Checks and background operation

In Settings, choose **Manual**, **On opening** (default), **Daily** or **Weekly**. Daily and weekly checks respect the last check time and run only while DriverLoom is open or kept in the tray. Checks never install drivers automatically.

**Keep running in the tray** and **Start with Windows** are both off by default. With tray mode enabled, closing the window hides it; use the tray icon to reopen, check or exit. Windows startup opens the window unless tray mode is also enabled. DriverLoom does not install a background service or wake the PC to check.

## DriverLoom updates

DriverLoom checks its own latest stable GitHub release on opening. Turn **Check app updates on opening** off in Settings to disable that check, or use **Check app updates** whenever you choose. App checks are separate from the hardware-check schedule and optional source catalog.

When a newer published version is available, a popup offers **Download and install** and **Release notes**. Downloads start only when you choose that action. DriverLoom shows progress and a Cancel button, verifies the release's SHA-256 digest, file size and installer version, then opens normal interactive setup. Windows security checks and shortcut options remain in place. Failed or cancelled downloads are removed; use **Check app updates** to retry. No browser is needed for the installer; release notes still open in your browser.

Setup closes DriverLoom safely and keeps its preferences. An active driver installation blocks the upgrade. Hardware checks and installation actions pause while the app update is downloading or setup is open. Copies in another Windows session, or an instance setup cannot safely identify, need to be closed manually. A tray startup defers the popup until you reopen DriverLoom.

Only published stable releases are offered. Test installers from Actions can be newer than the public release and will not be downgraded.

## Current limits

Automatic driver installation supports eligible **Windows Update drivers only**. Supported manufacturer downloads wait for your Install update action before opening their normal interactive installer; other packages use the indicated app or website. Coverage varies by device; see the [coverage guide](docs/COVERAGE.md). DriverLoom does not flash firmware or restart your PC automatically.

## Privacy

DriverLoom requires no account and contains no analytics, advertising or usage tracking.

- **Local data:** hardware inventory, preferences, saved sources and diagnostic logs are stored on your PC in `%LOCALAPPDATA%\HardwareUpdateLauncher`. DriverLoom does not automatically upload these files.
- **Copy list:** copies the displayed device or package names and reasons to the Windows clipboard when you select it.
- **Update checks:** checks contact Windows Update and manufacturer sites at the frequency you select, or when you use refresh. Some manufacturer lookups include hardware-model and Windows-version details.
- **App update checks:** the startup check contacts the public DriverLoom GitHub release API without an account, hardware details or diagnostic files. You can disable it in Settings. Manual app checks contact the same API.
- **App downloads:** choosing Download and install retrieves only DriverLoom's own installer from its public GitHub release and GitHub's release storage. Verified installers are saved under the local data folder's `downloads` directory. No account or diagnostic upload is involved. Verification checks integrity; the installer remains unsigned while signing is on hold.
- **Manufacturer downloads:** choosing a device's Download update action contacts its official metadata and download servers. The device and offer are checked again locally before and after download. Verified manufacturer packages are stored under `%LOCALAPPDATA%\HardwareUpdateLauncher\drivers`. A local SHA-256 detects changes before launch; it is not presented as a checksum published by the manufacturer. No hardware inventory or diagnostic file is uploaded. The vendor installer applies its own privacy policy.
- **ZIP setup folders:** Install update checks the saved file format. Supported ASUS ZIPs are extracted with their full folder structure into a `setup-...` subfolder beside the ZIP, under the saved driver version in `drivers` or `backups`. Only the verified `AsusSetup.exe` is opened, with that folder as its working directory. The ZIP and extracted files remain available after DriverLoom closes. Failed or cancelled preparation removes its new folder and keeps the ZIP. Catalog verification is read-only and does not register catalogs or install drivers.
- **Optional catalogs and links:** catalog metadata is fetched if you configure a repository. Opening a vendor, release notes or repository link visits that site in your browser. Manufacturer logos are bundled locally and make no network requests.
- **Installed applications:** launcher discovery reads local installation and executable metadata; app paths are not uploaded. Open actions start the verified vendor application with its normal permissions and settings. Those applications apply their own privacy policies.

- **Driver backups:** driver files, device identifiers and version metadata stay in the local `backups` directory. Backup does not contact the internet or upload diagnostics. Windows prompts before privileged export or restore.

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
