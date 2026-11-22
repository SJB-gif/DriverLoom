# DriverLoom 0.1.15

- Added verified installed-app actions for AMD Install Manager, AMD Software graphics fallback, NVIDIA App, iCUE, CORSAIR SSD Toolbox and Samsung Magician.
- Discovery uses local registry registrations and standard program folders. Registered command-line strings are not executed; executable identity and vendor signature are checked again on Open. Missing or unverifiable apps keep the official website workflow.
- Devices sharing the same detected launcher use one compact header/Open button, with individual statuses and installed/available versions underneath. Different tools from the same manufacturer stay separate.
- Double-click a group for individual device details, official sites and source editing. Right-click retains access to official sites after an app replaces the main action.
- Groups stay together when sorted. An available device update puts its group in the updates-first section; unknown firmware is never inferred to be current.

Direct manufacturer driver installation, release publishing and signing remain on hold. Existing eligible Windows Update installation is unchanged.
