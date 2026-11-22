# DriverLoom 0.1.6 - test build

No release or tag is published.

- A single integrated title bar displays the user's supplied DriverLoom wordmark. Settings is a gear; About and Help live inside Settings. Window controls retain minimize, maximize/restore and close.
- The bottom detail textbox is removed. A compact footer reports the last-check age and sources, with an official GitHub mark linking to the repository. Device details remain available by double-click and status tooltips.
- Opening checks automatically; an unboxed refresh arrow starts later checks. Update All is shown only after a fresh check finds updates. Its review list distinguishes manually installed vendor packages from eligible Windows Update drivers. Neither startup nor refresh can install anything.
- Hardware symbols now distinguish graphics, audio, Wi-Fi, Ethernet, storage and chipset devices. These are device-type symbols, rather than guessed manufacturer logos.
- The supplied loop artwork replaces the older chip icon. Windows icon frames cover 16 through 256 pixels. The original full wordmark is displayed directly from the supplied source sheet; provenance and imagegen preparation are documented in `assets/ATTRIBUTION.md`.
- A native .NET Framework x64 GUI host runs the existing Windows PowerShell engine in-process. The executable, application window and shortcut use DriverLoom branding and a shared taskbar AppID, replacing the PowerShell shortcut target. Existing install/data identity is retained for upgrades.

Validation covers cached versus fresh update actions, vendor-only review without installation, timezone-aware check age, dark/light/system startup, native STA hosting, 64-bit background jobs, paths with spaces, shortcut AppID persistence, and startup errors. Clean Windows CI additionally verifies installation, launch from a 32-bit setup host, Start menu launch/relaunch, payload hashes and uninstall. Desktop UI automation rejected custom DriverLoom windows in this environment; rendered previews and built-in checks were used instead. No drivers, firmware or reboots are applied during validation.
