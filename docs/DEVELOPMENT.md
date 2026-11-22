# Development

## Repository layout

| Folder | Contents |
| --- | --- |
| `src/` | App scripts, native launcher and bundled artwork in `assets/`. |
| `installer/` | NSIS setup and the graceful shutdown helper. |
| `scripts/` | Build tools and asset generation. |
| `tests/` | Engine, UI, download and installer checks. |
| `docs/` | User/developer guides, coverage and signing policy. Historical notes are in `archive/` and `releases/`. |
| `.github/` | GitHub Actions workflow. |

`catalog.json` stays at the repository root for existing app versions. Generated installers and executables go in ignored `dist/`; local working files belong in ignored `.local/`.

Run the commands below from the repository root. For a source-only launch, use `./src/Launch.ps1` in 64-bit Windows PowerShell 5.1 with STA enabled. The installed payload keeps its existing flat layout and data paths.

## Build and test

Use Windows 10/11 x64, 64-bit Windows PowerShell 5.1 and stock NSIS 3.11 or later:

```powershell
.\scripts\Build.ps1 -MakeNSIS 'C:\Program Files (x86)\NSIS\makensis.exe'
```

The build prepares icon formats, compiles the native x64 .NET Framework host, runs engine, manufacturer, coverage, UI/theme and native-host checks, and creates `dist\DriverLoom-Setup.exe` with a SHA-256 sidecar. Both the installer finish page and Start menu launch `DriverLoom.exe`. The embedded engine uses Windows PowerShell 5.1. No extra runtime download is required.

On a disposable Windows user or clean test machine, run:

```powershell
.\tests\Test-Installer.ps1
```

This installs into a temporary path with spaces, verifies payload hashes, taskbar identity and icon metadata, tests both launch paths, and uninstalls. It refuses to replace an existing installation. Tests isolate saved settings and do not install drivers, reboot, write to USB or flash firmware.

GitHub Actions runs the build and installer checks and uploads the EXE and checksum as a workflow artifact. The workflow has read-only repository permissions. Publishing a GitHub release is a separate operation.

Manufacturer SVGs are pinned to the Simple Icons commit and hashes in `src/assets/manufacturers/manifest.json`. The Windows build rasterises their paths with WPF into dark/light PNGs. Runtime rendering uses bundled PNGs and falls back to category symbols. Source notices and brand-source links are included in the installer.

`AppUpdates.ps1` reads only the fixed DriverLoom latest-release API, accepts published stable numeric versions and validates exact project release/installer URLs. It has no automatic binary execution or dependency on the configurable hardware catalog. Startup checks run in a background job; background tray starts defer the notification until the window is shown.

`VendorApps.ps1` discovers a fixed set of vendor frontends from local uninstall/App Paths registrations and program folders. It checks local executable names, company metadata and valid vendor Authenticode signatures. Launches use the verified executable and its working directory, with no extracted registry arguments, elevation request or update switches. The UI groups only visible devices sharing an actual detected launcher key/path; full per-device data remains in row metadata and the group details dialog. Smoke fixtures can inject a catalog only in smoke mode, where UI app launching is disabled. Launcher dispatch tests mock process creation and never open the user's vendor apps.

`SetupBridge.cs` closes only matching installed native executables owned by the current user in the current Windows session. New apps receive a named graceful-exit request; the driver-install guard can refuse it. Older native apps use Restart Manager with explicit process IDs and start times, without force shutdown. Legacy encoded driver-install commands are checked before that fallback. Unknown PowerShell instances, inaccessible process identities and cross-session copies cause a safe refusal instead of a broad process-name kill. Installer checks cover window/tray upgrades, busy refusal, a legacy tray fixture and an unrelated same-name decoy process on a clean runner.

## Shortcut options

Interactive setup offers Start menu and desktop shortcut checkboxes. On the first install, Start menu is selected and desktop is optional. Upgrades retain the previous selection. For silent deployment, `/STARTMENU=0` or `1` and `/DESKTOP=0` or `1` override the defaults:

```powershell
.\dist\DriverLoom-Setup.exe /S /STARTMENU=1 /DESKTOP=0
```

The installer checks exercise all four combinations, shortcut target/icon/AppID metadata, retained choices during an upgrade, and removal during uninstall.

## Diagnostics

Local state remains in `%LOCALAPPDATA%\HardwareUpdateLauncher` for compatibility with earlier builds:

- `settings.json`: preferences and saved manufacturer sources.
- `inventory.json`: the latest hardware inventory and check results.
- `startup-error.log` or `host-error.log`: startup diagnostics, when a failure occurs.
- `downloads`: verified DriverLoom update installers; cancelled or failed attempts remove their installer and partial file.

