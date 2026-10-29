; ***  WSUS Offline Next 2026.10.2 - Generator Adaptive Launcher  ***
; ***  Automatically routes to Modern (.NET 8) or Legacy (Win32)  ***

#pragma compile(CompanyName, "WSUS Offline Next Project")
#pragma compile(FileDescription, "WSUS Offline Update Generator (Adaptive Launcher)")
#pragma compile(FileVersion, 2026.10.2)
#pragma compile(InternalName, "GeneratorLauncher")
#pragma compile(LegalCopyright, "GNU GPLv3")
#pragma compile(OriginalFilename, UpdateGenerator.exe)
#pragma compile(ProductName, "WSUS Offline Next")
#pragma compile(ProductVersion, 2026.10.2)

Func _IsWebView2Installed()
    Local $sVer
    ; 1. System-wide Evergreen runtime (Windows 10 / 11 standard)
    $sVer = RegRead("HKLM64\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}", "pv")
    If $sVer <> "" Then Return True
    $sVer = RegRead("HKLM64\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}", "pv")
    If $sVer <> "" Then Return True
    $sVer = RegRead("HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}", "pv")
    If $sVer <> "" Then Return True
    $sVer = RegRead("HKLM\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}", "pv")
    If $sVer <> "" Then Return True
    ; 2. Per-user / Classic installer
    $sVer = RegRead("HKLM64\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-F55F-4E40-8A2F-69DF4B838507}", "pv")
    If $sVer <> "" Then Return True
    $sVer = RegRead("HKLM\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-F55F-4E40-8A2F-69DF4B838507}", "pv")
    If $sVer <> "" Then Return True
    $sVer = RegRead("HKCU\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}", "pv")
    If $sVer <> "" Then Return True
    $sVer = RegRead("HKCU\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-F55F-4E40-8A2F-69DF4B838507}", "pv")
    If $sVer <> "" Then Return True
    ; 3. File system location checks
    If FileExists(@ProgramFilesDir & "\Microsoft\EdgeWebView\Application") Then Return True
    If FileExists("C:\Program Files (x86)\Microsoft\EdgeWebView\Application") Then Return True
    Return False
EndFunc

Func _CanRunModern()
    ; 1. Architecture: modern application is compiled for x64
    If @OSArch <> "X64" And @OSArch <> "ARM64" Then Return False

    ; 2. OS version: .NET 8 requires Windows 10 Version 1607 (Build 14393) minimum
    If Number(@OSBuild) < 14393 Then Return False

    ; 3. Modern binary must exist
    Local $sModernExe = @ScriptDir & "\UpdateGeneratorModern.exe"
    If Not FileExists($sModernExe) Then Return False

    ; 4. WebView2 runtime must be available
    If Not _IsWebView2Installed() Then Return False

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
Local $sIniFile = @ScriptDir & "\UpdateGenerator.ini"
If FileExists($sIniFile) Then
    Local $sVal = IniRead($sIniFile, "Control", "ForceLegacyGUI", "0")
    If $sVal = "1" Then $bForceLegacy = True
EndIf

Local $sTargetExe = ""
If ($bForceModern Or (_CanRunModern() And Not $bForceLegacy)) Then
    $sTargetExe = @ScriptDir & "\UpdateGeneratorModern.exe"
    If Not FileExists($sTargetExe) Then
        $sTargetExe = @ScriptDir & "\UpdateGeneratorLegacy.exe"
    EndIf
Else
    $sTargetExe = @ScriptDir & "\UpdateGeneratorLegacy.exe"
    If Not FileExists($sTargetExe) Then
        $sTargetExe = @ScriptDir & "\UpdateGeneratorModern.exe"
    EndIf
EndIf

If Not FileExists($sTargetExe) Then
    MsgBox(16, "WSUS Offline Next", "Error: No suitable generator executable found." & @CRLF & "Target: " & $sTargetExe)
    Exit(1)
EndIf

Local $sRunCmd = '"' & $sTargetExe & '"'
If $sArgs <> "" Then $sRunCmd &= " " & $sArgs

Local $iExitCode = RunWait($sRunCmd, @ScriptDir)
Exit($iExitCode)
