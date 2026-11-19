# Hardware Update Launcher

An MIT-licensed Windows 10/11 x64 prototype for recording hardware, checking saved manufacturer sources and applying eligible Windows Update drivers.

Current source: **0.1.2**, maintained at [SJB-gif/HardwareUpdateLauncher](https://github.com/SJB-gif/HardwareUpdateLauncher). See [Windows verification](docs/VERIFICATION.md) and the [release draft](docs/RELEASE_NOTES_0.1.2.md). No release has been published yet.

## Run it

Open `HardwareUpdateLauncher-Setup.exe`. Setup installs for the current user and creates a **Hardware Update Launcher** Start menu shortcut and an uninstall entry. The installer is unsigned. The launcher uses Windows PowerShell 5.1 with a process-scoped execution policy setting. Machine policy takes precedence. A startup failure inside the launcher produces a dialog and usually writes `%LOCALAPPDATA%\HardwareUpdateLauncher\startup-error.log`.

1. The launcher scans on opening and records a local inventory. Use **Check for updates** to refresh the inventory, compatible Windows Update offers and manufacturer versions at any time.
2. Choose a device, then **Open source** to find its official support page. **Edit source** saves the exact page or feed. An optional pattern with a named `version` group lets the launcher read it repeatedly. For HTML and JSON sources, the pattern runs on the response text. Leave the pattern blank to save a manual support link.
3. Review the **Windows Update offers** tab. **Update All** asks for confirmation and administrator approval, re-checks the approved update IDs and revisions, and applies each eligible offer through Windows Update Agent. The results window lists what installed or failed. It pauses remaining installations when a restart is required.
4. In **Settings**, enable **BIOS checks and USB preparation guide** if wanted. The guide shows the model, board revision and installed BIOS. If the manufacturer calls for copying a file to the USB root, use **Copy prepared file to USB** with the file already extracted and renamed according to the vendor instructions. The app copies to an explicitly chosen USB volume and refuses to overwrite an existing file. Formatting, making bootable media and flashing are vendor-managed steps.

The inventory and saved links live in `%LOCALAPPDATA%\HardwareUpdateLauncher\inventory.json` and `settings.json`. The inventory includes motherboard and BIOS details, RAM part numbers, CPU model, storage firmware reported by Windows, display drivers and selected PCI chipset, networking, media and storage drivers. Available fields depend on what the hardware and Windows expose. Ordinary RAM modules and CPUs are inventory entries. The launcher keeps its hardware inventory local. It contacts Windows Update, saved manufacturer URLs and the optional GitHub repository.

## Coverage

- Windows Update availability follows the Windows-configured update service, its compatibility decisions and any organisation policy. It can offer a different package from the manufacturer's website.
- The initial manufacturer adapter covers Samsung retail 990 PRO, 990 EVO Plus, 990 EVO and 980 PRO firmware. Other devices show a vendor portal where recognised, and can use a saved support link, a page pattern or a reviewed catalog entry. Browser-rendered version lists may require a vendor feed or manual review.
- **Update All** applies eligible Windows Update driver offers. Manufacturer-only packages and firmware remain separate. Firmware classes, identified firmware and interactive packages are excluded from the install queue. Duplicate offers for a single hardware ID and class are surfaced for review. Licences requiring extended review are deferred to Windows Update.
- Vendor pages can publish different numbering from the installed Windows driver. Only comparable version strings or recognised Samsung firmware revisions get ordered automatically. Other differences are shown for review. Check the exact model and revision before applying a vendor package.

## GitHub catalog and builds

The source has a GitHub Actions workflow that tests the PowerShell and builds a Windows x64 installer. The public source repository is `SJB-gif/HardwareUpdateLauncher`. The optional catalog setting uses unauthenticated reads; enter `SJB-gif/HardwareUpdateLauncher` in **Settings** if desired. On each check the app reads the latest release tag and `catalog.json` from the repository's `main` branch. Until the first release is published, the release lookup has no result. It displays a release when available and provides a link to the release page. The catalog is data. The app does not download or execute scripts or installer binaries from the repository.

Add reviewed entries to the `sources` array in `catalog.json` with this shape. Use the exact values from the local inventory and escape backslashes for JSON.

```json
{
  "Kind": "BIOS",
  "Manufacturer": "Example manufacturer",
  "Model": "Exact board model",
  "Part": "",
  "Revision": "1.0",
  "SystemManufacturer": "Example OEM",
  "SystemModel": "Exact system model",
  "SystemPart": "Exact system SKU",
  "Url": "https://example.com/exact-product/version-feed.json",
  "Pattern": "\"version\"\\s*:\\s*\"(?<version>[0-9.]+)\""
}
```

Catalog entries require exact device fields, a single matching source and a URL on the recognised manufacturer domain. BIOS, chipset and GPU entries additionally match the system manufacturer, model and SKU, where available. Local overrides take precedence. Save the final URL if a support page redirects. If a pattern returns several distinct versions, make it specific to the current listing.

To build from source, install stock NSIS 3.11 or later, then use **64-bit Windows PowerShell 5.1**:

```powershell
.\Build.ps1 -MakeNSIS 'C:\Program Files (x86)\NSIS\makensis.exe'
```

This runs the engine and Windows Forms startup checks, then writes `dist\HardwareUpdateLauncher-Setup.exe` and its SHA-256 sidecar. End users need only the installer EXE. The setup program uses NSIS's bundled x86 Unicode stub, accepts only native x64 Windows 10/11, and explicitly starts 64-bit Windows PowerShell. The finish-page command uses `Sysnative` from the 32-bit setup process; the Start menu shortcut uses `System32` from the Windows shell.

Run the following on a clean test user or disposable Windows machine to verify the installer:

```powershell
.\Test-Installer.ps1
```

This temporarily creates the actual per-user Start menu shortcut and uninstall registration, installs into a temporary path with spaces, verifies launch paths and payload hashes, and uninstalls. It refuses to replace an existing installation. Its startup tests use isolated settings; driver installation, reboot and BIOS flashing are not exercised. `Launch.ps1 -SmokeTest` opens and closes the real form without starting a hardware or network scan.

The Actions workflow runs the same build and installer checks and uploads the EXE plus checksum as a workflow artifact. It has read-only repository permissions and does not publish a release. A GitHub Actions run and an interactive finish-page check remain required before release approval.

## References

- [How Windows selects a driver package](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/how-windows-selects-a-driver-for-a-device)
- [Windows Update Agent API](https://learn.microsoft.com/en-us/windows/win32/api/_wua/)
- [Samsung storage firmware support](https://semiconductor.samsung.com/consumer-storage/support/tools/)
- [Microsoft BitLocker guidance for manufacturer firmware updates](https://learn.microsoft.com/en-us/troubleshoot/windows-client/windows-security/suspend-bitlocker-protection-non-microsoft-updates)
