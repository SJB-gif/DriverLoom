# DriverLoom 0.1.10

- Added Manual, On opening, Daily and Weekly check frequencies. On opening is the default.
- Added optional tray operation and Start with Windows, both off by default.
- Closing to the tray preserves scheduled checks. Its menu can reopen the window, check or exit. Opening DriverLoom again restores the existing instance.
- Startup registration is per user and removed during uninstall. No background service or wake task is created.
- Updated the README with background behavior, privacy details and the project's support policy.

Checks never install updates automatically. Driver installation still requires review and confirmation. Daily and weekly checks run only while the app is running.

This test build is unsigned. No new public release or SignPath application is included in this change.
