# Stock NSIS 3.11 ships x86 stubs. The app still requires native Windows x64.
Target x86-unicode
RequestExecutionLevel user
ManifestSupportedOS Win10

!include "MUI2.nsh"
!include "WinVer.nsh"
!include "x64.nsh"
!include "nsDialogs.nsh"
!include "FileFunc.nsh"

!define APP "DriverLoom"
!define VERSION "0.1.10"
!define UNINSTALL "Software\Microsoft\Windows\CurrentVersion\Uninstall\HardwareUpdateLauncher"
!ifndef OUTPUT_EXE
  !define OUTPUT_EXE "DriverLoom-Setup.exe"
!endif

Name "${APP}"
OutFile "${OUTPUT_EXE}"
InstallDir "$LOCALAPPDATA\Programs\HardwareUpdateLauncher"
ShowInstDetails show
SetCompressor /SOLID lzma
VIProductVersion "0.1.10.0"
VIAddVersionKey "ProductName" "${APP}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "FileDescription" "${APP} Setup"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "LegalCopyright" "DriverLoom contributors"

!define MUI_ICON "assets\DriverLoom-loops.ico"
!define MUI_UNICON "assets\DriverLoom-loops.ico"

!define MUI_FINISHPAGE_RUN
!define MUI_FINISHPAGE_RUN_TEXT "Open DriverLoom"
!define MUI_FINISHPAGE_RUN_FUNCTION LaunchApplication
!insertmacro MUI_PAGE_WELCOME
Page custom ShortcutsPage ShortcutsPageLeave
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Var ShortcutsDialog
Var StartMenuCheck
Var DesktopCheck
Var StartMenuSelected
Var DesktopSelected

Function ShortcutsPage
  !insertmacro MUI_HEADER_TEXT "Shortcuts" "Choose where to add DriverLoom shortcuts."
  nsDialogs::Create 1018
  Pop $ShortcutsDialog
  ${If} $ShortcutsDialog == error
    Abort
  ${EndIf}
  ${NSD_CreateLabel} 0 0 100% 28u "Choose the shortcuts you would like to create:"
  Pop $0
  ${NSD_CreateCheckbox} 0 36u 100% 14u "Create a Start menu shortcut"
  Pop $StartMenuCheck
  ${NSD_SetState} $StartMenuCheck $StartMenuSelected
  ${NSD_CreateCheckbox} 0 62u 100% 14u "Create a desktop shortcut"
  Pop $DesktopCheck
  ${NSD_SetState} $DesktopCheck $DesktopSelected
  ${NSD_CreateLabel} 0 100u 100% 28u "Shortcuts are created for your Windows account only."
  Pop $0
  nsDialogs::Show
FunctionEnd

Function ShortcutsPageLeave
  ${NSD_GetState} $StartMenuCheck $StartMenuSelected
  ${NSD_GetState} $DesktopCheck $DesktopSelected
FunctionEnd

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
  StrCpy $StartMenuSelected 1
  StrCpy $DesktopSelected 0
  ClearErrors
  ReadRegDWORD $0 HKCU "${UNINSTALL}" "StartMenuShortcut"
  ${IfNot} ${Errors}
    StrCpy $StartMenuSelected $0
  ${EndIf}
  ClearErrors
  ReadRegDWORD $0 HKCU "${UNINSTALL}" "DesktopShortcut"
  ${IfNot} ${Errors}
    StrCpy $DesktopSelected $0
  ${Else}
    IfFileExists "$DESKTOP\${APP}.lnk" 0 +2
    StrCpy $DesktopSelected 1
  ${EndIf}
  ${GetParameters} $R9
  ClearErrors
  ${GetOptions} $R9 "/STARTMENU=" $R8
  ${IfNot} ${Errors}
    ${If} $R8 != 0
    ${AndIf} $R8 != 1
      SetErrorLevel 2
      Quit
    ${EndIf}
    StrCpy $StartMenuSelected $R8
  ${EndIf}
  ClearErrors
  ${GetOptions} $R9 "/DESKTOP=" $R8
  ${IfNot} ${Errors}
    ${If} $R8 != 0
    ${AndIf} $R8 != 1
      SetErrorLevel 2
      Quit
    ${EndIf}
    StrCpy $DesktopSelected $R8
  ${EndIf}
  ClearErrors
  System::Call 'kernel32::OpenMutexW(i 0x100000, i 0, w "Local\HardwareUpdateLauncher") p.r0'
  ${If} $0 P<> 0
    System::Call 'kernel32::CloseHandle(p r0)'
    MessageBox MB_ICONEXCLAMATION|MB_OK "Exit ${APP} before running setup again. If it is in the tray, right-click its icon and choose Exit."
    Abort
  ${EndIf}
FunctionEnd

