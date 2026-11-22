# DriverLoom 0.1.7 - taskbar icon fix

No release or tag is published.

The installed 0.1.6 icon matched the new loop artwork and its shortcut referenced that file, while Windows still displayed the previous chip icon. This points to a stale shell icon association under the reused resource path.

- Use `DriverLoom-loops.ico` for the window, executable resource, installer, shortcut and uninstall registration, avoiding the old chip-icon resource filename.
- Set the window's explicit AppUserModel ID, relaunch icon resource, quoted relaunch command and display name before showing it. Process and shortcut AppIDs stay `SJB.DriverLoom`.
- Notify the shell when its DriverLoom shortcut has been updated. No global icon-cache deletion, Explorer restart or changes to unrelated shortcuts are performed.
- Native-host and installer tests read all four window properties back from Windows and verify the fresh icon filename and relaunch path with spaces.

The loop artwork, main UI, hardware checks and update-installation rules are unchanged. Close the existing app before installing, then open the updated DriverLoom shortcut.

API references: [RelaunchIconResource](https://learn.microsoft.com/en-us/windows/win32/properties/props-system-appusermodel-relaunchiconresource), [RelaunchCommand](https://learn.microsoft.com/en-us/windows/win32/properties/props-system-appusermodel-relaunchcommand).
