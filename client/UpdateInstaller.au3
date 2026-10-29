; ***  WSUS Offline Next 2026.10.2 - Installer  ***
; ***       Author: T. Wittrock, Kiel        ***
; ***         - Next Edition -          ***
; ***   Dialog scaling added by Th. Baisch   ***

#include <GUIConstants.au3>
#include <MsgBoxConstants.au3>
#include <WinAPIError.au3>

#RequireAdmin
#pragma compile(CompanyName, "WSUS Offline Next Project")
#pragma compile(FileDescription, "WSUS Offline Update Installer")
#pragma compile(FileVersion, 2026.10.2)
#pragma compile(InternalName, "Installer")
#pragma compile(LegalCopyright, "GNU GPLv3")
#pragma compile(OriginalFilename, UpdateInstaller.exe)
#pragma compile(ProductName, "WSUS Offline Next")
#pragma compile(ProductVersion, 2026.10.2)

Dim Const $caption                      = "WSUS Offline Next - 2026.10.2 (b2026.10) - Installer"

; Registry constants
Dim Const $reg_key_wsh_hklm64           = "HKLM64\Software\Microsoft\Windows Script Host\Settings"
Dim Const $reg_key_wsh_hklm             = "HKEY_LOCAL_MACHINE\Software\Microsoft\Windows Script Host\Settings"
Dim Const $reg_key_wsh_hkcu             = "HKEY_CURRENT_USER\Software\Microsoft\Windows Script Host\Settings"
Dim Const $reg_key_ie                   = "HKEY_LOCAL_MACHINE\Software\Microsoft\Internet Explorer"
Dim Const $reg_key_dotnet35             = "HKEY_LOCAL_MACHINE\Software\Microsoft\NET Framework Setup\NDP\v3.5"
Dim Const $reg_key_dotnet4              = "HKEY_LOCAL_MACHINE\Software\Microsoft\NET Framework Setup\NDP\v4\Full"
Dim Const $reg_key_wmf                  = "HKEY_LOCAL_MACHINE\Software\Microsoft\PowerShell\3\PowerShellEngine"
Dim Const $reg_key_hkcu_desktop         = "HKEY_CURRENT_USER\Control Panel\Desktop"
Dim Const $reg_key_hkcu_winmetrics      = "HKEY_CURRENT_USER\Control Panel\Desktop\WindowMetrics"
Dim Const $reg_key_windowsupdate        = "HKEY_LOCAL_MACHINE\Software\Policies\Microsoft\Windows\WindowsUpdate"

Dim Const $reg_val_default              = ""
Dim Const $reg_val_enabled              = "Enabled"
Dim Const $reg_val_version              = "Version"
Dim Const $reg_val_release              = "Release"
Dim Const $reg_val_pshversion           = "PowerShellVersion"
Dim Const $reg_val_logpixels            = "LogPixels"
Dim Const $reg_val_applieddpi           = "AppliedDPI"
Dim Const $reg_val_wustatusserver       = "WUStatusServer"

; Defaults
Dim Const $msimax                       = 10
Dim Const $default_logpixels            = 96
Dim Const $target_version_dotnet35      = "3.5.30729"

; INI file constants
Dim Const $ini_section_installation     = "Installation"
Dim Const $ini_value_buildupgrade       = "upgradebuilds"
Dim Const $ini_value_rcerts             = "updatercerts"
Dim Const $ini_value_dotnet35           = "instdotnet35"
Dim Const $ini_value_dotnet4            = "instdotnet4"
Dim Const $ini_value_wmf                = "instwmf"
Dim Const $ini_value_dotnet5            = "updatedotnet5"
Dim Const $ini_value_cpp                = "updatecpp"
Dim Const $ini_value_instedge           = "instedge"
Dim Const $ini_value_instwebview2       = "instwebview2"
Dim Const $ini_value_instoffice         = "updateoffice"
; Hidden installation constants
Dim Const $ini_value_skipieinst         = "skipieinst"
Dim Const $ini_value_skipdefs           = "skipdefs"
Dim Const $ini_value_skipdynamic        = "skipdynamic"
Dim Const $ini_value_all                = "all"
Dim Const $ini_value_excludestatics     = "excludestatics"
Dim Const $ini_value_seconly            = "seconly"

Dim Const $ini_section_control          = "Control"
Dim Const $ini_value_verify             = "verify"
Dim Const $ini_value_autoreboot         = "autoreboot"
Dim Const $ini_value_shutdown           = "shutdown"
Dim Const $ini_value_auditonly          = "auditonly"

Dim Const $ini_section_messaging        = "Messaging"
Dim Const $ini_value_showlog            = "showlog"
; Hidden messaging constants
Dim Const $ini_value_showieinfo         = "showieinfo"
Dim Const $ini_value_showdotnet4info    = "showdotnet4info"
Dim Const $ini_value_showdismprogress   = "showdismprogress"

Dim Const $ini_section_misc             = "Miscellaneous"
Dim Const $ini_value_monitoron          = "monitoron"
Dim Const $ini_value_wustatusserver     = "WUStatusServer"

Dim Const $ini_section_msi              = "MSI"

Dim Const $enabled                      = "Enabled"
Dim Const $disabled                     = "Disabled"

; Paths
Dim Const $path_max_length              = 192
Dim Const $path_invalid_chars           = "!%&()^+,;="
Dim Const $path_rel_builddate           = "\builddate.txt"
Dim Const $path_rel_hashes              = "\md\"
Dim Const $path_rel_autologon           = "\bin\Autologon.exe"
Dim Const $path_rel_rcerts              = "\win\glb\*.crt"
Dim Const $path_rel_cpp                 = "\cpp\vcredist*.exe"
Dim Const $path_rel_instdotnet48        = "\dotnet\ndp48-x86-x64-allos-*.exe"
Dim Const $path_rel_instdotnet481       = "\dotnet\ndp481-x86-x64-allos-*.exe"
Dim Const $path_rel_edge                = "\edge\MicrosoftEdgeEnterprise*.msi"
Dim Const $path_rel_msedge_legacy       = "\msedge\MicrosoftEdge_*.exe"
Dim Const $path_rel_webview2            = "\edge\MicrosoftEdgeWebView2*.exe"
; -- BEGIN GENERATED BUILDS TABLE --
; Format: [build, arch, os_family, servicing_branch, status, ekb_source_build, ekb_kb, ekb_prereq_kb, ekb_min_revision, is_enforced]
Global Const $aBuildRegistry[12][10] = [ _
  ["19041", "x86", "win10", "19041", "active",  "",      "",           "",           "",      0], _
  ["19041", "x64", "win10", "19041", "active",  "",      "",           "",           "",      0], _
  ["19042", "x86", "win10", "19041", "eol",     "19041", "kb4562830",  "kb5008212",  "572",   1], _
  ["19042", "x64", "win10", "19041", "eol",     "19041", "kb4562830",  "kb5008212",  "572",   1], _
  ["19044", "x86", "win10", "19041", "eol",     "19041", "kb5003791",  "kb5008212",  "1237",  0], _
  ["19044", "x64", "win10", "19041", "eol",     "19041", "kb5003791",  "kb5008212",  "1237",  0], _
  ["19045", "x86", "win10", "19041", "active",  "19041", "kb5015684",  "kb5021233",  "1865",  0], _
  ["19045", "x64", "win10", "19041", "active",  "19041", "kb5015684",  "kb5021233",  "1865",  0], _
  ["26100", "x64", "win11", "26100", "active",  "",      "",           "",           "",      0], _
  ["26200", "x64", "win11", "26100", "active",  "26100", "kb5054156",  "kb5064081",  "5074",  0], _
  ["26300", "x64", "win11", "26100", "active",  "26100", "kb5054156",  "",           "",      0], _
  ["28000", "x64", "win11", "28000", "ineligible",  "",  "",           "",           "",      0] _
]
; -- END GENERATED BUILDS TABLE --
Dim Const $path_rel_msi_all             = "\wouallmsi.txt"
Dim Const $path_rel_msi_selected        = "\Temp\wouselmsi.txt"

Dim $maindlg, $scriptdir, $mapped, $tabitemfocused, $buildupgrade, $rcerts, $dotnet35, $dotnet4, $wmf, $dotnet5, $cpp, $instedge, $instwebview2, $instoffice, $lbloffice, $verify, $autoreboot, $shutdown, $auditonly, $showlog, $btn_start, $btn_exit, $options, $builddate
Dim $dlgheight, $groupwidth, $txtwidth, $txtheight, $btnwidth, $btnheight, $txtxoffset, $txtyoffset, $txtxpos, $txtypos, $msiall, $msipacks[$msimax], $msicount, $msilistfile, $line, $gergui, $pRedirect, $dllCallResult, $i

