# Hardware Update Launcher 0.1.4 - test build

No release or tag is published.

- One main Check & Update All action with Settings, About and Help in a top menu. Startup only checks; a user-triggered combined action checks first and asks before installing supported Windows Update packages.
- Main results contain successful manufacturer checks and eligible Windows Update packages. Windows inbox components and package subcomponents are removed from the list. Unsupported items and excluded Windows Update offers move into Settings, with their reasons.
- Provider/INF-based classification retains third-party OEM packages even when Microsoft signs them. Raw identity needed for matching stays local; basic CPU/board/system information is in About.
- Broader adapters support legacy GeForce security drivers, discrete Radeon RX graphics on Intel and AMD systems, older recognised Ryzen families, Intel wireless product metadata and more Samsung retail SSD firmware families. Existing ASUS matching remains exact-board and component-specific.
- Cross-PC coverage tests verify that model-specific results are not tied to the development PC. Offline, blocked and ambiguous sources are unsupported rather than current.

Manufacturer installers remain manual through Review update links. Universal automatic manufacturer coverage and package installation are not claimed. See the [coverage matrix](../COVERAGE.md) for supported checks and current limits. Firmware flashing, formatting, driver installation and reboots are not performed during validation.