Managed app updates accept only newer stable releases from `SJB-gif/DriverLoom`, require the completed asset's GitHub SHA-256 digest, limit the installer to 64 MiB, constrain HTTPS redirects to GitHub release hosts, and check its embedded version before launch. The Internet-zone marker is retained and setup is interactive. `Test-AppDownloads.ps1` exercises downloads with synthetic response streams and a mocked launcher; it never executes downloaded files.

`Packages.ps1` implements the bounded AMD chipset / Radeon / desktop NVIDIA routes described in [coverage](COVERAGE.md). `Test-Packages.ps1` uses synthetic official feeds, streams and signatures to cover fresh device/offer resolution, exact hosts/paths/publishers, withdrawn packages, cancellation and file tampering. Radeon cases include hybrid systems, Intel CPUs, multiple Radeon GPUs, changed display drivers, optional/beta packages and Windows-specific selection. `Test-AppDownloadUI.ps1` covers app, chipset and Radeon workers, cancellation, handoff guards and rechecking, with process launches mocked. No driver package is executed by these tests.

`Test-DownloadRanges.ps1` checks complete byte assembly, strong validators, range boundaries, changed lengths, ignored ranges, truncation and cancellation with small synthetic streams. Transfer progress is throttled to keep large downloads from flooding the job's progress stream.

`AsusPackages.ps1` handles the bounded ASUS archive workflow; `AsusTrust.cs` uses read-only Windows SetupAPI and WinVerifyTrust/catalog APIs. `Test-AsusTrust.ps1` verifies a standard Windows catalog member, rejects changed bytes and checks x64 INF parsing. `Test-AsusPackages.ps1` uses synthetic archives and mocked signers/launches to test all four categories, IDs/classes/versions, unsafe ZIP paths/links, cancellation, changed offers and configuration tampering. Actual ASUS archives can be inspected separately without executing setup; vendor archives and binaries are never committed to the repository.

Review and redact hardware identifiers before attaching inventory or logs to a public issue. Include the DriverLoom version, Windows version, failing action and the relevant error.

## Optional source catalog

In Settings > Advanced sources, enter a public `owner/repository`, such as `SJB-gif/DriverLoom`. DriverLoom reads `catalog.json` from `main` and queries published release metadata without authentication. The catalog supplies version-source data; the app does not download or execute scripts or installers from it. The former `SJB-gif/HardwareUpdateLauncher` catalog name maps to the renamed repository.

Add reviewed entries to the `sources` array in `catalog.json`:

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

Catalog matching requires exact device fields, one matching source and a recognised manufacturer domain. BIOS, chipset and GPU entries also match system manufacturer, model and SKU where available. Local source overrides take precedence. A version pattern must capture one unambiguous version in a named `version` group. Save the final HTTPS URL if a support page redirects.

See [coverage and matching rules](COVERAGE.md) for adapter details and limitations.

DriverLibrary.ps1 owns bounded local manifests, verified saved installers, Windows exports and per-device retention. DriverUI.ps1 separates inline download from explicit install and provides backup/rollback controls. DriverBackupWorker.ps1 runs only after UAC approval, exports exact installed OEM INFs, or restores one compatible driver on one present device using DriverRestore.cs. Restore stages a hash-checked administrator-only copy, preserves Windows signature checks, and never deletes an active driver or reboots. Test-DriverLibrary.ps1 mocks export/signatures and exercises persistence, retention, tampering and a read-only native lookup; Test-DriverUI.ps1 tests explicit transfer, button progress, cancellation and second-click installation dispatch. Tests must never invoke Stage or native Select with install=true.

The native host embeds Host.manifest to declare Windows 10/11 support. Without it, .NET Framework reported Windows 8 inside the launcher while PowerShell background jobs reported Windows 11, so saved-package launch failed before setup. Test-Host compares the native host's reported OS/build and driver target with the Windows PowerShell process. Install update now verifies/prepares the saved package and starts external setup only; backup stays in Settings. UI checks reject automatic backup, in-app installation dialogs and assumptions that a process exit means successful installation.

Saved-package preparation detects EXE/ZIP headers, restricts ZIP execution to the verified ASUS adapter, and extracts into a short setup-XXXXXXXX folder within its saved version. Persistent roots are bound to their archive's library folder. Launch records protect the full version directory from pruning or moving for the current Windows boot, because vendor setup may leave child processes using it. Unknown boot sessions fail closed for cleanup. Startup maintenance retains the newest extracted folder and prunes obsolete unprotected preparations. Failed preparation deletes only its new root. Tests mock process launch and boot sessions to verify these paths without running setup.
