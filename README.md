# DriverLoom

An MIT-licensed Windows 10/11 x64 prototype for recording hardware, checking saved manufacturer sources and applying eligible Windows Update drivers.

Current source: **0.1.5**, maintained at [SJB-gif/HardwareUpdateLauncher](https://github.com/SJB-gif/HardwareUpdateLauncher). See the [0.1.5 changes](docs/RELEASE_NOTES_0.1.5.md), [coverage matrix](docs/COVERAGE.md) and [earlier Windows verification](docs/VERIFICATION.md). No release has been published yet.

## Run it

Open `DriverLoom-Setup.exe`. Setup installs for the current user and creates a **DriverLoom** Start menu shortcut and an uninstall entry with the new chip-and-update icon. It upgrades earlier Hardware Update Launcher builds using the existing install location and data directory, preserving saved sources and preferences. Close the running app before upgrading. The installer is unsigned. The launcher uses Windows PowerShell 5.1 with a process-scoped execution policy setting. Machine policy takes precedence. A startup failure inside the launcher produces a dialog and usually writes `%LOCALAPPDATA%\HardwareUpdateLauncher\startup-error.log`.

1. The main screen has one **Check & Update All** button. It refreshes the inventory and manufacturer checks, then asks before installing supported Windows Update packages. The opening background scan only checks; it cannot start installations. Windows-managed components, identity-only entries and package subcomponents are kept out of the results list.
2. Manufacturer updates requiring manual installation have a **Review update** link. Other successful checks have **Vendor details**. Their published versions are never substituted for unrelated component versions. Automatic manufacturer-package installation is not implemented in this test build.
3. **Settings > Unsupported items** lists devices without a verified automatic version check, with a reason. Unreachable sources are treated as unsupported for that scan, never current. **Settings > Windows Update exclusions** shows offers withheld for unsupported class, possible interaction, firmware, missing identity or duplicate targets. These offers never enter the install queue.
4. **Settings > Appearance** offers Dark (default), Light and Match system. The preference applies when saved and on the next start. Advanced source overrides remain available from **Settings > Advanced sources** or the unsupported list's right-click menu. Save an exact official page/feed and, optionally, a pattern with a named `version` group. BIOS opt-in and the USB guide are in Settings. The guide copies only an explicitly selected, prepared file; formatting and flashing remain vendor-managed steps. **About** shows the app and basic system identity, and **Help** explains the combined action.

The inventory and saved links live in `%LOCALAPPDATA%\HardwareUpdateLauncher\inventory.json` and `settings.json`. The inventory includes motherboard and BIOS details, RAM part numbers, CPU model, storage firmware reported by Windows, display drivers and selected PCI chipset, networking, media and storage drivers. Available fields depend on what the hardware and Windows expose. Ordinary RAM modules and CPUs are inventory entries. The launcher keeps its hardware inventory local. It contacts Windows Update, saved manufacturer URLs and the optional GitHub repository.

## Coverage

- Windows Update availability follows the Windows-configured update service, its compatibility decisions and any organisation policy. It can offer a different package from the manufacturer's website.
- NVIDIA GeForce checks resolve the exact GPU in NVIDIA's product lookup, require that GPU and the Windows version in supported-products metadata, and compare non-beta WHQL Game Ready or legacy Security Update drivers. Product IDs are resolved dynamically for supported RTX/GTX/GT families, rather than pinned to one PC. Windows driver versions are converted to NVIDIA's published numbering.
- AMD checks compare installed **AMD Chipset Software** and **AMD Software: Adrenalin Edition** package versions with official chipset, Ryzen integrated-graphics or discrete Radeon RX product pages. Discrete Radeon checks also work on Intel PCs. Different AMD GPUs keep their own product sources; package and component versions remain distinct.
- Intel wireless checks require the exact adapter token in Intel's supported-products section and an explicit four-part driver version. AX200 uses its separate legacy product page. If the source is blocked, the model is absent or version data is ambiguous, the device moves to Unsupported items. Bluetooth and other Intel classes without a verified mapping are not reported as checked.
- ASUS motherboard checks validate the exact board model and OS in ASUS's driver feed. Component matching covers Intel I225/I226 LAN, MediaTek MT7922/RZ616 Wi-Fi and recognised onboard Realtek USB audio. A package for a different NIC, Wi-Fi vendor or motherboard is not selected. The board feed may contain older versions than Windows Update; these are shown as installed versions being higher, not upgrade recommendations.
- Samsung firmware checks now also cover recognised retail 950/960/970/980 families, including exact EVO versus EVO Plus matching. OEM drive codes remain unsupported unless an exact source is configured. Proprietary or serial-dependent Corsair, Seagate and other vendor workflows are explained in Unsupported items. A saved exact source or reviewed catalog entry still overrides built-in checks.
- **Update All** applies eligible Windows Update driver offers. Manufacturer-only packages and firmware remain separate. Firmware classes, identified firmware and interactive packages are excluded from the install queue. Duplicate offers for a single hardware ID and class are surfaced for review. Licences requiring extended review are deferred to Windows Update.
- Vendor pages can publish different numbering from the installed Windows driver. Only comparable version strings or recognised Samsung firmware revisions get ordered automatically. Other differences are shown for review. Check the exact model and revision before applying a vendor package.

## GitHub catalog and builds

The source has a GitHub Actions workflow that tests the PowerShell and builds a Windows x64 installer. The public source repository is `SJB-gif/HardwareUpdateLauncher`. The optional catalog setting uses unauthenticated reads; enter `SJB-gif/HardwareUpdateLauncher` in **Settings > Advanced sources** if desired. On each check the app reads `catalog.json` from the repository's `main` branch and queries published release metadata. Until the first release is published, the release lookup has no result. The catalog is data. The app does not download or execute scripts or installer binaries from the repository.

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

This regenerates the icon from vector drawing commands, runs engine, manufacturer matching, cross-PC coverage and Windows Forms startup/theme checks, then writes `dist\DriverLoom-Setup.exe` and its SHA-256 sidecar. End users need only the installer EXE. The setup program uses NSIS's bundled x86 Unicode stub, accepts only native x64 Windows 10/11, and explicitly starts 64-bit Windows PowerShell. The finish-page command uses `Sysnative` from the 32-bit setup process; the Start menu shortcut uses `System32` from the Windows shell. UI helpers compile locally using Windows' included .NET compiler; no extra runtime download is required.

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
