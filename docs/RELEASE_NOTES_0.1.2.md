# Hardware Update Launcher 0.1.2 - release draft

Prepared locally on 19 November 2026. No repository, tag or release has been published.

Windows setup now builds with stock NSIS 3.11. The previous source requested an amd64 stub missing from the standard Windows compiler package. Setup uses the bundled Unicode stub, rejects unsupported OS architectures and explicitly launches 64-bit Windows PowerShell. The installer remains a single `HardwareUpdateLauncher-Setup.exe` for Windows 10/11 x64.

Startup now checks its PowerShell host and STA mode and records host details and the underlying exception in the startup log. Installer metadata reports 0.1.2, and uninstall asks the user to close the app before removing its scripts.

The source includes repeatable build, Windows Forms startup and installer lifecycle checks. Local hardware inventory, settings, compiler downloads and built binaries are excluded from Git. The workflow produces an installer and checksum without publishing a release.

The installer is unsigned. Windows Update is still the only automatic installation source; manufacturer-only packages remain separate. BIOS features remain off by default, and the USB guide still neither formats a drive nor flashes firmware.

See [verification evidence and remaining checks](VERIFICATION.md) before publishing. The original portable failure was not conclusively reconstructed, and the separately delivered 0.1.1 installer was unavailable for hash verification.
