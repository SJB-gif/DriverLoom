# Stock NSIS 3.11 ships x86 stubs. The app still requires native Windows x64.
Target x86-unicode
RequestExecutionLevel user
ManifestSupportedOS Win10

!include "MUI2.nsh"
!include "WinVer.nsh"
!include "x64.nsh"

!define APP "DriverLoom"
!define VERSION "0.1.5"
!define UNINSTALL "Software\Microsoft\Windows\CurrentVersion\Uninstall\HardwareUpdateLauncher"
!define POWERSHELL "$WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
!define LAUNCH_ARGS '-NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "$INSTDIR\Launch.ps1"'
!ifndef OUTPUT_EXE
  !define OUTPUT_EXE "DriverLoom-Setup.exe"
!endif

Name "${APP}"
OutFile "${OUTPUT_EXE}"
InstallDir "$LOCALAPPDATA\Programs\HardwareUpdateLauncher"
ShowInstDetails show
SetCompressor /SOLID lzma
VIProductVersion "0.1.5.0"
VIAddVersionKey "ProductName" "${APP}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "FileDescription" "${APP} Setup"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "LegalCopyright" "DriverLoom contributors"

!define MUI_ICON "assets\DriverLoom.ico"
!define MUI_UNICON "assets\DriverLoom.ico"

!define MUI_FINISHPAGE_RUN
!define MUI_FINISHPAGE_RUN_TEXT "Open DriverLoom"
!define MUI_FINISHPAGE_RUN_FUNCTION LaunchApplication
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Function .onInit
  ${IfNot} ${IsNativeAMD64}
    MessageBox MB_ICONSTOP|MB_OK "${APP} requires an x64 Windows PC."
    Abort
  ${EndIf}
  ${IfNot} ${AtLeastWin10}
    MessageBox MB_ICONSTOP|MB_OK "${APP} requires 64-bit Windows 10 or Windows 11."
    Abort
  ${EndIf}
  SetShellVarContext current
  SetRegView 64
  System::Call 'kernel32::OpenMutexW(i 0x100000, i 0, w "Local\HardwareUpdateLauncher") p.r0'
  ${If} $0 P<> 0
    System::Call 'kernel32::CloseHandle(p r0)'
    MessageBox MB_ICONEXCLAMATION|MB_OK "Close ${APP} before running setup again."
    Abort
  ${EndIf}
FunctionEnd

Function LaunchApplication
  ClearErrors
  # This installer is 32-bit: Sysnative reaches 64-bit PowerShell without WOW64 redirection.
  Exec '"$WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe" ${LAUNCH_ARGS}'
  ${If} ${Errors}
    MessageBox MB_ICONSTOP|MB_OK "Setup could not open Windows PowerShell. Try the Start menu shortcut."
  ${EndIf}
FunctionEnd

Section "Install"
  SetOutPath "$INSTDIR"
  SetOverwrite on
  File "Launch.ps1"
  File "App.ps1"
  File "Engine.ps1"
  File "Manufacturers.ps1"
  File "Coverage.ps1"
  File "Theme.ps1"
  File "Theme.cs"
  File "Install.ps1"
  File "LICENSE"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  SetOutPath "$INSTDIR\assets"
  File "assets\DriverLoom.ico"
  File "assets\DriverLoom.png"
  SetOutPath "$INSTDIR"

  # Keep the existing installation/data identity so this also upgrades pre-branding builds.
  Delete "$SMPROGRAMS\Hardware Update Launcher.lnk"
  CreateShortcut "$SMPROGRAMS\${APP}.lnk" "${POWERSHELL}" '${LAUNCH_ARGS}' "$INSTDIR\assets\DriverLoom.ico"

  WriteRegStr HKCU "${UNINSTALL}" "DisplayName" "${APP}"
  WriteRegStr HKCU "${UNINSTALL}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINSTALL}" "Publisher" "DriverLoom contributors"
  WriteRegStr HKCU "${UNINSTALL}" "DisplayIcon" "$INSTDIR\assets\DriverLoom.ico"
  WriteRegStr HKCU "${UNINSTALL}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALL}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegDWORD HKCU "${UNINSTALL}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTALL}" "NoRepair" 1
SectionEnd

Function un.onInit
  System::Call 'kernel32::OpenMutexW(i 0x100000, i 0, w "Local\HardwareUpdateLauncher") p.r0'
  ${If} $0 P<> 0
    System::Call 'kernel32::CloseHandle(p r0)'
    MessageBox MB_ICONEXCLAMATION|MB_OK "Close ${APP} before uninstalling."
    Abort
  ${EndIf}
FunctionEnd

Section "Uninstall"
  SetShellVarContext current
  SetRegView 64
  Delete "$SMPROGRAMS\${APP}.lnk"
  DeleteRegKey HKCU "${UNINSTALL}"
  Delete "$INSTDIR\Launch.ps1"
  Delete "$INSTDIR\App.ps1"
  Delete "$INSTDIR\Engine.ps1"
  Delete "$INSTDIR\Manufacturers.ps1"
  Delete "$INSTDIR\Coverage.ps1"
  Delete "$INSTDIR\Theme.ps1"
  Delete "$INSTDIR\Theme.cs"
  Delete "$INSTDIR\assets\DriverLoom.ico"
  Delete "$INSTDIR\assets\DriverLoom.png"
  RMDir "$INSTDIR\assets"
  Delete "$INSTDIR\Install.ps1"
  Delete "$INSTDIR\LICENSE"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
SectionEnd
