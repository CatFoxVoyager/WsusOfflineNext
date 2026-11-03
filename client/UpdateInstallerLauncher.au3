; ***  WSUS Offline Next 5.1.0+2026.11 - Installer Adaptive Launcher  ***
; ***  Automatically routes to Modern (.NET 8) or Legacy (Win32)  ***

#RequireAdmin
#pragma compile(CompanyName, "WSUS Offline Next Project")
#pragma compile(FileDescription, "WSUS Offline Update Installer (Adaptive Launcher)")
#pragma compile(FileVersion, 5.1.0)
#pragma compile(InternalName, "InstallerLauncher")
#pragma compile(LegalCopyright, "GNU GPLv3")
#pragma compile(OriginalFilename, UpdateInstaller.exe)
#pragma compile(ProductName, "WSUS Offline Next")
#pragma compile(ProductVersion, 5.1.0)

; Minimum WebView2 runtime version accepted by the modern interface: the
; runtime version that matches the WebView2 SDK the application is built
; against (the package documentation defines the default browser version as
; the runtime version corresponding to the SDK version). An older runtime
; passes a presence-only check but fails downstream with E_NOINTERFACE-class
; errors, so it must route Legacy instead.
Global Const $MIN_WEBVIEW2_VERSION = "156.0.4314.35"

Func _GetWebView2Version()
    Local $sVer
    ; 1. System-wide Evergreen runtime (Windows 10 / 11 standard)
    $sVer = RegRead("HKLM64\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}", "pv")
    If $sVer <> "" Then Return $sVer
    $sVer = RegRead("HKLM64\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}", "pv")
    If $sVer <> "" Then Return $sVer
    $sVer = RegRead("HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}", "pv")
    If $sVer <> "" Then Return $sVer
    $sVer = RegRead("HKLM\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}", "pv")
    If $sVer <> "" Then Return $sVer
    ; 2. Per-user / Classic installer
    $sVer = RegRead("HKLM64\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-F55F-4E40-8A2F-69DF4B838507}", "pv")
    If $sVer <> "" Then Return $sVer
    $sVer = RegRead("HKLM\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-F55F-4E40-8A2F-69DF4B838507}", "pv")
    If $sVer <> "" Then Return $sVer
    $sVer = RegRead("HKCU\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}", "pv")
    If $sVer <> "" Then Return $sVer
    $sVer = RegRead("HKCU\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-F55F-4E40-8A2F-69DF4B838507}", "pv")
    If $sVer <> "" Then Return $sVer
    Return ""
EndFunc

Func _IsVersionAtLeast($sVersion, $sMinimum)
    ; Numeric part-by-part comparison with >= semantics. A missing part
    ; counts as 0 and a non-numeric part counts as 0 (fail-safe: an
    ; unparsable runtime never routes Modern).
    Local $aVersion = StringSplit($sVersion, ".")
    Local $aMinimum = StringSplit($sMinimum, ".")
    Local $iParts = $aVersion[0]
    If $aMinimum[0] > $iParts Then $iParts = $aMinimum[0]
    Local $iIndex, $iVerPart, $iMinPart
    For $iIndex = 1 To $iParts
        $iVerPart = 0
        $iMinPart = 0
        If $iIndex <= $aVersion[0] Then
            If StringIsDigit($aVersion[$iIndex]) Then $iVerPart = Number($aVersion[$iIndex])
        EndIf
        If $iIndex <= $aMinimum[0] Then
            If StringIsDigit($aMinimum[$iIndex]) Then $iMinPart = Number($aMinimum[$iIndex])
        EndIf
        If $iVerPart < $iMinPart Then Return False
        If $iVerPart > $iMinPart Then Return True
    Next
    Return True
EndFunc

Func _CanRunModern()
    ; 1. Architecture: modern application is compiled for x64
    If @OSArch <> "X64" And @OSArch <> "ARM64" Then Return False

    ; 2. OS version: .NET 8 requires Windows 10 Version 1607 (Build 14393) minimum
    If Number(@OSBuild) < 14393 Then Return False

    ; 3. Modern binary must exist
    Local $sModernExe = @ScriptDir & "\UpdateInstallerModern.exe"
    If Not FileExists($sModernExe) Then Return False

    ; 4. WebView2 runtime must be available and at least the SDK minimum
    Local $sWv2Ver = _GetWebView2Version()
    If Not _IsVersionAtLeast($sWv2Ver, $MIN_WEBVIEW2_VERSION) Then Return False

    Return True
EndFunc

; Parse overrides
Local $bForceLegacy = False
Local $bForceModern = False
Local $sArgs = $CmdLineRaw

If StringInStr($CmdLineRaw, "/legacy") > 0 Or StringInStr($CmdLineRaw, "/classic") > 0 Then
    $bForceLegacy = True
EndIf

If StringInStr($CmdLineRaw, "/modern") > 0 Or StringInStr($CmdLineRaw, "/next") > 0 Then
    $bForceModern = True
EndIf

; Check INI file: [Control] ForceLegacyGUI=1
Local $sIniFile = @ScriptDir & "\UpdateInstaller.ini"
If FileExists($sIniFile) Then
    Local $sVal = IniRead($sIniFile, "Control", "ForceLegacyGUI", "0")
    If $sVal = "1" Then $bForceLegacy = True
EndIf

Local $sTargetExe = ""
If ($bForceModern Or (_CanRunModern() And Not $bForceLegacy)) Then
    $sTargetExe = @ScriptDir & "\UpdateInstallerModern.exe"
    If Not FileExists($sTargetExe) Then
        $sTargetExe = @ScriptDir & "\UpdateInstallerLegacy.exe"
    EndIf
Else
    $sTargetExe = @ScriptDir & "\UpdateInstallerLegacy.exe"
    If Not FileExists($sTargetExe) Then
        $sTargetExe = @ScriptDir & "\UpdateInstallerModern.exe"
    EndIf
EndIf

If Not FileExists($sTargetExe) Then
    MsgBox(16, "WSUS Offline Next", "Error: No suitable installer executable found." & @CRLF & "Target: " & $sTargetExe)
    Exit(1)
EndIf

Local $sRunCmd = '"' & $sTargetExe & '"'
If $sArgs <> "" Then $sRunCmd &= " " & $sArgs

Local $iExitCode = RunWait($sRunCmd, @ScriptDir)
Exit($iExitCode)
