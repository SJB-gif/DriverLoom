# DriverLoom 0.1.5 - test build

No release or tag is published.

- Hardware Update Launcher is now named **DriverLoom**. The source repository remains `SJB-gif/HardwareUpdateLauncher`.
- A new chip-and-up-arrow icon appears in the app, installer, Start menu shortcut and uninstall entry. Vector source is in `assets/DriverLoom.svg`; `Build-BrandAssets.ps1` produces the PNG and nine-size Windows ICO.
- Charcoal surfaces, fine borders, clear status badges, device glyphs, version columns and a prominent combined action follow the supplied visual direction. Layouts and artwork are original.
- Settings now groups Appearance, Updates, BIOS, Coverage and Advanced sources. Dark is the default; Light and Match system are saved preferences. System appearance is resolved on startup and when preferences are saved.
- Existing installation identity, local data and saved manufacturer sources are retained. Setup replaces the old Start menu shortcut with DriverLoom; close the running app before upgrading.
- Startup checks cover the new branding, icon, legacy settings and all three appearance modes. The clean Windows installer checks verify payloads, shortcut icon, registration, both launch paths and uninstall.

Driver matching and installation rules are unchanged. Automatic installation covers eligible Windows Update drivers; manufacturer-only packages still require Review update. No driver installation or firmware flashing is performed during validation.

The user selected DriverLoom on 19 November 2026 after initial exact-name web searches. An exact-name GitHub repository search returned no matches on that date. This is an initial conflict check, not a guarantee of exclusive use.