Function LaunchApplication
  ClearErrors
  Exec '"$INSTDIR\DriverLoom.exe"'
  ${If} ${Errors}
    MessageBox MB_ICONSTOP|MB_OK "Setup could not open DriverLoom. Try the Start menu shortcut."
  ${EndIf}
FunctionEnd

Section "Install"
  SetOutPath "$INSTDIR"
  SetOverwrite on
  File "Launch.ps1"
  File "App.ps1"
  File "Engine.ps1"
  File "Lifecycle.ps1"
  File "Manufacturers.ps1"
  File "Coverage.ps1"
  File "Theme.ps1"
  File "Theme.cs"
  File "Install.ps1"
  File "LICENSE"
  File "assets\ATTRIBUTION.md"
  File "dist\host\DriverLoom.exe"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  SetOutPath "$INSTDIR\assets"
  File "assets\DriverLoom-loops.ico"
  File "assets\DriverLoom.png"
  File "assets\DriverLoom-brand.png"
  File "assets\GitHub-light.png"
  File "assets\GitHub-dark.png"
  SetOutPath "$INSTDIR"

  # Keep the existing installation/data identity so this also upgrades pre-branding builds.
  Delete "$SMPROGRAMS\Hardware Update Launcher.lnk"
  ${If} $StartMenuSelected == 1
    CreateShortcut "$SMPROGRAMS\${APP}.lnk" "$INSTDIR\DriverLoom.exe" "" "$INSTDIR\assets\DriverLoom-loops.ico"
    ExecWait '"$INSTDIR\DriverLoom.exe" --shortcut-id "$SMPROGRAMS\${APP}.lnk"' $0
  ${Else}
    Delete "$SMPROGRAMS\${APP}.lnk"
  ${EndIf}
  ${If} $DesktopSelected == 1
    CreateShortcut "$DESKTOP\${APP}.lnk" "$INSTDIR\DriverLoom.exe" "" "$INSTDIR\assets\DriverLoom-loops.ico"
    ExecWait '"$INSTDIR\DriverLoom.exe" --shortcut-id "$DESKTOP\${APP}.lnk"' $0
  ${Else}
    Delete "$DESKTOP\${APP}.lnk"
  ${EndIf}

  WriteRegStr HKCU "${UNINSTALL}" "DisplayName" "${APP}"
  WriteRegStr HKCU "${UNINSTALL}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINSTALL}" "Publisher" "DriverLoom contributors"
  WriteRegStr HKCU "${UNINSTALL}" "DisplayIcon" "$INSTDIR\assets\DriverLoom-loops.ico"
  WriteRegStr HKCU "${UNINSTALL}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALL}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegDWORD HKCU "${UNINSTALL}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTALL}" "NoRepair" 1
  WriteRegDWORD HKCU "${UNINSTALL}" "StartMenuShortcut" $StartMenuSelected
  WriteRegDWORD HKCU "${UNINSTALL}" "DesktopShortcut" $DesktopSelected
SectionEnd

Function un.onInit
  System::Call 'kernel32::OpenMutexW(i 0x100000, i 0, w "Local\HardwareUpdateLauncher") p.r0'
  ${If} $0 P<> 0
    System::Call 'kernel32::CloseHandle(p r0)'
    MessageBox MB_ICONEXCLAMATION|MB_OK "Exit ${APP} before uninstalling. If it is in the tray, right-click its icon and choose Exit."
    Abort
  ${EndIf}
FunctionEnd

Section "Uninstall"
  SetShellVarContext current
  SetRegView 64
  Delete "$SMPROGRAMS\${APP}.lnk"
  Delete "$DESKTOP\${APP}.lnk"
  DeleteRegKey HKCU "${UNINSTALL}"
  DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "DriverLoom"
  Delete "$INSTDIR\Launch.ps1"
  Delete "$INSTDIR\App.ps1"
  Delete "$INSTDIR\Engine.ps1"
  Delete "$INSTDIR\Lifecycle.ps1"
  Delete "$INSTDIR\Manufacturers.ps1"
  Delete "$INSTDIR\Coverage.ps1"
  Delete "$INSTDIR\Theme.ps1"
  Delete "$INSTDIR\Theme.cs"
  Delete "$INSTDIR\assets\DriverLoom-loops.ico"
  Delete "$INSTDIR\assets\DriverLoom.ico"
  Delete "$INSTDIR\assets\DriverLoom.png"
  Delete "$INSTDIR\assets\DriverLoom-brand.png"
  Delete "$INSTDIR\assets\GitHub-light.png"
  Delete "$INSTDIR\assets\GitHub-dark.png"
  Delete "$INSTDIR\ATTRIBUTION.md"
  Delete "$INSTDIR\DriverLoom.exe"
  RMDir "$INSTDIR\assets"
  Delete "$INSTDIR\Install.ps1"
  Delete "$INSTDIR\LICENSE"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
SectionEnd
