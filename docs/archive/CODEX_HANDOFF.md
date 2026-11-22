# Hardware Update Launcher — Codex handoff

## Where the project stands

As of 19 November 2026, the latest build is **0.1.1**, an unsigned x64 Windows installer built with NSIS. No Git repository, commit, push, Actions run or GitHub release was created for this project. The destination owner, repository and visibility still need to be supplied by the user.

The first build was `HardwareUpdateLauncher-Windows-x64.zip`. It contained a portable launcher, scripts and source files. The user reported that it did not work and clarified that end users should download **one installer EXE**. The exact failure and whether it happened before or after the app window opened were never established. The replacement `HardwareUpdateLauncher-Setup.exe` uses NSIS, installs the app for the current user, creates a Start menu shortcut and registers an uninstaller. The installer starts Windows PowerShell directly through the installed startup script. The user has yet to confirm a successful Windows launch.

This handoff archive is the current source tree, including the installer changes. It omits the superseded standalone launcher, the reference ArtCraft executable and all built binaries. The standalone 0.1.1 installer was delivered separately. Its SHA-256 is `f12fb7ba4eafe3770be0240f79c811e0f67c9f43470d50aef86665ebee6360fc`.

## Intended product

- Open-source Windows utility inspired by ArtCraft Launcher's GitHub-oriented update workflow. The ArtCraft executable was inspected as a reference. This project has its own implementation.
- On the first run, identify the motherboard and BIOS, RAM, HDD/SSD, CPU and chipset, GPU and applicable driver devices. Record manufacturer, exact model, part or SKU, hardware IDs, board revision, and installed firmware or driver version where exposed. Resolve and save official vendor sources once so later scans can reuse them.
- Combine compatible updates in an **Update All** action. The intended product includes support for manufacturer-only drivers where compatibility, integrity and publisher can be verified. The current implementation applies eligible Windows Update offers only.
- Make BIOS checks and USB preparation optional and off by default. Where supported by the vendor, guide the user through preparing a BIOS file and copying it to the USB. Leave the actual flash to the vendor workflow.
- End users download a single `HardwareUpdateLauncher-Setup.exe`. GitHub holds the source and release artifacts.

## Current implementation

| File | Role |
| --- | --- |
| `App.ps1` | Windows Forms interface, scan controls, saved sources, settings, BIOS guide and USB file copy |
| `Engine.ps1` | Windows hardware inventory, manufacturer version checks, GitHub catalog/release lookup and Windows Update offer filtering |
| `Install.ps1` | Elevated Windows Update installation of approved update IDs and revisions, result reporting and reboot handling |
| `Launch.ps1` | Application entry point and startup error reporting |
| `Setup.nsi` | Install and uninstall for the current user, Start menu shortcut and optional first launch |
| `catalog.json` | Empty starter catalog. Uses exact hardware identity and official vendor domains. |
| `Test-Engine.ps1` | PowerShell syntax and engine checks |
| `.github/workflows/build.yml` | Existing Windows Actions build workflow. Uploads a workflow artifact. GitHub Releases publishing has yet to be configured and verified. |

The app scans on startup and saves state to `%LOCALAPPDATA%\HardwareUpdateLauncher\inventory.json` and `settings.json`. The files can contain hardware identifiers. Keep them out of Git and any public issue attachments unless reviewed and redacted.

Built-in automatic vendor checks cover Samsung retail 990 PRO, 990 EVO Plus, 990 EVO and 980 PRO firmware. Other hardware can use a recognised vendor portal, a user-saved exact page or feed with a version pattern, or a matching reviewed catalog entry. Broad automatic discovery and vendor-specific installations are still open. RAM and CPU entries are generally inventory only. Windows Update offers are filtered to exclude identified firmware and packages that require interaction. **Update All** requests administrator approval before applying eligible Windows Update drivers. BIOS USB preparation copies a selected, already-prepared file to a selected USB volume. The guide does not format a drive or flash firmware.

The optional GitHub setting accepts `owner/repository`. It reads the latest published release tag and `catalog.json` from the `main` branch. It displays a release link and consumes catalog metadata. It does not currently self-update or run remote scripts.

## Verification and first tasks in Codex

1. Extract this ZIP and use its root as the project root. Confirm the GitHub owner/repository and whether to use an existing repo or create one. Confirm visibility before creating or publishing a repo.
2. Run `powershell -NoProfile -File Test-Engine.ps1` and build the installer with NSIS 3.11 or later using `makensis Setup.nsi`. Review the Windows workflow, including NSIS availability, and verify it builds the same installer deliverable. The current workflow has never run on GitHub.
3. On a clean Windows 10/11 x64 environment, run the installer as a regular user. Verify the finish-page launch and Start menu shortcut, inventory and initial scan, relaunch and uninstall. Check `%LOCALAPPDATA%\HardwareUpdateLauncher\startup-error.log` if the app fails after the PowerShell entry point runs. Capture the exact error and which launch path failed. Use a controlled Windows test system for actual driver installs and reboot handling. Test BIOS opt-in and USB copy without performing a flash.
4. When the target repository and publish scope are confirmed, commit and push the source and record the workflow result. Publish the single installer EXE as a GitHub Release asset after a Windows smoke test, and report the repo and release URLs. Set or document the catalog's repo slug once the destination is known.
5. Continue the manufacturer-source work separately from getting the app running. Start with one vendor and verify exact hardware and OS matching, version ordering and official package integrity before offering that vendor's driver through **Update All**.

Previous checks passed for PowerShell syntax and engine tests on Linux, a live Samsung version lookup for the four supported retail families, NSIS compilation, installer payload extraction and byte comparison, and startup log writing with an induced error. A local Wine runtime could not initialise. Windows install, first launch, the live Windows Update queue and USB copy still need testing on Windows.