Func Office16Detected()
  If EnvGet("O2K16_VER_MAJOR") <> "" Then
    Return True
  EndIf
  Local $p = RegRead("HKLM\Software\Microsoft\Office\16.0\Common\InstallRoot", "Path")
  If $p <> "" Then Return True
  $p = RegRead("HKLM\Software\Wow6432Node\Microsoft\Office\16.0\Common\InstallRoot", "Path")
  If $p <> "" Then Return True
  Return False
EndFunc

Func Office16Description()
  Local $name = EnvGet("O2K16_PRODUCT_NAME")
  Local $arch = EnvGet("O2K16_ARCH")
  If $name <> "" Then
    If $arch <> "" Then
      Return $name & " (" & $arch & ")"
    Else
      Return $name
    EndIf
  EndIf
  If Office16Detected() Then
    Return "Microsoft Office 2016+"
  EndIf
  If $gergui Then
    Return "Kein Office erkannt"
  Else
    Return "No Office detected"
  EndIf
EndFunc

Func ShowGUIInGerman()
  If $CmdLine[0] > 0 Then
    Switch StringLower($CmdLine[1])
      Case "enu"
        Return False
      Case "deu"
        Return True
    EndSwitch
  EndIf
  Return ( (@OSLang = "0007") OR (@OSLang = "0407") OR (@OSLang = "0807") OR (@OSLang = "0C07") OR (@OSLang = "1007") OR (@OSLang = "1407") )
EndFunc

; Returns script directory, also sets global variable $mapped
Func AssignScriptDirectory()
Dim $result, $netdrives, $i

  ; Check if script directory is a network share, map if unmapped
  $result = ""
  $mapped = False
  If DriveGetType(@ScriptDir) = "Network" Then
    If StringInStr(@ScriptDir, "\\") = 0 Then
      $result = @ScriptDir
    Else
      $netdrives = DriveGetDrive("NETWORK")
      If NOT @error Then
        For $i = 1 to $netdrives[0]
          If StringInStr(@ScriptDir, DriveMapGet($netdrives[$i])) > 0 Then
            $result = $netdrives[$i] & StringRight(@ScriptDir, StringLen(@ScriptDir) - StringLen(DriveMapGet($netdrives[$i])))
            ExitLoop
          EndIf
        Next
      EndIf
      If $result = "" Then
        $result = DriveMapAdd("*", @ScriptDir)
        If @error Then
          $result = ""
        Else
          $mapped = True
        EndIf
      EndIf
    EndIf
  Else
    $result = @ScriptDir
  EndIf
  Return $result
EndFunc

Func IsCheckBoxChecked($chkbox)
  Return BitAND(GUICtrlRead($chkbox), $GUI_CHECKED) = $GUI_CHECKED
EndFunc

Func CheckBoxStateToString($chkbox)
  If IsCheckBoxChecked($chkbox) Then
    Return $enabled
  Else
    Return $disabled
  EndIf
EndFunc

