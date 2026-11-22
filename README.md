# DriverLoom

Check hardware updates from official sources in one simple Windows app.

**[Download for Windows](https://github.com/SJB-gif/DriverLoom/releases/latest/download/DriverLoom-Setup.exe)** · [Release notes](https://github.com/SJB-gif/DriverLoom/releases/latest) · [User guide](docs/USAGE.md) · [Supported hardware](docs/COVERAGE.md)

Windows 10/11 x64. Latest release: **[0.1.22](https://github.com/SJB-gif/DriverLoom/releases/tag/v0.1.22)**. One installer, installed for the current user. **Currently unsigned; code signing is on hold.**

## Get started

1. Run **DriverLoom-Setup.exe** and choose your Start menu and desktop shortcuts. Setup closes running DriverLoom copies before upgrading and keeps your settings. Finish any active driver installation first.
2. Open DriverLoom. It checks on opening by default; use the refresh arrow to check again.
3. Choose **Download update**, then **Install update**, for a supported manufacturer package. Its verified installer opens with normal Windows prompts. Other devices open the indicated app or official website.

**Update All** reviews available updates. Eligible Windows Update drivers can be installed together after confirmation. Manufacturer installers open separately when you choose. DriverLoom does not flash firmware or restart your PC automatically.

## What it does

- Shows installed and available versions, grouped by hardware type, with updates-first sorting.
- Checks supported AMD, NVIDIA, Intel, ASUS and Samsung hardware against official sources.
- Manages verified AMD chipset/Radeon, desktop NVIDIA and supported ASUS driver downloads, including ZIP extraction.
- Opens supported installed vendor apps and identifies devices that need another update method.
- Saves downloaded installers, exports installed third-party drivers and provides backup/rollback controls.
- Offers dark, light and system themes, optional tray/scheduled checks and DriverLoom app updates.

Coverage varies by device. See the [coverage guide](docs/COVERAGE.md) and [user guide](docs/USAGE.md) for download validation, backups, settings and current limits.

## Privacy

No account, analytics, advertising or usage tracking. Inventory, settings, downloads, backups and diagnostic logs stay on your PC; DriverLoom does not automatically upload them. Update checks contact Windows Update, official manufacturer services and GitHub. These services receive normal connection information, and some manufacturer checks include model and Windows-version details. Checks never install drivers automatically.

App checks can be disabled, and hardware-check frequency is configurable. See [privacy details](docs/USAGE.md#privacy) and the [code signing policy](docs/CODE_SIGNING_POLICY.md).

## Support

Provided as-is by a volunteer-maintained project. **No individual support or promise of a reply, fix or ongoing maintenance.** Optional bug reports belong in [GitHub Issues](https://github.com/SJB-gif/DriverLoom/issues) and may not be reviewed or answered. Please do not use personal email or social accounts for support. Remove personal information from reports before posting.

## Source and development

| Folder | Purpose |
| --- | --- |
| [src](src) | App source and bundled artwork |
| [installer](installer) | Windows setup and shutdown helper |
| [scripts](scripts) | Build tools |
| [tests](tests) | Automated checks |
| [docs](docs) | Guides, coverage and historical notes |

Build from the repository root using **64-bit Windows PowerShell 5.1** and **NSIS 3.11 or later**:

```powershell
.\scripts\Build.ps1 -MakeNSIS 'C:\Program Files (x86)\NSIS\makensis.exe'
```

The build runs the checks and writes the installer and SHA-256 checksum to `dist/`. See the [development guide](docs/DEVELOPMENT.md). Test installers are available from [GitHub Actions](https://github.com/SJB-gif/DriverLoom/actions/workflows/build.yml).

## License

[MIT](LICENSE). [Artwork credits](src/assets/ATTRIBUTION.md).
