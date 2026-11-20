# Coverage and source rules

DriverLoom targets Windows 10/11 x64 across different PCs. It does not claim that every manufacturer's device has a public, automatically comparable update feed.

| Family | Automatic check | Matching rule |
| --- | --- | --- |
| NVIDIA GeForce RTX/GTX/GT | WHQL Game Ready / Security Update versions | Dynamic official series/product IDs, exact GPU in supported products, matching Windows family, no beta |
| AMD chipset packages | Installed AMD Chipset Software versus official AM4/AM5 package | Chipset read from the motherboard model and AMD CPU identity; supports other board vendors |
| AMD Radeon RX discrete graphics | Adrenalin package from the exact RX 5000/6000/7000/9000 model page | Independent of CPU vendor; each GPU keeps its own source |
| Ryzen integrated Radeon | Adrenalin package from the detected desktop Ryzen product page | Exact processor source; missing/retired pages are unsupported |
| Intel wireless | Explicit installed-driver version from official product metadata | Model must appear in the supported-products section; AX200 has its own source; blocked/ambiguous pages are unsupported |
| ASUS LAN / Wi-Fi / audio / selected Bluetooth | Board-specific numeric driver versions | Exact board and OS response, component/vendor/USB-model gates; no sibling-board substitutions |
| Samsung retail NVMe SSD | Official model-specific firmware | Exact 950/960/970/980/990 retail family, unique firmware version; OEM model codes not inferred |
| Other manufacturers / OEM systems | Unsupported-item explanation and official support route | Vendor recognised from provider, model and public PCI/USB vendor codes; no false current or automatic install claim |

Generic Windows components are removed from the main results and unsupported count. Classification uses provider and published INF identity, with name-based compatibility for older saved scans. Microsoft-signed `oemNN.inf` packages remain eligible for manufacturer checking; signing alone does not mean a Windows inbox component. CPU, RAM and system identity remain available through About and internal matching.

Direct version comparison, managed downloads, vendor setup and automatic installation are separate capabilities. A successful manufacturer check never executes a package by itself. Update All opens a review list; eligible Windows Update offers can then be installed following confirmation, administrator approval and offer revalidation.

Managed downloads initially cover AMD chipset EXEs from the detected AM4/AM5 chipset's Windows section and desktop NVIDIA WHQL Game Ready/Security Update EXEs from the exact GPU/OS lookup. Only newer, comparable versions have Download & install actions. The device, installed version and official offer are refreshed before and after download; saved source/catalog URLs cannot authorise executables. Redirects must preserve the advertised versioned package path on approved vendor hosts. Windows must validate the exact manufacturer's signing identity. Downloads are bounded to 2 GiB, retain the Internet marker, and are hashed and revalidated immediately before execution. The local hash detects changes after validation; no unpublished vendor hash is implied. Cancelled or failed attempts remove their executable and partial files.

AMD chipset EXEs must also identify themselves as AMD Chipset Software with an embedded file version matching the official offer. NVIDIA self-extractors use the versioned exact GPU/OS download route and trusted NVIDIA publisher check; an extractor's own version is not substituted for a driver version.

Vendor installers run interactively without automatic licence acceptance, silent switches, forced restart or driver-rank overrides. DriverLoom blocks overlapping installs and its own replacement until the vendor handoff is finished, then refreshes versions. It never equates a process exit with successful driver installation. Radeon, notebook NVIDIA, OEM archive/INF and firmware installation paths remain app/website actions for now.

Sources can change or block automation. Failed automatic checks remain visible as Check unavailable, with the reason in device details. Successful source reads with incomparable versions also show Check unavailable. These states never count as current or as available updates.

Devices without a supported automatic check appear when Settings > Show items without automatic checks is enabled. Their status names the managing app or support page, with an official web link when known. CORSAIR iCUE and SSD Toolbox are identified separately, as are ASUS utility/audio components and Microsoft Gaming Services. A VPN adapter does not establish which consumer VPN app owns it, so its download link remains unset. No serial number is sent to a manufacturer to resolve a manual item.

The MediaTek RZ616 Bluetooth path includes the OEM ID `USB\VID_0489&PID_E0E2`. This was verified in ASUS's `mtkbtfilter.inf` for the exact ROG STRIX X670E-A GAMING WIFI package, version 1.1037.0.399. For this OEM ID, the exact-board feed must also identify RZ616 in the title or download filename; an unrelated higher-version Bluetooth package is rejected.

Cross-PC fixtures cover Intel wireless, a discrete Radeon on an Intel CPU, MSI AM4 chipset matching, exact ASUS/OS rejection, Windows inbox components and third-party OEM packages. Live product-metadata probes also covered a legacy GTX 980 and RX 6800 XT, independent of the development PC. Intel's public page returned HTTP 403 on the development network, so that source's live availability is not claimed; the failure path and supported-product parser are tested.

Sources: [Microsoft driver provider/INF fields](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/whqlprov/win32-pnpsigneddriver), [Intel Wi-Fi downloads](https://www.intel.com/content/www/us/en/download/19351/intel-wireless-wi-fi-drivers-for-windows-10-and-windows-11.html), [AMD product downloads](https://www.amd.com/en/support/downloads/drivers.html), [NVIDIA driver search](https://www.nvidia.com/en-us/drivers/), [Samsung firmware](https://semiconductor.samsung.com/consumer-storage/support/tools/).