Func DefaultIniRead($section, $key, $default)
  Return IniRead($scriptdir & "\" & StringLeft(@ScriptName, StringInStr(@ScriptName, ".", 0, -1)) & "ini", $section, $key, $default)
EndFunc

Func MyIniRead($section, $key, $default)
Dim $inifilepath, $result

  $result = DefaultIniRead($section, $key, $default)
  $inifilepath = @TempDir & "\" & StringLeft(@ScriptName, StringInStr(@ScriptName, ".", 0, -1)) & "ini"
  If FileExists($inifilepath) Then
    $result = IniRead($inifilepath, $section, $key, $result)
  EndIf
  Return $result
EndFunc

Func IniCopy()
Dim $ini_src, $ini_dest, $i

  $ini_src = $scriptdir & "\" & StringLeft(@ScriptName, StringInStr(@ScriptName, ".", 0, -1)) & "ini"
  $ini_dest = @TempDir & "\" & StringLeft(@ScriptName, StringInStr(@ScriptName, ".", 0, -1)) & "ini"
  FileCopy($ini_src, $ini_dest, 1)
  FileSetAttrib($ini_dest, "-R")

  IniWrite($ini_dest, $ini_section_installation, $ini_value_rcerts, CheckBoxStateToString($rcerts))
  IniWrite($ini_dest, $ini_section_installation, $ini_value_dotnet35, CheckBoxStateToString($dotnet35))
  IniWrite($ini_dest, $ini_section_installation, $ini_value_dotnet4, CheckBoxStateToString($dotnet4))
  IniWrite($ini_dest, $ini_section_installation, $ini_value_wmf, CheckBoxStateToString($wmf))
  IniWrite($ini_dest, $ini_section_installation, $ini_value_dotnet5, CheckBoxStateToString($dotnet5))
  IniWrite($ini_dest, $ini_section_installation, $ini_value_cpp, CheckBoxStateToString($cpp))
  IniWrite($ini_dest, $ini_section_installation, $ini_value_instedge, CheckBoxStateToString($instedge))
  IniWrite($ini_dest, $ini_section_installation, $ini_value_instwebview2, CheckBoxStateToString($instwebview2))
  IniWrite($ini_dest, $ini_section_installation, $ini_value_instoffice, CheckBoxStateToString($instoffice))

  IniWrite($ini_dest, $ini_section_control, $ini_value_verify, CheckBoxStateToString($verify))
  IniWrite($ini_dest, $ini_section_control, $ini_value_autoreboot, CheckBoxStateToString($autoreboot))
  IniWrite($ini_dest, $ini_section_control, $ini_value_shutdown, CheckBoxStateToString($shutdown))
  IniWrite($ini_dest, $ini_section_control, $ini_value_auditonly, CheckBoxStateToString($auditonly))
  IniWrite($ini_dest, $ini_section_messaging, $ini_value_showlog, CheckBoxStateToString($showlog))

  For $i = 0 To $msicount - 1
    IniWrite($ini_dest, $ini_section_msi, GUICtrlRead($msipacks[$i], 1), CheckBoxStateToString($msipacks[$i]))
  Next

  Return 0
EndFunc

Func PathValid($path)
  Dim $result, $arr_invalid, $i

  If StringLen($path) > $path_max_length Then
    $result = False
  Else
    $result = True
    $arr_invalid = StringSplit($path_invalid_chars, "")
    For $i = 1 to $arr_invalid[0]
      If StringInStr($path, $arr_invalid[$i]) > 0 Then
        $result = False
        ExitLoop
      EndIf
    Next
  EndIf
  Return $result
EndFunc

Func MediumBuildDate($basepath)
  Dim $result

  $result = FileReadLine($basepath & $path_rel_builddate)
  If @error Then
    $result = ""
  EndIf
  Return $result
EndFunc

Func IsBuildIneligible($build)
  For $i = 0 To UBound($aBuildRegistry) - 1
    If ($aBuildRegistry[$i][0] = $build) Then
      Return ($aBuildRegistry[$i][4] = "ineligible")
    EndIf
  Next
  Return False
EndFunc

Func BuildUpgradeAvailable($basepath, $enforcementmode)
  Local $currBuild = @OSBuild
  Local $currArch = (@OSArch = "X86" ? "x86" : "x64")

  If IsBuildIneligible($currBuild) Then Return 0

  For $i = 0 To UBound($aBuildRegistry) - 1
    Local $bMatch = False
    If ($aBuildRegistry[$i][5] = $currBuild) And ($aBuildRegistry[$i][1] = $currArch) Then
      $bMatch = True
    ElseIf ($aBuildRegistry[$i][3] = "19041") And ($aBuildRegistry[$i][1] = $currArch) And (Number($currBuild) >= 19041) And (Number($currBuild) < Number($aBuildRegistry[$i][0])) Then
      $bMatch = True
    EndIf

    If $bMatch Then
      Local $targetBuild = $aBuildRegistry[$i][0]
      Local $ekbKb = $aBuildRegistry[$i][6]
      Local $osFamily = $aBuildRegistry[$i][2]
      Local $isEnforced = $aBuildRegistry[$i][9]

      If ($enforcementmode > 0) And ($isEnforced <> 1) Then ContinueLoop

      If $ekbKb <> "" Then
        Local $osPrefix = ($osFamily = "win11" ? "windows11.0-" : "windows10.0-")
        Local $subDir = ($currArch = "x64" ? "\w100-x64\glb\" : "\w100\glb\")

        Local $p1 = $basepath & $subDir & $osPrefix & $ekbKb & "-" & $currArch & "*.*"
        Local $p2 = $basepath & $subDir & $currBuild & "\" & $osPrefix & $ekbKb & "-" & $currArch & "*.*"

        If FileExists($p1) Or FileExists($p2) Then
          Return 1
        EndIf
      EndIf
    EndIf
  Next
  Return 0
EndFunc

Func BuildUpgradeEnforced()
  Local $currBuild = @OSBuild
  Local $currArch = (@OSArch = "X86" ? "x86" : "x64")

  For $i = 0 To UBound($aBuildRegistry) - 1
    If ($aBuildRegistry[$i][5] = $currBuild) And ($aBuildRegistry[$i][1] = $currArch) Then
      If ($aBuildRegistry[$i][9] = 1) Then Return 1
    EndIf
  Next
  Return 0
EndFunc

Func WSHAvailable()
  Dim $reg_val

  If (@OSArch <> "X86") Then
    $reg_val = RegRead($reg_key_wsh_hklm64, $reg_val_enabled)
  Else
    $reg_val = RegRead($reg_key_wsh_hklm, $reg_val_enabled)
  EndIf
  If ($reg_val = "0") Then
    Return 0
  EndIf
  $reg_val = RegRead($reg_key_wsh_hkcu, $reg_val_enabled)
  If ($reg_val = "0") Then
    Return 0
  EndIf
  Return 1
EndFunc

Func IEVersion()
Dim $reg_val

  $reg_val = RegRead($reg_key_ie, $reg_val_version)
  If StringInStr($reg_val, "9.10.") > 0 Then
    Return "10"
  EndIf
  If StringInStr($reg_val, "9.11.") > 0 Then
    Return "11"
  EndIf
  Return StringLeft($reg_val, StringInStr($reg_val, ".") - 1)
EndFunc

Func DotNet35Version()
Dim $reg_val

  $reg_val = RegRead($reg_key_dotnet35, $reg_val_version)
  Return StringLeft($reg_val, StringInStr($reg_val, ".", 0, -1) - 1)
EndFunc

Func DotNet4Version()
  Return RegRead($reg_key_dotnet4, $reg_val_version)
EndFunc

Func DotNet4Release()
  Return RegRead($reg_key_dotnet4, $reg_val_release)
EndFunc

Func DotNet4DisplayVersion()
  Return DotNet4ReleaseToDisplayVersion(DotNet4Release())
EndFunc

Func DotNet4ReleaseToDisplayVersion($strDotNet4Release)
  Switch $strDotNet4Release
    Case "378389"
      Return "4.5"
	  
    Case "378675" ; Windows 8.1 / Windows Server 2012 R2
      Return "4.5.1"
    Case "378758"
      Return "4.5.1"
	  
    Case "379893"
      Return "4.5.2"
	  
    Case "393295" ; Windows 10 1507 (10240)
      Return "4.6"
    Case "393297"
      Return "4.6"
	  
    Case "394254" ; Windows 10 1511 (10586)
      Return "4.6.1"
    Case "394271"
      Return "4.6.1"
	  
    Case "394802" ; Windows 10 1607 / Windows Server 2016 (14393)
      Return "4.6.2"
    Case "394806"
      Return "4.6.2"
	  
    Case "460798" ; Windows 10 1703 (15063)
      Return "4.7"
    Case "460805"
      Return "4.7"
	  
    Case "461308" ;  Windows 10 1709 (16299)
      Return "4.7.1"
    Case "461310"
      Return "4.7.1"
	  
    Case "461808" ; Windows 10 1803 (17134)
      Return "4.7.2"
    Case "461814"
      Return "4.7.2"
	  
    Case "528040" ; Windows 10 1903/1909 (18362)
      Return "4.8"
    Case "528049"
      Return "4.8"
    Case "528372" ; Windows 10 2004/20H2/21H1/21H2 (19041)
      Return "4.8"
    Case "528449" ; Windows Server 2022 (20348) / Windows 11 (22000)
      Return "4.8"

    Case "533320" ; Windows 11 (22621)
      Return "4.8.1"
    Case "533325"
      Return "4.8.1"
    Case Else
      Return ""
  EndSwitch
EndFunc

Func DotNet4MainVersion()
  Return StringLeft(DotNet4Version(), 3)
EndFunc

Func DotNet4TargetRelease()
  Switch @OSVersion
    Case "WIN_10"
      If (Number(@OSBuild) < 19041) Then
        Switch @OSBuild
          Case "10240"
		    Return "394806"
          Case "14393"
		    Return "528049"
          Case "18362", "18363"
		    Return "528040"
		  Case Else
		    Return "528049"
        EndSwitch
      Else
        Return "533325"
      EndIf
    Case "WIN_2016"
      Return "528049"
    Case "WIN_2019"
      Return "528049"
    Case "WIN_2022"
      Return "533325"
	Case "WIN_11"
      Switch @OSBuild
        Case "22000"
          Return "533325"
        Case "22621", "22631", "26100", "26200", "26300", "28000"
          Return "533320"
        Case Else
          Return "533320"
      EndSwitch
	Case Else
      Return "0"
  EndSwitch
EndFunc

Func DotNet4TargetVersionDisplay()
  Return DotNet4ReleaseToDisplayVersion(DotNet4TargetRelease())
EndFunc

Func WMFMainVersion()
  Return StringLeft(RegRead($reg_key_wmf, $reg_val_pshversion), 3)
EndFunc

Func WMFTargetVersion()
  Return "5.1"
EndFunc

Func HashFilesPresent($basepath)
  Return FileExists($basepath & $path_rel_hashes)
EndFunc

Func AutologonPresent($basepath)
  Return FileExists($basepath & $path_rel_autologon)
EndFunc

Func RootCertificatesPresent($basepath)
  Return FileExists($basepath & $path_rel_rcerts)
EndFunc

Func CPPPresent($basepath)
  Return FileExists($basepath & $path_rel_cpp)
EndFunc

Func EdgePresent($basepath)
  Return (FileExists($basepath & $path_rel_edge) Or FileExists($basepath & $path_rel_msedge_legacy))
EndFunc

Func WebView2Present($basepath)
  Return FileExists($basepath & $path_rel_webview2)
EndFunc

Func DotNet4InstPresent($basepath)
  Switch DotNet4TargetVersionDisplay()
    Case "4.8"
      Return FileExists($basepath & $path_rel_instdotnet48)
    Case "4.8.1"
      Return FileExists($basepath & $path_rel_instdotnet481)
    Case Else
      Return FileExists($basepath & $path_rel_instdotnet48) ; not optimal, but working
  EndSwitch
EndFunc

Func ListMSIPackages()
Dim $result

  $result = RunWait(@ComSpec & " /D /C TouchMSITree.cmd /listall", $scriptdir & "\cmd", @SW_HIDE)
  If $result = 0 Then
    $result = @error
  EndIf
  Return $result
EndFunc

; Single unified DPI strategy via Win32 GDI / User32 API
Func CalcGUISize()
  Dim $dpi, $hDC, $aDPI

  ; Enable process DPI awareness across modern Windows (Vista through Windows 11)
  DllCall("user32.dll", "bool", "SetProcessDPIAware")

  ; Query system DPI via GetDpiForSystem (Windows 10 1607+) or GetDeviceCaps (GDI fallback)
  $dpi = 0
  $aDPI = DllCall("user32.dll", "uint", "GetDpiForSystem")
  If (Not @error) And ($aDPI[0] > 0) Then
    $dpi = $aDPI[0]
  EndIf
  If ($dpi = 0) Then
    $hDC = DllCall("user32.dll", "handle", "GetDC", "hwnd", 0)
    If (Not @error) And ($hDC[0] <> 0) Then
      $aDPI = DllCall("gdi32.dll", "int", "GetDeviceCaps", "handle", $hDC[0], "int", 90) ; 90 = LOGPIXELSY
      If (Not @error) And ($aDPI[0] > 0) Then
        $dpi = $aDPI[0]
      EndIf
      DllCall("user32.dll", "int", "ReleaseDC", "hwnd", 0, "handle", $hDC[0])
    EndIf
  EndIf
  If ($dpi = 0) Then
    $dpi = RegRead($reg_key_hkcu_winmetrics, $reg_val_applieddpi)
    If ($dpi = "") Then $dpi = RegRead($reg_key_hkcu_desktop, $reg_val_logpixels)
  EndIf
  If ($dpi = 0) Or ($dpi = "") Then
    $dpi = $default_logpixels
  EndIf

  ; Proportional UI metrics scaled from 96 DPI baseline
  $dlgheight = 395 * $dpi / $default_logpixels
  If $gergui Then
    $txtwidth = 240 * $dpi / $default_logpixels
  Else
    $txtwidth = 220 * $dpi / $default_logpixels
  EndIf
  $txtheight = 22 * $dpi / $default_logpixels
  $btnwidth = 88 * $dpi / $default_logpixels
  $btnheight = 28 * $dpi / $default_logpixels
  $txtxoffset = 12 * $dpi / $default_logpixels
  $txtyoffset = 10 * $dpi / $default_logpixels
  Return 0
EndFunc

; Main Dialog
AutoItSetOption("GUICloseOnESC", 0)
AutoItSetOption("TrayAutoPause", 0)
AutoItSetOption("TrayIconHide", 1)
$gergui = ShowGUIInGerman()
CalcGUISize()
$groupwidth = 2 * $txtwidth + 2 * $txtxoffset
$maindlg = GUICreate($caption, $groupwidth + 4 * $txtxoffset, $dlgheight)
GUISetFont(9, 400, 0, "Segoe UI")

$scriptdir = AssignScriptDirectory()

;  Label
$txtxpos = $txtxoffset
$txtypos = $txtyoffset
If $gergui Then
  GUICtrlCreateLabel("Wählen Sie die gewünschten Optionen und klicken Sie auf 'Start'," & @LF & "um die fehlenden Microsoft-Updates auf Ihrem System zu installieren.", $txtxpos, $txtypos, 3 * $groupwidth / 4, 1.5 * $txtheight)
Else
  GUICtrlCreateLabel("Select desired options and click 'Start'" & @LF & "to install missing Microsoft updates on your computer.", $txtxpos, $txtypos, 3 * $groupwidth / 4, 1.5 * $txtheight)
EndIf

;  Medium info group
$builddate = MediumBuildDate($scriptdir)
If ($builddate <> "") Then
  $txtxpos = 3 * $txtxoffset + 3 * $groupwidth / 4
  $txtypos = 0
  If $gergui Then
    GUICtrlCreateGroup("Medium-Info", $txtxpos, $txtypos, $groupwidth / 4, 2 * $txtheight)
  Else
    GUICtrlCreateGroup("Medium info", $txtxpos, $txtypos, $groupwidth / 4, 2 * $txtheight)
  EndIf
  $txtxpos = $txtxpos + $txtxoffset
  $txtypos = $txtypos + 1.5 * $txtyoffset + 2
  GUICtrlCreateLabel("Build: " & $builddate, $txtxpos, $txtypos, $groupwidth / 4 - 2 * $txtxoffset, $txtheight)
EndIf

;  Tab control
$txtxpos = $txtxoffset
$txtypos = $txtyoffset + 1.5 * $txtheight
GuiCtrlCreateTab($txtxpos, $txtypos, $groupwidth + 2 * $txtxoffset, $dlgheight - $btnheight - 1.5 * $txtheight - 3 * $txtyoffset)

;  Updating Tab
If $gergui Then
  $tabitemfocused = GuiCtrlCreateTabItem("Aktualisierung")
Else
  $tabitemfocused = GuiCtrlCreateTabItem("Updating")
EndIf

;  Installation group
$txtxpos = 2 * $txtxoffset
$txtypos = 3.5 * $txtyoffset + 1.5 * $txtheight
GUICtrlCreateGroup("Installation", $txtxpos, $txtypos, $groupwidth, 7.2 * $txtheight)

; Perform Feature Update via Enablement Package
$txtxpos = 3 * $txtxoffset
$txtypos = $txtypos + 1.5 * $txtyoffset
If $gergui Then
  $buildupgrade = GUICtrlCreateCheckbox("Feature Update Über Enablement Package", $txtxpos, $txtypos, $txtwidth, $txtheight)
Else
  $buildupgrade = GUICtrlCreateCheckbox("Feature Update via Enablement Package", $txtxpos, $txtypos, $txtwidth, $txtheight)
EndIf
If ( (BuildUpgradeEnforced() <= 1) AND (BuildUpgradeAvailable($scriptdir, 0)) ) Then
  If MyIniRead($ini_section_installation, $ini_value_buildupgrade, $enabled) = $enabled Then
    GUICtrlSetState(-1, $GUI_CHECKED)
  Else
    GUICtrlSetState(-1, $GUI_UNCHECKED)
  EndIf
Else
  If ( (BuildUpgradeEnforced() > 1 ) AND (BuildUpgradeAvailable($scriptdir, 1)) ) Then
    GUICtrlSetState(-1, $GUI_CHECKED + $GUI_DISABLE)
  Else
    GUICtrlSetState(-1, $GUI_UNCHECKED + $GUI_DISABLE)
  EndIf
EndIf
If IsBuildIneligible(@OSBuild) Then
  GUICtrlSetState($buildupgrade, $GUI_UNCHECKED + $GUI_DISABLE)
  If $gergui Then
    MsgBox(BitOr($MB_TASKMODAL, $MB_ICONINFORMATION, $MB_OK), "Information", _
      "Auf diesem System wird Windows 11 Build " & @OSBuild & " (26H1) ausgeführt." & @LF & _
      "Diese Version befindet sich auf einem separaten Servicing-Zweig und ist" & @LF & _
      "für ein Upgrade über Enablement Package nicht berechtigt.")
  Else
    MsgBox(BitOr($MB_TASKMODAL, $MB_ICONINFORMATION, $MB_OK), "Information", _
      "This system is running Windows 11 build " & @OSBuild & " (26H1)." & @LF & _
      "This version is on a separate servicing branch and is ineligible" & @LF & _
      "for in-place feature upgrade via enablement package.")
  EndIf
EndIf

; Update Root Certificates
$txtxpos = $txtxpos + $txtwidth
If $gergui Then
  $rcerts = GUICtrlCreateCheckbox("Stammzertifikate aktualisieren", $txtxpos, $txtypos, $txtwidth, $txtheight)
Else
  $rcerts = GUICtrlCreateCheckbox("Update Root Certificates", $txtxpos, $txtypos, $txtwidth, $txtheight)
EndIf
If RootCertificatesPresent($scriptdir) Then
  If MyIniRead($ini_section_installation, $ini_value_rcerts, $enabled) = $enabled Then
    GUICtrlSetState(-1, $GUI_CHECKED)
  Else
    GUICtrlSetState(-1, $GUI_UNCHECKED)
  EndIf
Else
  GUICtrlSetState(-1, $GUI_UNCHECKED + $GUI_DISABLE)
EndIf

; Install .NET Framework 3.5
$txtxpos = 3 * $txtxoffset
$txtypos = $txtypos + $txtheight
If $gergui Then
  $dotnet35 = GUICtrlCreateCheckbox(".NET Framework 3.5 installieren", $txtxpos, $txtypos, $txtwidth, $txtheight)
Else
  $dotnet35 = GUICtrlCreateCheckbox("Install .NET Framework 3.5", $txtxpos, $txtypos, $txtwidth, $txtheight)
EndIf
If MyIniRead($ini_section_installation, $ini_value_dotnet35, $disabled) = $enabled Then
  GUICtrlSetState(-1, $GUI_CHECKED)
Else
  GUICtrlSetState(-1, $GUI_UNCHECKED)
EndIf

; Install .NET Framework 4
$txtxpos = 3 * $txtxoffset
$txtypos = $txtypos + $txtheight
If $gergui Then
  $dotnet4 = GUICtrlCreateCheckbox(".NET Framework " & DotNet4TargetVersionDisplay() & " installieren", $txtxpos, $txtypos, $txtwidth, $txtheight)
Else
  $dotnet4 = GUICtrlCreateCheckbox("Install .NET Framework " & DotNet4TargetVersionDisplay(), $txtxpos, $txtypos, $txtwidth, $txtheight)
EndIf
If ( (Number(DotNet4Release()) >= Number(DotNet4TargetRelease())) OR (NOT DotNet4InstPresent($scriptdir)) ) Then
  GUICtrlSetState(-1, $GUI_UNCHECKED + $GUI_DISABLE)
Else
  If ( (DotNet4MainVersion() = "4.0") OR (DotNet4MainVersion() = "4.5") OR (DotNet4DisplayVersion() = "4.6") OR (DotNet4DisplayVersion() = "4.6.1")) Then
    GUICtrlSetState(-1, $GUI_CHECKED + $GUI_DISABLE)
  Else
    If MyIniRead($ini_section_installation, $ini_value_dotnet4, $disabled) = $enabled Then
      GUICtrlSetState(-1, $GUI_CHECKED)
    Else
      GUICtrlSetState(-1, $GUI_UNCHECKED)
    EndIf
  EndIf
EndIf

; Install Windows Management Framework
$txtxpos = $txtxpos + $txtwidth
If $gergui Then
  $wmf = GUICtrlCreateCheckbox("Management Framework " & WMFTargetVersion() & " installieren", $txtxpos, $txtypos, $txtwidth, $txtheight)
Else
  $wmf = GUICtrlCreateCheckbox("Install Management Framework " & WMFTargetVersion(), $txtxpos, $txtypos, $txtwidth, $txtheight)
EndIf
If ( (@OSVersion = "WIN_10") OR (@OSVersion = "WIN_2016") OR (@OSVersion = "WIN_2019") OR (@OSVersion = "WIN_2022") OR (@OSVersion = "WIN_11") _
  OR ( (DotNet4MainVersion() <> "4.5") AND (DotNet4MainVersion() <> "4.6") AND (DotNet4MainVersion() <> "4.7") AND (DotNet4MainVersion() <> "4.8") AND (NOT IsCheckBoxChecked($dotnet4)) ) _
  OR (WMFMainVersion() = WMFTargetVersion()) ) Then
  GUICtrlSetState(-1, $GUI_UNCHECKED + $GUI_DISABLE)
Else
  If MyIniRead($ini_section_installation, $ini_value_wmf, $disabled) = $enabled Then
    GUICtrlSetState(-1, $GUI_CHECKED)
  Else
    GUICtrlSetState(-1, $GUI_UNCHECKED)
  EndIf
EndIf

; Install .NET Framework 5 (and newer)
$txtxpos = 3 * $txtxoffset
$txtypos = $txtypos + $txtheight
If $gergui Then
  $dotnet5 = GUICtrlCreateCheckbox(".NET Framework 5 (und neuer) aktualisieren", $txtxpos, $txtypos, $txtwidth, $txtheight)
Else
  $dotnet5 = GUICtrlCreateCheckbox("Update .NET Framework 5 (and newer)", $txtxpos, $txtypos, $txtwidth, $txtheight)
EndIf
If MyIniRead($ini_section_installation, $ini_value_dotnet5, $disabled) = $enabled Then
  GUICtrlSetState(-1, $GUI_CHECKED)
Else
  GUICtrlSetState(-1, $GUI_UNCHECKED)
EndIf

; Update C++ Runtime Libraries
$txtxpos = $txtxpos + $txtwidth
If $gergui Then
  $cpp = GUICtrlCreateCheckbox("C++-Laufzeitbibliotheken aktualisieren", $txtxpos, $txtypos, $txtwidth, $txtheight)
Else
  $cpp = GUICtrlCreateCheckbox("Update C++ Runtime Libraries", $txtxpos, $txtypos, $txtwidth, $txtheight)
EndIf
If CPPPresent($scriptdir) Then
  If MyIniRead($ini_section_installation, $ini_value_cpp, $enabled) = $enabled Then
    GUICtrlSetState(-1, $GUI_CHECKED)
  Else
    GUICtrlSetState(-1, $GUI_UNCHECKED)
  EndIf
Else
  GUICtrlSetState(-1, $GUI_UNCHECKED + $GUI_DISABLE)
EndIf

; Install Microsoft Edge
$txtxpos = 3 * $txtxoffset
$txtypos = $txtypos + $txtheight
If $gergui Then
  $instedge = GUICtrlCreateCheckbox("Microsoft Edge installieren", $txtxpos, $txtypos, $txtwidth, $txtheight)
Else
  $instedge = GUICtrlCreateCheckbox("Install Microsoft Edge", $txtxpos, $txtypos, $txtwidth, $txtheight)
EndIf
If EdgePresent($scriptdir) Then
  If MyIniRead($ini_section_installation, $ini_value_instedge, $disabled) = $enabled Then
    GUICtrlSetState(-1, $GUI_CHECKED)
  Else
    GUICtrlSetState(-1, $GUI_UNCHECKED)
  EndIf
Else
  GUICtrlSetState(-1, $GUI_UNCHECKED + $GUI_DISABLE)
EndIf

; Install Microsoft Edge WebView2 Runtime
$txtxpos = $txtxpos + $txtwidth
If $gergui Then
  $instwebview2 = GUICtrlCreateCheckbox("Edge WebView2-Laufzeit installieren", $txtxpos, $txtypos, $txtwidth, $txtheight)
Else
  $instwebview2 = GUICtrlCreateCheckbox("Install Edge WebView2 Runtime", $txtxpos, $txtypos, $txtwidth, $txtheight)
EndIf
If WebView2Present($scriptdir) Then
  If MyIniRead($ini_section_installation, $ini_value_instwebview2, $disabled) = $enabled Then
    GUICtrlSetState(-1, $GUI_CHECKED)
  Else
    GUICtrlSetState(-1, $GUI_UNCHECKED)
  EndIf
Else
  GUICtrlSetState(-1, $GUI_UNCHECKED + $GUI_DISABLE)
EndIf

; Update Microsoft Office
$txtxpos = 3 * $txtxoffset
$txtypos = $txtypos + $txtheight
If $gergui Then
  $instoffice = GUICtrlCreateCheckbox("Microsoft Office aktualisieren", $txtxpos, $txtypos, $txtwidth, $txtheight)
Else
  $instoffice = GUICtrlCreateCheckbox("Update Microsoft Office", $txtxpos, $txtypos, $txtwidth, $txtheight)
EndIf
$txtxpos = $txtxpos + $txtwidth
$lbloffice = GUICtrlCreateLabel(Office16Description(), $txtxpos, $txtypos + 3, $txtwidth, $txtheight)
GUICtrlSetColor($lbloffice, 0x606060)

If Office16Detected() Then
  If MyIniRead($ini_section_installation, $ini_value_instoffice, $enabled) = $enabled Then
    GUICtrlSetState($instoffice, $GUI_CHECKED)
  Else
    GUICtrlSetState($instoffice, $GUI_UNCHECKED)
  EndIf
Else
  GUICtrlSetState($instoffice, $GUI_UNCHECKED + $GUI_DISABLE)
EndIf

;  Control group
$txtxpos = 2 * $txtxoffset
$txtypos = $txtypos + 2.5 * $txtyoffset
If $gergui Then
  GUICtrlCreateGroup("Steuerung", $txtxpos, $txtypos, $groupwidth, 4 * $txtheight)
Else
  GUICtrlCreateGroup("Control", $txtxpos, $txtypos, $groupwidth, 4 * $txtheight)
EndIf

; Verify
$txtxpos = 3 * $txtxoffset
$txtypos = $txtypos + 1.5 * $txtyoffset
If $gergui Then
  $verify = GUICtrlCreateCheckbox("Installationspakete verifizieren", $txtxpos, $txtypos, $txtwidth, $txtheight)
Else
  $verify = GUICtrlCreateCheckbox("Verify installation packages", $txtxpos, $txtypos, $txtwidth, $txtheight)
EndIf
If HashFilesPresent($scriptdir) Then
  If MyIniRead($ini_section_control, $ini_value_verify, $enabled) = $enabled Then
    GUICtrlSetState(-1, $GUI_CHECKED)
  Else
    GUICtrlSetState(-1, $GUI_UNCHECKED)
  EndIf
Else
  GUICtrlSetState(-1, $GUI_UNCHECKED + $GUI_DISABLE)
EndIf

;  Automatic reboot and recall
$txtxpos = $txtxpos + $txtwidth
If $gergui Then
  $autoreboot = GUICtrlCreateCheckbox("Automatisch neu starten und fortsetzen", $txtxpos, $txtypos, $txtwidth, $txtheight)
Else
  $autoreboot = GUICtrlCreateCheckbox("Automatic reboot and recall", $txtxpos, $txtypos, $txtwidth, $txtheight)
EndIf
If ( (@OSVersion = "WIN_10") OR (@OSVersion = "WIN_2016") OR (@OSVersion = "WIN_2019") OR (@OSVersion = "WIN_2022") OR (@OSVersion = "WIN_11") OR (NOT AutologonPresent($scriptdir)) ) Then
  GUICtrlSetState(-1, $GUI_UNCHECKED + $GUI_DISABLE)
Else
  If MyIniRead($ini_section_control, $ini_value_autoreboot, $disabled) = $enabled Then
    GUICtrlSetState(-1, $GUI_CHECKED)
  Else
    GUICtrlSetState(-1, $GUI_UNCHECKED)
  EndIf
EndIf

;  Automatic shutdown
$txtxpos = 3 * $txtxoffset
$txtypos = $txtypos + $txtheight
If $gergui Then
  $shutdown = GUICtrlCreateCheckbox("Herunterfahren nach Abschluss", $txtxpos, $txtypos, $txtwidth, $txtheight)
Else
  $shutdown = GUICtrlCreateCheckbox("Shut down on completion", $txtxpos, $txtypos, $txtwidth, $txtheight)
EndIf
If MyIniRead($ini_section_control, $ini_value_shutdown, $disabled) = $enabled Then
  GUICtrlSetState(-1, $GUI_CHECKED)
Else
  GUICtrlSetState(-1, $GUI_UNCHECKED)
EndIf

; Show log file
$txtxpos = $txtxpos + $txtwidth
If $gergui Then
  $showlog = GUICtrlCreateCheckbox("Protokolldatei anzeigen", $txtxpos, $txtypos, $txtwidth, $txtheight)
Else
  $showlog = GUICtrlCreateCheckbox("Show log file", $txtxpos, $txtypos, $txtwidth, $txtheight)
EndIf
If ( (MyIniRead($ini_section_messaging, $ini_value_showlog, $disabled) = $enabled) _
 AND (NOT IsCheckBoxChecked($shutdown)) ) Then
  GUICtrlSetState(-1, $GUI_CHECKED)
Else
  GUICtrlSetState(-1, $GUI_UNCHECKED)
  If IsCheckBoxChecked($shutdown) Then
    GUICtrlSetState(-1, $GUI_DISABLE)
  EndIf
EndIf

; Audit only
$txtxpos = 3 * $txtxoffset
$txtypos = $txtypos + $txtheight
If $gergui Then
  $auditonly = GUICtrlCreateCheckbox("Nur auditieren (Bericht fehlender Updates)", $txtxpos, $txtypos, $txtwidth * 1.5, $txtheight)
Else
  $auditonly = GUICtrlCreateCheckbox("Audit only (missing updates report)", $txtxpos, $txtypos, $txtwidth * 1.5, $txtheight)
EndIf
If MyIniRead($ini_section_control, $ini_value_auditonly, $disabled) = $enabled Then
  GUICtrlSetState(-1, $GUI_CHECKED)
  GUICtrlSetState($autoreboot, $GUI_UNCHECKED + $GUI_DISABLE)
  GUICtrlSetState($shutdown, $GUI_UNCHECKED + $GUI_DISABLE)
Else
  GUICtrlSetState(-1, $GUI_UNCHECKED)
EndIf

;  Software Tab
$msicount = 1
ListMSIPackages()
If FileExists(@TempDir & $path_rel_msi_all) Then
  GuiCtrlCreateTabItem("Software")

  ; Select all
  $txtxpos = 2 * $txtxoffset
  $txtypos = 3.5 * $txtyoffset + 1.5 * $txtheight
  If $gergui Then
    $msiall = GUICtrlCreateCheckbox("Alle auswählen", $txtxpos, $txtypos, $txtwidth, $txtheight)
  Else
    $msiall = GUICtrlCreateCheckbox("Select all", $txtxpos, $txtypos, $txtwidth, $txtheight)
  EndIf
  ;  MSI packages' group
  $txtypos = $txtypos + $txtheight
  If $gergui Then
    GUICtrlCreateGroup("MSI-Pakete", $txtxpos, $txtypos, $groupwidth, ($msimax / 2 + 1) * $txtheight)
  Else
    GUICtrlCreateGroup("MSI packages", $txtxpos, $txtypos, $groupwidth, ($msimax / 2 + 1) * $txtheight)
  EndIf
  $txtxpos = 3 * $txtxoffset
  $txtypos = $txtypos + 1.5 * $txtyoffset
  For $msicount = 0 To $msimax - 1
    $line = FileReadLine(@TempDir & $path_rel_msi_all, $msicount + 1)
    If @error <> 0 Then ExitLoop
    $msipacks[$msicount] = GUICtrlCreateCheckbox($line, $txtxpos + Mod($msicount, 2) * $txtwidth, $txtypos + BitShift($msicount, 1) * $txtheight, $txtwidth, $txtheight)
    If MyIniRead($ini_section_msi, GUICtrlRead(-1, 1), $disabled) = $enabled Then
      GUICtrlSetState(-1, $GUI_CHECKED)
    EndIf
  Next
  FileDelete(@TempDir & $path_rel_msi_all)
  If $msicount = 0 Then $msicount = 1
EndIf

;  End Tab item definition
GuiCtrlCreateTabItem("")
GUICtrlSetState($tabitemfocused, $GUI_SHOW)

;  Start button
$txtypos = $dlgheight - $btnheight - $txtyoffset
$btn_start = GUICtrlCreateButton("Start", $txtxoffset, $txtypos, $btnwidth, $btnheight)
GUICtrlSetResizing (-1, $GUI_DOCKLEFT + $GUI_DOCKBOTTOM)

;  Exit button
If $gergui Then
  $btn_exit = GUICtrlCreateButton("Ende", $groupwidth - $btnwidth + 3 * $txtxoffset, $txtypos, $btnwidth, $btnheight)
Else
  $btn_exit = GUICtrlCreateButton("Exit", $groupwidth - $btnwidth + 3 * $txtxoffset, $txtypos, $btnwidth, $btnheight)
EndIf
GUICtrlSetResizing (-1, $GUI_DOCKRIGHT + $GUI_DOCKBOTTOM)

; GUI message loop
GUISetState()
If ( (@OSVersion = "WIN_XP") OR (@OSVersion = "WIN_2003") OR (@OSVersion = "WIN_8") OR (@OSVersion = "WIN_VISTA") OR (@OSVersion = "WIN_2008") OR (@OSVersion = "WIN_7") OR (@OSVersion = "WIN_2008R2") ) Then
  If $gergui Then
    MsgBox(BitOr($MB_TASKMODAL, $MB_ICONERROR, $MB_OK), "Fehler", "Nicht unterstütztes Betriebssystem: " & @OSVersion)
  Else
    MsgBox(BitOr($MB_TASKMODAL, $MB_ICONERROR, $MB_OK), "Fehler", "Unsupported Operating System: " & @OSVersion)
  EndIf
  Exit(1)
EndIf
If NOT WSHAvailable() Then
  If $gergui Then
    MsgBox(BitOr($MB_TASKMODAL, $MB_ICONERROR, $MB_OK), "Fehler", "Der Windows Script Host ist deaktiviert. Bitte prüfen Sie die Registrierungswerte" _
                     & @LF & "HKEY_LOCAL_MACHINE\Software\Microsoft\Windows Script Host\Settings\Enabled und" _
                     & @LF & "HKEY_CURRENT_USER\Software\Microsoft\Windows Script Host\Settings\Enabled")
  Else
    MsgBox(BitOr($MB_TASKMODAL, $MB_ICONERROR, $MB_OK), "Error", "Windows Script Host is disabled on this machine. Please check registry values" _
                    & @LF & "HKEY_LOCAL_MACHINE\Software\Microsoft\Windows Script Host\Settings\Enabled and" _
                    & @LF & "HKEY_CURRENT_USER\Software\Microsoft\Windows Script Host\Settings\Enabled")
  EndIf
  Exit(1)
EndIf
If $scriptdir = "" Then
  If $gergui Then
    MsgBox(BitOr($MB_TASKMODAL, $MB_ICONERROR, $MB_OK), "Fehler", "Dem Skript-Pfad " & @ScriptDir _
                     & @LF & "konnte kein Laufwerksbuchstabe zugewiesen werden.")
  Else
    MsgBox(BitOr($MB_TASKMODAL, $MB_ICONERROR, $MB_OK), "Error", "Unable to assign a drive letter" _
                    & @LF & "to the script path " & @ScriptDir)
  EndIf
  Exit(1)
EndIf
If NOT PathValid($scriptdir) Then
  If $gergui Then
    MsgBox(BitOr($MB_TASKMODAL, $MB_ICONERROR, $MB_OK), "Fehler", "Der Skript-Pfad darf nicht mehr als " & $path_max_length & " Zeichen lang sein und" _
                     & @LF & "darf keines der folgenden Zeichen enthalten: " & $path_invalid_chars)
  Else
    MsgBox(BitOr($MB_TASKMODAL, $MB_ICONERROR, $MB_OK), "Error", "The script path must not be more than " & $path_max_length & " characters long and" _
                    & @LF & "must not contain any of the following characters: " & $path_invalid_chars)
  EndIf
  Exit(1)
EndIf
If NOT PathValid(@TempDir) Then
  If $gergui Then
    MsgBox(BitOr($MB_TASKMODAL, $MB_ICONERROR, $MB_OK), "Fehler", "Der %TEMP%-Pfad darf nicht mehr als " & $path_max_length & " Zeichen lang sein und" _
                     & @LF & "darf keines der folgenden Zeichen enthalten: " & $path_invalid_chars)
  Else
    MsgBox(BitOr($MB_TASKMODAL, $MB_ICONERROR, $MB_OK), "Error", "The %TEMP% path must not be more than " & $path_max_length & " characters long and" _
                    & @LF & "must not contain any of the following characters: " & $path_invalid_chars)
  EndIf
  Exit(1)
EndIf
If (StringRight(EnvGet("TEMP"), 1) = "\") OR (StringRight(EnvGet("TEMP"), 1) = ":") Then
  If $gergui Then
    MsgBox(BitOr($MB_TASKMODAL, $MB_ICONERROR, $MB_OK), "Fehler", "Der %TEMP%-Pfad enthält einen abschließenden Backslash ('\')" _
                     & @LF & "oder einen abschließenden Doppelpunkt (':').")
  Else
    MsgBox(BitOr($MB_TASKMODAL, $MB_ICONERROR, $MB_OK), "Error", "The %TEMP% path contains a trailing backslash ('\')" _
                    & @LF & "or a trailing colon (':').")
  EndIf
  Exit(1)
EndIf
If ( (@OSVersion = "WIN_2012") _
 AND FileExists(@ProgramFilesDir & "\Internet Explorer\iexplore.exe") _
 AND ( (IEVersion() = "8") OR (IEVersion() = "9") OR (IEVersion() = "10") ) _
 AND (DefaultIniRead($ini_section_installation, $ini_value_skipieinst, $disabled) = $disabled) _
 AND (DefaultIniRead($ini_section_messaging, $ini_value_showieinfo, $enabled) = $enabled) ) Then
  If $gergui Then
     MsgBox(BitOr($MB_TASKMODAL, $MB_ICONINFORMATION, $MB_OK), "Information", "Auf diesem System wird die neueste Version des Internet Explorers (IE11)" _
                           & @LF & "automatisch installiert, wenn Sie die Aktualisierung starten.")
  Else
     MsgBox(BitOr($MB_TASKMODAL, $MB_ICONINFORMATION, $MB_OK), "Information", "On this system, the most recent version of Internet Explorer (IE11)" _
                           & @LF & "will be automatically installed, when you start the updating process.")
  EndIf
EndIf
;MsgBox(BitOr($MB_TASKMODAL, $MB_ICONINFORMATION, $MB_OK), "DEBUG", "DotNet4MainVersion()=" & DotNet4MainVersion() & @LF & "DotNet4DisplayVersion()=" & DotNet4DisplayVersion() & @LF & "DotNet4Release()=" & DotNet4Release())
If ( ( (DotNet4MainVersion() <> "") AND ((DotNet4MainVersion() = "4.5") OR ((DotNet4MainVersion() = "4.6") AND (DotNet4DisplayVersion() <> "4.6.2")))) _
 AND (DefaultIniRead($ini_section_messaging, $ini_value_showdotnet4info, $enabled) = $enabled) ) Then
  If $gergui Then
     MsgBox(BitOr($MB_TASKMODAL, $MB_ICONINFORMATION, $MB_OK), "Information", "Auf diesem System wird Version 4.6.2 des .NET Framework" _
                           & @LF & "automatisch installiert, wenn Sie die Aktualisierung starten.")
  Else
     MsgBox(BitOr($MB_TASKMODAL, $MB_ICONINFORMATION, $MB_OK), "Information", "On this system, version 4.6.2 of .NET Framework" _
                           & @LF & "will be automatically installed, when you start the updating process.")
  EndIf
EndIf
If ( BuildUpgradeEnforced() > 0 ) Then
  If BuildUpgradeAvailable($scriptdir, 1) Then
    If $gergui Then
      MsgBox(BitOr($MB_TASKMODAL, $MB_ICONINFORMATION, $MB_OK), "Information", "Auf diesem System wird das Feature Update Über Enablement Package automatisch installiert, wenn Sie die Aktualisierung starten.")
    Else
      MsgBox(BitOr($MB_TASKMODAL, $MB_ICONINFORMATION, $MB_OK), "Information", "On this system, the Feature Update via Enablement Package will be automatically installed, when you start the updating process.")
    EndIf
  Else
    If $gergui Then
      MsgBox(BitOr($MB_TASKMODAL, $MB_ICONWARNING, $MB_OK), "Warnung", "Auf diesem System wird eine nicht unterstützte Version von Windows 10 ausgeführt, welche nicht automatisch aktualisiert werden kann." & @LF & "Die Update-Ermittlung kann fehlende Updates für Windows melden.")
    Else
      MsgBox(BitOr($MB_TASKMODAL, $MB_ICONWARNING, $MB_OK), "Warning", "This system is running a version of Windows 10, which cannot be automatically upgraded to a supported one." & @LF & "The dynamic update search might report missing updates for Windows.")
    EndIf
  EndIf
EndIf
Local $accelKeys[2][2] = [["{enter}", $btn_start], ["{escape}", $btn_exit]]
GUISetAccelerators($accelKeys)
While 1
  Switch GUIGetMsg()
    Case $GUI_EVENT_CLOSE    ; Window closed
      If $mapped Then
        DriveMapDel($scriptdir)
      EndIf
      ExitLoop

    Case $btn_exit           ; Exit Button pressed
      If $mapped Then
        DriveMapDel($scriptdir)
      EndIf
      ExitLoop

    Case $dotnet4              ; .NET 4 check box toggled
      If ( ( (IsCheckBoxChecked($dotnet4)) OR (DotNet4MainVersion() = "4.5") OR (DotNet4MainVersion() = "4.6") OR (DotNet4MainVersion() = "4.7") OR (DotNet4MainVersion() = "4.8") ) _
       AND (@OSVersion <> "WIN_10") AND (@OSVersion <> "WIN_2016") AND (@OSVersion <> "WIN_2019") AND (@OSVersion <> "WIN_2022") AND (@OSVersion <> "WIN_11") _
       AND (WMFMainVersion() <> WMFTargetVersion()) ) Then
        GUICtrlSetState($wmf, $GUI_ENABLE)
      Else
        GUICtrlSetState($wmf, $GUI_UNCHECKED + $GUI_DISABLE)
      EndIf

    Case $autoreboot         ; Automatic reboot check box toggled
      If IsCheckBoxChecked($autoreboot) Then
        If $gergui Then
          If MsgBox(BitOr($MB_TASKMODAL, $MB_DEFBUTTON2, $MB_ICONEXCLAMATION, $MB_YESNO), "Warnung", "Die Option 'Automatisch neu starten und fortsetzen' deaktiviert" _
                               & @LF & "temporär die Benutzerkontensteuerung (UAC), falls erforderlich." _
                               & @LF & "Möchten Sie fortsetzen?") = 7 Then
            GUICtrlSetState($autoreboot, $GUI_UNCHECKED)
          EndIf
        Else
          If MsgBox(BitOr($MB_TASKMODAL, $MB_DEFBUTTON2, $MB_ICONEXCLAMATION, $MB_YESNO), "Warning", "The option 'Automatic reboot and recall' temporarily" _
                               & @LF & "disables the User Account Control (UAC), if required." _
                               & @LF & "Do you wish to proceed?") = 7 Then
            GUICtrlSetState($autoreboot, $GUI_UNCHECKED)
          EndIf
        EndIf
      EndIf
      If ( (IsCheckBoxChecked($autoreboot)) AND (DriveGetType($scriptdir) = "Network") ) Then
        If $gergui Then
          If MsgBox(BitOr($MB_TASKMODAL, $MB_DEFBUTTON2, $MB_ICONEXCLAMATION, $MB_YESNO), "Warnung", @ScriptName & " wurde von einer Netzwerkfreigabe gestartet." _
                               & @LF & "Die Option 'Automatisch neu starten und fortsetzen'" _
                               & @LF & "funktioniert nur dann ohne Benutzereingriff," _
                               & @LF & "wenn diese Freigabe anonymen Zugriff erlaubt." _
                               & @LF & "Möchten Sie fortsetzen?") = 7 Then
            GUICtrlSetState($autoreboot, $GUI_UNCHECKED)
          EndIf
        Else
          If MsgBox(BitOr($MB_TASKMODAL, $MB_DEFBUTTON2, $MB_ICONEXCLAMATION, $MB_YESNO), "Warning", @ScriptName & " was started from a network share." _
                               & @LF & "The option 'Automatic reboot and recall'" _
                               & @LF & "does only work without user interaction," _
                               & @LF & "if this share permits anonymous access." _
                               & @LF & "Do you wish to proceed?") = 7 Then
            GUICtrlSetState($autoreboot, $GUI_UNCHECKED)
          EndIf
        EndIf
      EndIf

    Case $auditonly          ; Audit only check box toggled
      If IsCheckBoxChecked($auditonly) Then
        GUICtrlSetState($autoreboot, $GUI_UNCHECKED + $GUI_DISABLE)
        GUICtrlSetState($shutdown, $GUI_UNCHECKED + $GUI_DISABLE)
      Else
        If ( (@OSVersion = "WIN_10") OR (@OSVersion = "WIN_2016") OR (@OSVersion = "WIN_2019") OR (@OSVersion = "WIN_2022") OR (@OSVersion = "WIN_11") OR (NOT AutologonPresent($scriptdir)) ) Then
          GUICtrlSetState($autoreboot, $GUI_UNCHECKED + $GUI_DISABLE)
        Else
          GUICtrlSetState($autoreboot, $GUI_ENABLE)
          If MyIniRead($ini_section_control, $ini_value_autoreboot, $disabled) = $enabled Then
            GUICtrlSetState($autoreboot, $GUI_CHECKED)
          EndIf
        EndIf
        GUICtrlSetState($shutdown, $GUI_ENABLE)
        If MyIniRead($ini_section_control, $ini_value_shutdown, $disabled) = $enabled Then
          GUICtrlSetState($shutdown, $GUI_CHECKED)
          GUICtrlSetState($showlog, $GUI_UNCHECKED + $GUI_DISABLE)
        EndIf
      EndIf

    Case $shutdown           ; Automatic shutdown check box toggled
      If IsCheckBoxChecked($shutdown) Then
        GUICtrlSetState($showlog, $GUI_UNCHECKED + $GUI_DISABLE)
      Else
        GUICtrlSetState($showlog, $GUI_ENABLE)
      EndIf

    Case $msiall             ; Select all check box toggled
      If IsCheckBoxChecked($msiall) Then
        For $i = 0 To $msicount - 1
          GUICtrlSetState($msipacks[$i], $GUI_CHECKED)
        Next
      Else
        For $i = 0 To $msicount - 1
          GUICtrlSetState($msipacks[$i], $GUI_UNCHECKED)
        Next
      EndIf

    Case $msipacks[0] To $msipacks[$msicount - 1]
      For $i = 0 To $msicount - 1
        If NOT IsCheckBoxChecked($msipacks[$i]) Then
          GUICtrlSetState($msiall, $GUI_UNCHECKED)
          ExitLoop
        EndIf
      Next

    Case $btn_start          ; Start Button pressed
      $options = MyIniRead($ini_section_misc, $ini_value_wustatusserver, "")    ; Dummy use of $options
      If $options <> "" Then
        RegWrite($reg_key_windowsupdate, $reg_val_wustatusserver, "REG_SZ", $options)
      EndIf
      $options = ""
      If IsCheckBoxChecked($buildupgrade) Then
        $options = $options & " /upgradebuilds"
      EndIf
      If IsCheckBoxChecked($rcerts) Then
        $options = $options & " /updatercerts"
      EndIf
      If IsCheckBoxChecked($dotnet35) Then
        $options = $options & " /instdotnet35"
      EndIf
      If IsCheckBoxChecked($dotnet4) Then
        $options = $options & " /instdotnet4"
      EndIf
      If IsCheckBoxChecked($wmf) Then
        $options = $options & " /instwmf"
      EndIf
      If IsCheckBoxChecked($dotnet5) Then
        $options = $options & " /updatedotnet5"
      EndIf
      If IsCheckBoxChecked($cpp) Then
        $options = $options & " /updatecpp"
      EndIf
      If IsCheckBoxChecked($instedge) Then
        $options = $options & " /instedge"
      EndIf
      If IsCheckBoxChecked($instwebview2) Then
        $options = $options & " /instwebview2"
      EndIf
      If IsCheckBoxChecked($instoffice) Then
        $options = $options & " /updateoffice"
      EndIf
      If DefaultIniRead($ini_section_installation, $ini_value_skipieinst, $disabled) = $enabled Then
        $options = $options & " /skipieinst"
      EndIf
      If DefaultIniRead($ini_section_installation, $ini_value_skipdefs, $disabled) = $enabled Then
        $options = $options & " /skipdefs"
      EndIf
      If DefaultIniRead($ini_section_installation, $ini_value_skipdynamic, $disabled) = $enabled Then
        $options = $options & " /skipdynamic"
      EndIf
      If DefaultIniRead($ini_section_installation, $ini_value_all, $disabled) = $enabled Then
        $options = $options & " /all"
      EndIf
      If DefaultIniRead($ini_section_installation, $ini_value_excludestatics, $disabled) = $enabled Then
        $options = $options & " /excludestatics"
      EndIf
      If DefaultIniRead($ini_section_installation, $ini_value_seconly, $disabled) = $enabled Then
        $options = $options & " /seconly"
      EndIf
      If IsCheckBoxChecked($verify) Then
        $options = $options & " /verify"
      EndIf
      If IsCheckBoxChecked($auditonly) Then
        $options = $options & " /auditonly"
      EndIf
      If ( (BitAND(GUICtrlRead($autoreboot), $GUI_DISABLE) <> $GUI_DISABLE) _
       AND (IsCheckBoxChecked($autoreboot)) ) Then
        $options = $options & " /autoreboot"
      Else
        IniCopy()
      EndIf
      If IsCheckBoxChecked($shutdown) Then
        $options = $options & " /shutdown"
      EndIf
      If IsCheckBoxChecked($showlog) Then
        $options = $options & " /showlog"
      EndIf
      If DefaultIniRead($ini_section_messaging, $ini_value_showdismprogress, $disabled) = $enabled Then
        $options = $options & " /showdismprogress"
      EndIf
      If DefaultIniRead($ini_section_misc, $ini_value_monitoron, $disabled) = $enabled Then
        $options = $options & " /monitoron"
      EndIf
      $msilistfile = FileOpen(@WindowsDir & $path_rel_msi_selected, 10)
      If $msilistfile <> -1 Then
        For $i = 0 To $msicount - 1
          If IsCheckBoxChecked($msipacks[$i]) Then
            FileWriteLine($msilistfile, GUICtrlRead($msipacks[$i], 1))
          EndIf
        Next
        FileClose($msilistfile)
      EndIf
      If FileGetSize(@WindowsDir & $path_rel_msi_selected) = 0 Then
        FileDelete(@WindowsDir & $path_rel_msi_selected)
      EndIf
      If (@OSArch <> "X86") Then
        $pRedirect = DllStructCreate("ptr")
        _WinAPI_SetLastError(0)
        $dllCallResult = DllCall("kernel32.dll", "bool", "Wow64DisableWow64FsRedirection", "ptr*", DllStructGetPtr($pRedirect))
        If (@error <> 0) OR (NOT $dllCallResult[0]) Then
          If $gergui Then
            MsgBox(BitOr($MB_TASKMODAL, $MB_ICONERROR, $MB_OK), "Fehler", "Fehler #" & @error & " (Rükgabewert: " & $dllCallResult[0] _
                                   & ", API-Fehlercode: " & _WinAPI_GetLastError() & ")" _
                                   & " beim Aufruf von Wow64DisableWow64FsRedirection.")
          Else
            MsgBox(BitOr($MB_TASKMODAL, $MB_ICONERROR, $MB_OK), "Error", "Error #" & @error & " (Return value: " & $dllCallResult[0] _
                                  & ", API error code: " & _WinAPI_GetLastError() & ")" _
                                  & " when calling Wow64DisableWow64FsRedirection.")
          EndIf
          ExitLoop
        EndIf
      EndIf
      If Run(@ComSpec & " /D /C Update.cmd" & $options, $scriptdir, @SW_HIDE) = 0 Then
        If $gergui Then
          MsgBox(BitOr($MB_TASKMODAL, $MB_ICONERROR, $MB_OK), "Fehler", "Fehler #" & @error & " beim Aufruf von" _
                           & @LF & @ComSpec & " /D /C Update.cmd" & $options & " in" _
                           & @LF & $scriptdir & ".")
        Else
          MsgBox(BitOr($MB_TASKMODAL, $MB_ICONERROR, $MB_OK), "Error", "Error #" & @error & " when calling" _
                          & @LF & @ComSpec & " /D /C Update.cmd" & $options & " in" _
                          & @LF & $scriptdir & ".")
        EndIf
      EndIf
      If (@OSArch <> "X86") Then
        _WinAPI_SetLastError(0)
        DllCall("kernel32.dll", "bool", "Wow64RevertWow64FsRedirection", "ptr", $pRedirect)
        If (@error <> 0) OR (_WinAPI_GetLastError() <> 0) Then
          If $gergui Then
            MsgBox(BitOr($MB_TASKMODAL, $MB_ICONERROR, $MB_OK), "Fehler", "Fehler #" & @error & " (API-Fehlercode: " & _WinAPI_GetLastError() & ")" _
                                   & " beim Aufruf von Wow64RevertWow64FsRedirection.")
          Else
            MsgBox(BitOr($MB_TASKMODAL, $MB_ICONERROR, $MB_OK), "Error", "Error #" & @error & " (API error code: " & _WinAPI_GetLastError() & ")" _
                                  & " when calling Wow64RevertWow64FsRedirection.")
          EndIf
        EndIf
        $pRedirect = 0
      EndIf
      ExitLoop
  EndSwitch
WEnd
Exit
