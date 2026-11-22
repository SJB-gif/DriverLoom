# Hardware Update Launcher 0.1.3 - test build

Prepared on 19 November 2026. This is an installer for testing; no GitHub Release or tag is published.

## Manufacturer checks

- Exact-product NVIDIA GeForce Game Ready checks, with Windows-family matching, supported-GPU verification, WHQL/beta filtering and conversion of Windows driver numbering.
- AMD chipset and Adrenalin package checks from official pages, using the installed package versions and the detected chipset or supported Ryzen integrated-graphics processor. Package and individual component versions remain distinct.
- Exact-board ASUS driver feeds for Intel I225/I226 LAN, MediaTek MT7922/RZ616 Wi-Fi and recognised onboard Realtek USB audio. Model/OS mismatches and ambiguous or failed responses show an unchecked result.
- Existing saved-source/catalog overrides and Samsung firmware checks remain available. Unsupported devices are explicitly unchecked or linked to the relevant package; Windows-managed devices are identified separately.

Manufacturer checks read public metadata only. They send public product/model information, not serial numbers, to official vendor endpoints. Select a row to see its source and comparison details, then use Open source for vendor review. Manufacturer-only packages are not automatically installed by Update All.

## Excluded Windows Update offers

The Windows Update tab retains excluded packages and displays all reasons: unsupported class, possible interaction, missing hardware ID, firmware or duplicate targets. Its summary distinguishes total offered, eligible and excluded counts. The install queue and its confirmation/revalidation rules remain unchanged; excluded rows cannot enable Update All.

Old saved scans still load. Their missing exclusion data is identified until a fresh scan completes. Settings and local inventory remain outside Git. The installer includes the manufacturer adapter module and preserves saved user settings on upgrade.

## Verification

Build.ps1 runs the PowerShell parser/engine tests, manufacturer matching tests and real Windows Forms startup tests. Fixtures exercise exact GPU/board/OS rejection, NVIDIA numbering, AMD package comparisons, wrong-component rejection, per-scan caching, offline sources, duplicate offers and excluded-only UI state. Test-Installer.ps1 validates the updated payload and installation lifecycle on a clean Windows user. No driver install, firmware flash or reboot is part of these tests.

Official sources used by the adapters:

- [NVIDIA driver search](https://www.nvidia.com/en-us/drivers/)
- [AMD Ryzen driver downloads](https://www.amd.com/en/support/downloads/drivers.html)
- [ASUS board support](https://www.asus.com/support/)
