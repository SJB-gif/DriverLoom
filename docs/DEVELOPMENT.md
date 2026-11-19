# Development

## Build and test

Use Windows 10/11 x64, 64-bit Windows PowerShell 5.1 and stock NSIS 3.11 or later:

```powershell
.\Build.ps1 -MakeNSIS 'C:\Program Files (x86)\NSIS\makensis.exe'
```

The build prepares icon formats, compiles the native x64 .NET Framework host, runs engine, manufacturer, coverage, UI/theme and native-host checks, and creates `dist\DriverLoom-Setup.exe` with a SHA-256 sidecar. Both the installer finish page and Start menu launch `DriverLoom.exe`. The embedded engine uses Windows PowerShell 5.1. No extra runtime download is required.

On a disposable Windows user or clean test machine, run:

```powershell
.\Test-Installer.ps1
```

This installs into a temporary path with spaces, verifies payload hashes, taskbar identity and icon metadata, tests both launch paths, and uninstalls. It refuses to replace an existing installation. Tests isolate saved settings and do not install drivers, reboot, write to USB or flash firmware.

GitHub Actions runs the build and installer checks and uploads the EXE and checksum as a workflow artifact. The workflow has read-only repository permissions. Publishing a GitHub release is a separate operation.

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
