# DriverLoom 0.1.8

The first public release of DriverLoom, a Windows app for checking hardware updates from official sources.

- Automatic checks on opening, with a refresh arrow for later checks.
- Installed and available versions for supported NVIDIA, AMD, Intel, ASUS and Samsung hardware.
- An Update All review list for eligible Windows Update drivers and manually installed manufacturer packages.
- Unsupported devices and excluded offers explained in Settings.
- Dark, light and system themes, an optional BIOS/USB guide, and the DriverLoom wordmark and loop icon.
- A native x64 launcher with the corrected taskbar icon and application identity.
- Setup options for Start menu and desktop shortcuts. Start menu is selected by default; desktop is optional. Upgrades remember your choices.

## Install

Download **DriverLoom-Setup.exe** from the release assets and run it. Choose your shortcut locations during setup. Close an existing DriverLoom instance before upgrading; preferences and saved sources are retained.

Requires Windows 10/11 x64. The installer is unsigned. A SHA-256 checksum is provided alongside the installer.

## Current limits

Automatic installation covers eligible Windows Update drivers only. Manufacturer packages use official review links and require manual installation. Coverage varies by hardware. DriverLoom does not flash firmware or restart the PC automatically.

Build validation covers hardware/source matching, UI startup and themes, native hosting, taskbar metadata, installer payloads, all shortcut choices, upgrade persistence, both Windows launch paths and uninstall. The taskbar icon fix was also confirmed in user testing. No drivers or firmware were installed during automated validation.
