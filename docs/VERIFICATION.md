# Windows verification - 19 November 2026

## Scope and provenance

The user requested extraction, diagnosis of the Windows launch failure, verification of the single-file installer, and source preparation for GitHub. Repository confirmation is required before any push or release. Future vendor-driver work in `CODEX_HANDOFF.md` is background, not authorization to implement it.

The ZIP was extracted outside the unrelated TravelMate checkout. Its original source is preserved in local `main` commit `f6bdd3c`; work continues on `codex/windows-launch-installer`. There is no remote. `CODEX_HANDOFF.md` describes the earlier 0.1.1 state; this report describes the local 0.1.2 repair.

## Diagnosis

- An old Windows PowerShell process referenced the superseded portable Desktop `App.ps1`. It had no visible main window and held the application's single-instance mutex. The Desktop source folder was empty, and no startup-error log was available. The verified stuck process was closed before testing the current entry point.
- The unmodified 0.1.1 handoff source constructed its interface on Windows PowerShell 5.1 with both empty state and a private copy of the existing 60-row inventory. A normal source launch subsequently exposed a responding app main window. These observations establish a stale-process blocker but do not prove the cause of the original portable failure.
- Building the supplied `Setup.nsi` with stock Windows NSIS 3.11 failed at line 1: `Error: reading stub ...\Stubs\zlib-amd64-unicode` / `Unable to set target architecture (adequate stub not found?)`. The bundled compiler contains only x86 stubs. The original Actions job pinned that same compiler version and would encounter this failure.
- Setup now uses the bundled `x86-unicode` stub with a native AMD64 OS guard. Its finish command uses `Sysnative` to bypass WOW64 redirection; its Start menu shortcut targets native `System32` PowerShell. See the [NSIS x64 helper definitions](https://github.com/nsis-dev/nsis/blob/v311/Include/x64.nsh).

## Tests executed locally

Host: Windows x64, OS build `10.0.26300`, Windows PowerShell 5.1. The installer checks ran with a non-administrator process token. No driver installation, reboot, USB write or firmware operation was requested.

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File Test-Engine.ps1
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File Build.ps1 -MakeNSIS .local\tools\nsis-3.11\makensis.exe
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File Test-Installer.ps1
```

Results:

- Existing engine checks pass, including syntax parsing of every root PowerShell script.
- `Build.ps1` passes engine and Windows startup tests and compiles with stock NSIS 3.11, warnings treated as errors.
- The real form is shown and closed for empty state and cached state, BIOS remains off unless opted in, and saved offers cannot enable Update All. Test mode performs no hardware or network scan.
- A deliberately incomplete private payload fails with exit code 1 and writes an isolated startup log containing the missing-engine error, host bitness and apartment.
- The installer declares `asInvoker`; the local test process was not an administrator. The setup PE is x86 by design while the installed app is hosted by 64-bit Windows PowerShell.
- Silent installation into a path with spaces succeeds. All five payload files match source SHA-256 hashes. The actual HKCU uninstall entry reports 0.1.2.
- The finish-page command is exercised from a real 32-bit PowerShell host and shows the form in a 64-bit STA process. This verifies the runtime command, not the interactive finish-page click.
- The installed, unmodified Start menu shortcut opens a responding app window on both launch attempts. The test terminates only its own launched process between attempts; graceful form closure is covered by the startup tests.
- Uninstall removes the payload, Start menu shortcut and HKCU registration and preserves saved test settings. Test-created files are removed. The user's existing hardware state is kept outside the test directories and Git.

A separate live read-only `Invoke-HardwareCheck` run completed in 90.3 seconds: 61 inventory entries, 60 vendor checks, Windows Update succeeded, zero eligible driver offers and zero warnings. Only counts and elapsed time were recorded for this diagnostic; it did not install anything. The full background-scan result presentation has not been visually inspected.

The NSIS portable ZIP used locally was obtained from the MacPorts distribution mirror after SourceForge returned HTML. Its SHA-256 is `c7d27f780ddb6cffb4730138cd1591e841f4b7edb155856901cdf5f214394fa1`. The CI workflow obtains stock NSIS 3.11 through Chocolatey and uses the same `Build.ps1` and `Test-Installer.ps1`; its package command follows [Chocolatey's documented upgrade/downgrade behavior](https://docs.chocolatey.org/docs/commands-upgrade/).

## Installer deliverable

- File: `dist/HardwareUpdateLauncher-Setup.exe`
- Version: 0.1.2; unsigned.
- Size: 97,282 bytes. SHA-256 for the verified local binary: `99fd95ae560a38e07a91566e596d592ab4a8c8609cebe0ecedc339b028ddf5af`. The adjacent `.sha256` file records the same hash. Rebuilding can change the binary hash because the compiler writes PE timestamps.
- The separate 0.1.1 EXE was absent from the supplied ZIP and local Desktop/Downloads search. Its handoff checksum could not be independently checked; the tests above apply to the rebuilt 0.1.2 EXE.

## Remaining checks before release

- Confirm GitHub owner/repository, existing versus new repository, visibility and publication scope. The connected GitHub installation search returned no repository named HardwareUpdateLauncher; this does not prove a repository is absent or authorize creation.
- Run and observe the workflow after an approved push. It builds and uploads artifacts only; it cannot publish a GitHub Release with its `contents: read` token. The workflow uses the current documented [checkout](https://github.com/actions/checkout) and [upload-artifact](https://github.com/actions/upload-artifact) actions.
- Click through the interactive installer welcome/finish pages and launch checkbox on independent clean Windows 10 and Windows 11 x64 environments. Local automated smoke checks do not establish coverage of those environments or the full visual flow.
- The computer-use inventory did not expose the diagnostic app windows, despite their process main-window and responsiveness checks succeeding; no screenshot or manual visual QA is claimed.
- Exercise actual driver installation and restart handling on a controlled test system. Review BIOS opt-in/USB copy with a disposable USB without flashing firmware. These checks are outside this repair.

## Behavior intentionally unchanged

Windows Update eligibility and administrator approval for installation, firmware exclusions, manufacturer adapters, version ordering, source matching, optional public GitHub catalog reads, local persistence and BIOS/USB behavior are unchanged. No vendor-driver installation, self-update, remote script execution, repository push or release publication was added.
## Exact files changed from the handoff baseline

- `.github/workflows/build.yml`
- `.gitattributes`
- `.gitignore`
- `App.ps1`
- `Build.ps1`
- `Engine.ps1`
- `Launch.ps1`
- `README.md`
- `Setup.nsi`
- `Test-App.ps1`
- `Test-Engine.ps1`
- `Test-Installer.ps1`
- `docs/RELEASE_NOTES_0.1.2.md`
- `docs/VERIFICATION.md`

`Install.ps1`, `catalog.json`, `LICENSE` and the original `CODEX_HANDOFF.md` are unchanged.
