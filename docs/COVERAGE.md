# Coverage and source rules

Hardware Update Launcher targets Windows 10/11 x64 across different PCs. It does not claim that every manufacturer's device has a public, automatically comparable update feed.

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

Direct version comparison, package information, manual vendor installation and automatic installation are separate capabilities. A successful manufacturer check does not authorise automatically executing its package. The combined button currently installs eligible Windows Update offers only, following an explicit confirmation, administrator approval and offer revalidation. Manufacturer packages requiring manual installation have Review update links.

Sources can change or block automation. Failed source reads, missing exact matches, conflicting versions and vendor-only utilities remain in Settings > Unsupported items. They are not silently omitted from coverage or counted as current. No serial number is sent to a manufacturer to resolve an unsupported item.

Cross-PC fixtures cover Intel wireless, a discrete Radeon on an Intel CPU, MSI AM4 chipset matching, exact ASUS/OS rejection, Windows inbox components and third-party OEM packages. Live product-metadata probes also covered a legacy GTX 980 and RX 6800 XT, independent of the development PC. Intel's public page returned HTTP 403 on the development network, so that source's live availability is not claimed; the failure path and supported-product parser are tested.

Sources: [Microsoft driver provider/INF fields](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/whqlprov/win32-pnpsigneddriver), [Intel Wi-Fi downloads](https://www.intel.com/content/www/us/en/download/19351/intel-wireless-wi-fi-drivers-for-windows-10-and-windows-11.html), [AMD product downloads](https://www.amd.com/en/support/downloads/drivers.html), [NVIDIA driver search](https://www.nvidia.com/en-us/drivers/), [Samsung firmware](https://semiconductor.samsung.com/consumer-storage/support/tools/).
