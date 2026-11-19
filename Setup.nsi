Target amd64-unicode
RequestExecutionLevel user
ManifestSupportedOS Win10

!include "MUI2.nsh"
!include "WinVer.nsh"

!define APP "Hardware Update Launcher"
!define VERSION "0.1.1"
!define UNINSTALL "Software\Microsoft\Windows\CurrentVersion\Uninstall\HardwareUpdateLauncher"
!define POWERSHELL "$WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
!define LAUNCH_ARGS '-NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "$INSTDIR\Launch.ps1"'
!ifndef OUTPUT_EXE
  !define OUTPUT_EXE "HardwareUpdateLauncher-Setup.exe"
!endif

Name "${APP}"
OutFile "${OUTPUT_EXE}"
InstallDir "$LOCALAPPDATA\Programs\HardwareUpdateLauncher"
ShowInstDetails show
SetCompressor /SOLID lzma
VIProductVersion "0.1.1.0"
VIAddVersionKey "ProductName" "${APP}"
VIAddVersionKey "FileDescription" "${APP} Setup"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "LegalCopyright" "Hardware Update Launcher contributors"

!define MUI_FINISHPAGE_RUN
!define MUI_FINISHPAGE_RUN_TEXT "Open Hardware Update Launcher"
!define MUI_FINISHPAGE_RUN_FUNCTION LaunchApplication
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Function .onInit
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
  Exec '"${POWERSHELL}" ${LAUNCH_ARGS}'
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
  File "Install.ps1"
  File "LICENSE"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  CreateShortcut "$SMPROGRAMS\${APP}.lnk" "${POWERSHELL}" '${LAUNCH_ARGS}'

  WriteRegStr HKCU "${UNINSTALL}" "DisplayName" "${APP}"
  WriteRegStr HKCU "${UNINSTALL}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINSTALL}" "Publisher" "Hardware Update Launcher contributors"
  WriteRegStr HKCU "${UNINSTALL}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALL}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegDWORD HKCU "${UNINSTALL}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTALL}" "NoRepair" 1
SectionEnd

Section "Uninstall"
  SetShellVarContext current
  SetRegView 64
  Delete "$SMPROGRAMS\${APP}.lnk"
  DeleteRegKey HKCU "${UNINSTALL}"
  Delete "$INSTDIR\Launch.ps1"
  Delete "$INSTDIR\App.ps1"
  Delete "$INSTDIR\Engine.ps1"
  Delete "$INSTDIR\Install.ps1"
  Delete "$INSTDIR\LICENSE"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
SectionEnd
