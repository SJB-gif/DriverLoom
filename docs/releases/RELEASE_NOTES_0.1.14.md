# DriverLoom 0.1.14

- Added 13 bundled manufacturer logos with dark/light variants and hardware-category fallbacks. No logo downloads occur while the app is running; artwork sources, checksums and upstream notices are included.
- Added Check app updates in Settings and a startup app-update check, enabled by default with a separate off switch.
- A newer published stable release opens a popup with the official installer download and release notes. Downloads open in the browser and require the user to run setup. Test builds never offer an older public release as an upgrade.
- Setup closes running installed DriverLoom windows and tray copies before replacing files. It targets the exact executable path, current user and Windows session. Active driver installation blocks setup; unidentifiable or cross-session instances require manual closure. Unrelated PowerShell processes and same-name executables are not terminated.
- Added an explicit graceful-exit protocol for new versions and a scoped Windows Restart Manager fallback for older native versions. Setup prevents a new DriverLoom instance from opening during file replacement and preserves saved preferences and shortcuts.

This test build is newer than the current public release, so a successful app update check is expected to report that no newer published release is available.

Release publishing and signing remain on hold.
