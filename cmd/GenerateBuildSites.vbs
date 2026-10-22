' =======================================================================
' WSUS Offline Update - Build Site Propagation Tool (Windows VBScript Engine)
' File: cmd/GenerateBuildSites.vbs
'
' Propagates build definitions from static/builds.ini into:
'   1. UpdateGenerator.au3
'   2. cmd/DownloadUpdates.cmd
'   3. sh/download-updates-tasks/60-main-updates.bash
'   4. sh/update-generator-tasks/10-show-selection-dialogs-with-dialog.bash
'   5. client/UpdateInstaller.au3
'
' Preserves CRLF line endings and Windows-1252 ANSI encoding.
' =======================================================================

Option Explicit

Dim objFSO, strScriptDir, strRepoRoot, strBuildsIni
Dim bCheckOnly, strArg, i
Dim objStream, strIniText, arrLines, strLine
Dim dictSections, dictSection, currentSection
Dim bDrift

Set objFSO = CreateObject("Scripting.FileSystemObject")
strScriptDir = objFSO.GetParentFolderName(WScript.ScriptFullName)
strRepoRoot = objFSO.GetParentFolderName(strScriptDir)
strBuildsIni = objFSO.BuildPath(strRepoRoot, "static\builds.ini")

bCheckOnly = False
For i = 0 To WScript.Arguments.Count - 1
    strArg = LCase(WScript.Arguments(i))
    If strArg = "--check" Or strArg = "/check" Or strArg = "-check" Then
        bCheckOnly = True
    End If
Next

If Not objFSO.FileExists(strBuildsIni) Then
    WScript.Echo "ERROR: static/builds.ini not found at " & strBuildsIni
    WScript.Quit 1
End If

' -----------------------------------------------------------------------
' Parse static/builds.ini
' -----------------------------------------------------------------------
Set dictSections = CreateObject("Scripting.Dictionary")
strIniText = ReadTextFile1252(strBuildsIni)
arrLines = Split(Replace(strIniText, vbCrLf, vbLf), vbLf)
currentSection = ""

For Each strLine In arrLines
    strLine = Trim(strLine)
    If strLine <> "" And Left(strLine, 1) <> ";" Then
        If Left(strLine, 1) = "[" And Right(strLine, 1) = "]" Then
            currentSection = Mid(strLine, 2, Len(strLine) - 2)
            Set dictSection = CreateObject("Scripting.Dictionary")
            dictSection.CompareMode = 1 ' TextCompare
            Set dictSections(currentSection) = dictSection
        ElseIf currentSection <> "" Then
            Dim intEq
            intEq = InStr(strLine, "=")
            If intEq > 0 Then
                Dim strKey, strVal
                strKey = LCase(Trim(Left(strLine, intEq - 1)))
                strVal = Trim(Mid(strLine, intEq + 1))
                dictSections(currentSection)(strKey) = strVal
            End If
        End If
    End If
Next

' -----------------------------------------------------------------------
' Target 1: UpdateGenerator.au3
' -----------------------------------------------------------------------
Dim strSite1Path, strSite1Content, strSite1Block, strSite1New
strSite1Path = objFSO.BuildPath(strRepoRoot, "UpdateGenerator.au3")

' Extract Windows 11 builds
Dim arrWin11Builds(), arrWin11Names(), arrWin11Defs()
Dim secKey, nWin11
nWin11 = 0

' Sort builds: 22000, 22621, 22631, 26100, 26200
' First collect all win11 x64 sections
For Each secKey In dictSections.Keys
    Set dictSection = dictSections(secKey)
    If LCase(dictSection("os_family")) = "win11" And LCase(dictSection("arch")) = "x64" And LCase(dictSection("status")) <> "ineligible" Then
        ReDim Preserve arrWin11Builds(nWin11)
        ReDim Preserve arrWin11Names(nWin11)
        ReDim Preserve arrWin11Defs(nWin11)
        arrWin11Builds(nWin11) = CLng(dictSection("build"))
        arrWin11Names(nWin11) = dictSection("marketing_name")
        arrWin11Defs(nWin11) = dictSection("default_enabled")
        nWin11 = nWin11 + 1
    End If
Next

' Bubble sort ascending by build number
Dim j, tmpB, tmpN, tmpD
For i = 0 To nWin11 - 2
    For j = i + 1 To nWin11 - 1
        If arrWin11Builds(i) > arrWin11Builds(j) Then
            tmpB = arrWin11Builds(i): arrWin11Builds(i) = arrWin11Builds(j): arrWin11Builds(j) = tmpB
            tmpN = arrWin11Names(i): arrWin11Names(i) = arrWin11Names(j): arrWin11Names(j) = tmpN
            tmpD = arrWin11Defs(i): arrWin11Defs(i) = arrWin11Defs(j): arrWin11Defs(j) = tmpD
        End If
    Next
Next

Dim strW11Versions, strW11Dsp, strW11Defaults
strW11Versions = ""
strW11Dsp = ""
strW11Defaults = ""
For i = 0 To nWin11 - 1
    If i > 0 Then
        strW11Versions = strW11Versions & ","
        strW11Dsp = strW11Dsp & ","
        strW11Defaults = strW11Defaults & ","
    End If
    strW11Versions = strW11Versions & CStr(arrWin11Builds(i))
    strW11Dsp = strW11Dsp & arrWin11Names(i)
    strW11Defaults = strW11Defaults & arrWin11Defs(i)
Next

strSite1Block = "Dim Const $win11_vmax                   = " & nWin11 & vbCrLf & _
                "Dim Const $win11_versions               = """ & strW11Versions & """" & vbCrLf & _
                "Dim Const $win11_displayversions        = """ & strW11Dsp & """" & vbCrLf & _
                "Dim Const $win11_defaults               = """ & strW11Defaults & """"

' -----------------------------------------------------------------------
' Target 2: cmd/DownloadUpdates.cmd
' -----------------------------------------------------------------------
Dim strSite2Path, strSite2Content, strSite2Block, strSite2New
strSite2Path = objFSO.BuildPath(strRepoRoot, "cmd\DownloadUpdates.cmd")

Dim strW11SpaceList
strW11SpaceList = ""
For i = 0 To nWin11 - 1
    If i > 0 Then strW11SpaceList = strW11SpaceList & " "
    strW11SpaceList = strW11SpaceList & CStr(arrWin11Builds(i))
Next
strSite2Block = "  set TMP_BUILDS_ALL_WIN11=" & strW11SpaceList

' -----------------------------------------------------------------------
' Target 3: sh/download-updates-tasks/60-main-updates.bash
' -----------------------------------------------------------------------
Dim strSite3Path, strSite3Content, strSite3Block, strSite3New
strSite3Path = objFSO.BuildPath(strRepoRoot, "sh\download-updates-tasks\60-main-updates.bash")

' Win10 x86 servicing branches (sorted ascending): 10240 14393 17763 19041
' Win10 x64 servicing branches: 10240 14393 17763 19041 20348
' plus Win11 x64 builds: 22000 22621 22631 26100 26200
Dim dictX86Branches, dictX64Branches, branch
Set dictX86Branches = CreateObject("Scripting.Dictionary")
Set dictX64Branches = CreateObject("Scripting.Dictionary")

For Each secKey In dictSections.Keys
    Set dictSection = dictSections(secKey)
    If LCase(dictSection("os_family")) = "win10" Then
        branch = CLng(dictSection("servicing_branch"))
        If LCase(dictSection("arch")) = "x86" Then
            dictX86Branches(branch) = True
        ElseIf LCase(dictSection("arch")) = "x64" Then
            dictX64Branches(branch) = True
        End If
    End If
Next

Dim arrX86B(), nX86B, arrX64B(), nX64B
nX86B = 0
For Each branch In dictX86Branches.Keys
    ReDim Preserve arrX86B(nX86B)
    arrX86B(nX86B) = branch
    nX86B = nX86B + 1
Next
For i = 0 To nX86B - 2
    For j = i + 1 To nX86B - 1
        If arrX86B(i) > arrX86B(j) Then
            tmpB = arrX86B(i): arrX86B(i) = arrX86B(j): arrX86B(j) = tmpB
        End If
    Next
Next

nX64B = 0
For Each branch In dictX64Branches.Keys
    ReDim Preserve arrX64B(nX64B)
    arrX64B(nX64B) = branch
    nX64B = nX64B + 1
Next
' Add Win11 builds to x64
For i = 0 To nWin11 - 1
    ReDim Preserve arrX64B(nX64B)
    arrX64B(nX64B) = arrWin11Builds(i)
    nX64B = nX64B + 1
Next
For i = 0 To nX64B - 2
    For j = i + 1 To nX64B - 1
        If arrX64B(i) > arrX64B(j) Then
            tmpB = arrX64B(i): arrX64B(i) = arrX64B(j): arrX64B(j) = tmpB
        End If
    Next
Next

Dim strX86List, strX64List
strX86List = ""
For i = 0 To nX86B - 1
    If i > 0 Then strX86List = strX86List & " "
    strX86List = strX86List & CStr(arrX86B(i))
Next
strX64List = ""
For i = 0 To nX64B - 1
    If i > 0 Then strX64List = strX64List & " "
    strX64List = strX64List & CStr(arrX64B(i))
Next

strSite3Block = "w100_x86_all_versions=( " & strX86List & " )" & vbCrLf & _
                "w100_x64_all_versions=( " & strX64List & " )"

' -----------------------------------------------------------------------
' Target 4: sh/update-generator-tasks/10-show-selection-dialogs-with-dialog.bash
' -----------------------------------------------------------------------
Dim strSite4Path, strSite4Content, strSite4Block, strSite4New
strSite4Path = objFSO.BuildPath(strRepoRoot, "sh\update-generator-tasks\10-show-selection-dialogs-with-dialog.bash")

' Dialog entries in standard order:
' 10240 x86, x64
' 14393 x86, x64
' 17763 x86, x64
' 19041 x86, x64
' 20348 x64
' 22000 x64
' 22621 x64
' 22631 x64
' 26100 x64
' 26200 x64
Dim arrKeys, k, keyStr, secName
arrKeys = Array( _
    "10240_x86", "10240_x64", _
    "14393_x86", "14393_x64", _
    "17763_x86", "17763_x64", _
    "19041_x86", "19041_x64", _
    "20348_x64", _
    "22000_x64", _
    "22621_x64", _
    "22631_x64", _
    "26100_x64", _
    "26200_x64", _
    "26300_x64" _
)

Dim strKeysBlock, strLabelsBlock, strValuesBlock
strKeysBlock = "w100_keys=(" & vbCrLf & _
               "    ""10240_x86""  ""10240_x64""" & vbCrLf & _
               "    ""14393_x86""  ""14393_x64""" & vbCrLf & _
               "    ""17763_x86""  ""17763_x64""" & vbCrLf & _
               "    ""19041_x86""  ""19041_x64""" & vbCrLf & _
               "                 ""20348_x64""" & vbCrLf & _
               "                 ""22000_x64""" & vbCrLf & _
               "                 ""22621_x64""" & vbCrLf & _
               "                 ""22631_x64""" & vbCrLf & _
               "                 ""26100_x64""" & vbCrLf & _
               "                 ""26200_x64""" & vbCrLf & _
               "                 ""26300_x64""" & vbCrLf & _
               ")"

strLabelsBlock = "declare -A w100_labels=(" & vbCrLf
For Each keyStr In arrKeys
    ' Section name: w100-x86-10240 or w100-x64-10240
    Dim parts
    parts = Split(keyStr, "_")
    secName = "w100-" & parts(1) & "-" & parts(0)
    If dictSections.Exists(secName) Then
        strLabelsBlock = strLabelsBlock & "    [" & keyStr & "]=""" & dictSections(secName)("dialog_label") & """" & vbCrLf
    End If
Next
strLabelsBlock = strLabelsBlock & ")"

strValuesBlock = "declare -A w100_values=(" & vbCrLf & _
                 "    [10240_x86]=""" & dictSections("w100-x86-10240")("dialog_value") & """  [10240_x64]=""" & dictSections("w100-x64-10240")("dialog_value") & """" & vbCrLf & _
                 "    [14393_x86]=""" & dictSections("w100-x86-14393")("dialog_value") & """   [14393_x64]=""" & dictSections("w100-x64-14393")("dialog_value") & """" & vbCrLf & _
                 "    [17763_x86]=""" & dictSections("w100-x86-17763")("dialog_value") & """   [17763_x64]=""" & dictSections("w100-x64-17763")("dialog_value") & """" & vbCrLf & _
                 "    [19041_x86]=""" & dictSections("w100-x86-19041")("dialog_value") & """   [19041_x64]=""" & dictSections("w100-x64-19041")("dialog_value") & """" & vbCrLf & _
                 "                       [20348_x64]=""" & dictSections("w100-x64-20348")("dialog_value") & """" & vbCrLf & _
                 "                       [22000_x64]=""" & dictSections("w100-x64-22000")("dialog_value") & """" & vbCrLf & _
                 "                       [22621_x64]=""" & dictSections("w100-x64-22621")("dialog_value") & """" & vbCrLf & _
                 "                       [22631_x64]=""" & dictSections("w100-x64-22631")("dialog_value") & """" & vbCrLf & _
                 "                       [26100_x64]=""" & dictSections("w100-x64-26100")("dialog_value") & """" & vbCrLf & _
                 "                       [26200_x64]=""" & dictSections("w100-x64-26200")("dialog_value") & """" & vbCrLf & _
                 "                       [26300_x64]=""" & dictSections("w100-x64-26300")("dialog_value") & """" & vbCrLf & _
                 ")"

strSite4Block = strKeysBlock & vbCrLf & vbCrLf & strLabelsBlock & vbCrLf & vbCrLf & strValuesBlock

' -----------------------------------------------------------------------
' Target 5: client/UpdateInstaller.au3 & client/static/StaticUpdateIds-BuildUpgrades.txt
' -----------------------------------------------------------------------
Dim strSite5Path, strSite5Content, strSite5Block, strSite5New
strSite5Path = objFSO.BuildPath(strRepoRoot, "client\UpdateInstaller.au3")

Dim arrRegistrySections, sSec, bld, arch, osF, regBranch, st, ekbSrc, ekbKb, ekbPre, ekbRev, enf, cont
arrRegistrySections = Array( _
    "w100-x86-19041", "w100-x64-19041", _
    "w100-x86-19042", "w100-x64-19042", _
    "w100-x86-19044", "w100-x64-19044", _
    "w100-x86-19045", "w100-x64-19045", _
    "w100-x64-26100", "w100-x64-26200", _
    "w100-x64-26300", "w100-x64-28000" _
)

strSite5Block = "; Format: [build, arch, os_family, servicing_branch, status, ekb_source_build, ekb_kb, ekb_prereq_kb, ekb_min_revision, is_enforced]" & vbCrLf & _
                "Global Const $aBuildRegistry[12][10] = [ _" & vbCrLf

For i = 0 To UBound(arrRegistrySections)
    sSec = arrRegistrySections(i)
    Set dictSection = dictSections(sSec)
    bld = dictSection("build")
    arch = dictSection("arch")
    osF = dictSection("os_family")
    regBranch = dictSection("servicing_branch")
    st = dictSection("status")
    ekbSrc = dictSection("ekb_source_build")
    ekbKb = dictSection("ekb_kb")
    ekbPre = dictSection("ekb_prereq_kb")
    ekbRev = dictSection("ekb_min_revision")
    enf = 0
    If bld = "19042" Then enf = 1
    If i < UBound(arrRegistrySections) Then cont = ", _" Else cont = " _"

    Dim cSt, cSrc, cKb, cPre, cRev, pSt, pSrc, pKb, pPre, pRev
    cSt = Chr(34) & st & Chr(34) & ","
    cSrc = Chr(34) & ekbSrc & Chr(34) & ","
    cKb = Chr(34) & ekbKb & Chr(34) & ","
    cPre = Chr(34) & ekbPre & Chr(34) & ","
    cRev = Chr(34) & ekbRev & Chr(34) & ","

    If st = "ineligible" Then
        pSt = PadRight(cSt, 14)
        pSrc = PadRight(cSrc, 4)
    Else
        pSt = PadRight(cSt, 10)
        pSrc = PadRight(cSrc, 8)
    End If
    pKb = PadRight(cKb, 13)
    pPre = PadRight(cPre, 13)
    pRev = PadRight(cRev, 8)

    strSite5Block = strSite5Block & "  [" & Chr(34) & bld & Chr(34) & ", " & Chr(34) & arch & Chr(34) & ", " & Chr(34) & osF & Chr(34) & ", " & Chr(34) & regBranch & Chr(34) & ", " & _
                    pSt & " " & pSrc & " " & pKb & " " & pPre & " " & pRev & " " & enf & "]" & cont & vbCrLf
Next
strSite5Block = strSite5Block & "]"

' StaticUpdateIds-BuildUpgrades.txt
Dim strStaticUpgradesPath, strStaticUpgradesContent, strStaticUpgradesNew
strStaticUpgradesPath = objFSO.BuildPath(strRepoRoot, "client\static\StaticUpdateIds-BuildUpgrades.txt")

Dim sec19044, sec19045, sec26200
Set sec19044 = dictSections("w100-x64-19044")
Set sec19045 = dictSections("w100-x64-19045")
Set sec26200 = dictSections("w100-x64-26200")

strStaticUpgradesNew = "19041," & sec19044("ekb_min_revision") & "," & sec19044("ekb_prereq_kb") & ",19044," & sec19044("ekb_kb") & vbCrLf & _
                       "19042," & sec19044("ekb_min_revision") & "," & sec19044("ekb_prereq_kb") & ",19044," & sec19044("ekb_kb") & vbCrLf & _
                       "19042," & sec19045("ekb_min_revision") & "," & sec19045("ekb_prereq_kb") & ",19045," & sec19045("ekb_kb") & vbCrLf & _
                       "19043," & sec19045("ekb_min_revision") & "," & sec19045("ekb_prereq_kb") & ",19045," & sec19045("ekb_kb") & vbCrLf & _
                       "19044," & sec19045("ekb_min_revision") & "," & sec19045("ekb_prereq_kb") & ",19045," & sec19045("ekb_kb") & vbCrLf & _
                       "26100," & sec26200("ekb_min_revision") & "," & sec26200("ekb_prereq_kb") & ",26200," & sec26200("ekb_kb") & vbCrLf

For Each secKey In dictSections.Keys
    Set dictSection = dictSections(secKey)
    If LCase(dictSection("os_family")) = "win11" And LCase(dictSection("arch")) = "x64" Then
        If dictSection("build") <> "26200" And dictSection("ekb_kb") <> "" And dictSection("ekb_prereq_kb") <> "" And dictSection("ekb_min_revision") <> "" Then
            strStaticUpgradesNew = strStaticUpgradesNew & dictSection("ekb_source_build") & "," & dictSection("ekb_min_revision") & "," & dictSection("ekb_prereq_kb") & "," & dictSection("build") & "," & dictSection("ekb_kb") & vbCrLf
        End If
    End If
Next

' StaticUpdateIds-Checkpoints.txt
Dim strStaticCheckpointsPath, strStaticCheckpointsContent, strStaticCheckpointsNew
Dim dictSeenCheckpoints, chkKey, chkBranch, chkKb, chkRev
strStaticCheckpointsPath = objFSO.BuildPath(strRepoRoot, "client\static\StaticUpdateIds-Checkpoints.txt")
Set dictSeenCheckpoints = CreateObject("Scripting.Dictionary")
strStaticCheckpointsNew = ""

For Each secKey In dictSections.Keys
    Set dictSection = dictSections(secKey)
    If dictSection.Exists("checkpoint_kbs") And dictSection.Exists("checkpoint_min_revision") Then
        chkKb = dictSection("checkpoint_kbs")
        chkRev = dictSection("checkpoint_min_revision")
        If chkKb <> "" And chkRev <> "" Then
            chkBranch = dictSection("servicing_branch")
            chkKey = chkBranch & "," & chkKb
            If Not dictSeenCheckpoints.Exists(chkKey) Then
                dictSeenCheckpoints(chkKey) = True
                strStaticCheckpointsNew = strStaticCheckpointsNew & chkBranch & "," & chkKb & "," & chkBranch & "," & chkRev & vbCrLf
            End If
        End If
    End If
Next

' -----------------------------------------------------------------------
' Process Replacements
' -----------------------------------------------------------------------
bDrift = False

' 1. UpdateGenerator.au3
strSite1Content = ReadTextFile1252(strSite1Path)
strSite1New = ReplaceBetweenMarkers(strSite1Content, "; -- BEGIN GENERATED BUILDS WIN11 --", "; -- END GENERATED BUILDS WIN11 --", strSite1Block, "UpdateGenerator.au3")
If strSite1New <> strSite1Content Then
    bDrift = True
    If bCheckOnly Then WScript.Echo "ERROR: File UpdateGenerator.au3 is out of sync with static/builds.ini."
End If
If Not bCheckOnly Then Call WriteTextFile1252(strSite1Path, strSite1New)

' 2. cmd/DownloadUpdates.cmd
strSite2Content = ReadTextFile1252(strSite2Path)
strSite2New = ReplaceBetweenMarkers(strSite2Content, "REM -- BEGIN GENERATED BUILDS WIN11 --", "REM -- END GENERATED BUILDS WIN11 --", strSite2Block, "cmd/DownloadUpdates.cmd")
If strSite2New <> strSite2Content Then
    bDrift = True
    If bCheckOnly Then WScript.Echo "ERROR: File cmd/DownloadUpdates.cmd is out of sync with static/builds.ini."
End If
If Not bCheckOnly Then Call WriteTextFile1252(strSite2Path, strSite2New)

' 3. sh/download-updates-tasks/60-main-updates.bash
strSite3Content = ReadTextFile1252(strSite3Path)
strSite3New = ReplaceBetweenMarkers(strSite3Content, "# -- BEGIN GENERATED BUILDS --", "# -- END GENERATED BUILDS --", strSite3Block, "sh/download-updates-tasks/60-main-updates.bash")
If strSite3New <> strSite3Content Then
    bDrift = True
    If bCheckOnly Then WScript.Echo "ERROR: File sh/download-updates-tasks/60-main-updates.bash is out of sync with static/builds.ini."
End If
If Not bCheckOnly Then Call WriteTextFile1252(strSite3Path, strSite3New)

' 4. sh/update-generator-tasks/10-show-selection-dialogs-with-dialog.bash
strSite4Content = ReadTextFile1252(strSite4Path)
strSite4New = ReplaceBetweenMarkers(strSite4Content, "# -- BEGIN GENERATED BUILDS --", "# -- END GENERATED BUILDS --", strSite4Block, "sh/update-generator-tasks/10-show-selection-dialogs-with-dialog.bash")
If strSite4New <> strSite4Content Then
    bDrift = True
    If bCheckOnly Then WScript.Echo "ERROR: File sh/update-generator-tasks/10-show-selection-dialogs-with-dialog.bash is out of sync with static/builds.ini."
End If
If Not bCheckOnly Then Call WriteTextFile1252(strSite4Path, strSite4New)

' 5. client/UpdateInstaller.au3
strSite5Content = ReadTextFile1252(strSite5Path)
strSite5New = ReplaceBetweenMarkers(strSite5Content, "; -- BEGIN GENERATED BUILDS TABLE --", "; -- END GENERATED BUILDS TABLE --", strSite5Block, "client/UpdateInstaller.au3 (TABLE)")
If strSite5New <> strSite5Content Then
    bDrift = True
    If bCheckOnly Then WScript.Echo "ERROR: File client/UpdateInstaller.au3 is out of sync with static/builds.ini."
End If
If Not bCheckOnly Then Call WriteTextFile1252(strSite5Path, strSite5New)

' Synchronize client/static/StaticUpdateIds-BuildUpgrades.txt
strStaticUpgradesContent = ReadTextFile1252(strStaticUpgradesPath)
If strStaticUpgradesNew <> strStaticUpgradesContent Then
    bDrift = True
    If bCheckOnly Then WScript.Echo "ERROR: File client/static/StaticUpdateIds-BuildUpgrades.txt is out of sync with static/builds.ini."
End If
If Not bCheckOnly Then Call WriteTextFile1252(strStaticUpgradesPath, strStaticUpgradesNew)

' Synchronize client/static/StaticUpdateIds-Checkpoints.txt
If objFSO.FileExists(strStaticCheckpointsPath) Then
    strStaticCheckpointsContent = ReadTextFile1252(strStaticCheckpointsPath)
Else
    strStaticCheckpointsContent = ""
End If
If strStaticCheckpointsNew <> strStaticCheckpointsContent Then
    bDrift = True
    If bCheckOnly Then WScript.Echo "ERROR: File client/static/StaticUpdateIds-Checkpoints.txt is out of sync with static/builds.ini."
End If
If Not bCheckOnly Then Call WriteTextFile1252(strStaticCheckpointsPath, strStaticCheckpointsNew)

' -----------------------------------------------------------------------
' Exit status report
' -----------------------------------------------------------------------
If bCheckOnly Then
    If bDrift Then
        WScript.Quit 1
    Else
        WScript.Echo "All 5 build sites are in sync with static/builds.ini."
        WScript.Quit 0
    End If
Else
    WScript.Echo "Successfully updated 5 build sites from static/builds.ini."
    WScript.Quit 0
End If

' -----------------------------------------------------------------------
' Helper Functions
' -----------------------------------------------------------------------
Function PadRight(strText, intLen)
    Dim s
    s = strText
    While Len(s) < intLen
        s = s & " "
    Wend
    PadRight = s
End Function

Function ReadTextFile1252(strFilePath)
    Dim objStream
    Set objStream = CreateObject("ADODB.Stream")
    objStream.Type = 2 ' adTypeText
    objStream.Charset = "windows-1252"
    objStream.Open
    objStream.LoadFromFile strFilePath
    ReadTextFile1252 = objStream.ReadText(-1)
    objStream.Close
    Set objStream = Nothing
End Function

Sub WriteTextFile1252(strFilePath, strContent)
    Dim objStream
    Set objStream = CreateObject("ADODB.Stream")
    objStream.Type = 2 ' adTypeText
    objStream.Charset = "windows-1252"
    objStream.Open
    objStream.WriteText strContent
    objStream.SaveToFile strFilePath, 2 ' adSaveCreateOverWrite
    objStream.Close
    Set objStream = Nothing
End Sub

Function ReplaceBetweenMarkers(strContent, strStartMarker, strEndMarker, strNewBlock, strFileName)
    Dim intStart, intEnd, intStartLineEnd, intEndLineStart
    intStart = InStr(strContent, strStartMarker)
    intEnd = InStr(strContent, strEndMarker)
    If intStart = 0 And intEnd = 0 Then
        WScript.Echo "ERROR: Markers not found in " & strFileName & ": " & strStartMarker
        WScript.Quit 1
    End If
    If (intStart > 0 And intEnd = 0) Or (intStart = 0 And intEnd > 0) Then
        WScript.Echo "ERROR: Mismatched markers in " & strFileName & ": start=" & intStart & ", end=" & intEnd
        WScript.Quit 1
    End If
    If intEnd < intStart Then
        WScript.Echo "ERROR: End marker before start marker in " & strFileName
        WScript.Quit 1
    End If

    ' Detect newline format after start marker (CRLF or LF)
    Dim strNL, intNLLen, intPosCrLf, intPosLf
    intPosCrLf = InStr(intStart, strContent, vbCrLf)
    intPosLf = InStr(intStart, strContent, vbLf)
    If intPosLf = 0 And intPosCrLf = 0 Then
        WScript.Echo "ERROR: Missing newline after start marker in " & strFileName
        WScript.Quit 1
    End If
    If intPosCrLf > 0 And (intPosLf = 0 Or intPosCrLf = intPosLf - 1) Then
        strNL = vbCrLf
        intNLLen = 2
        intStartLineEnd = intPosCrLf
    Else
        strNL = vbLf
        intNLLen = 1
        intStartLineEnd = intPosLf
    End If
    intStartLineEnd = intStartLineEnd + intNLLen

    ' Find start of line for end marker
    intEndLineStart = InStrRev(Left(strContent, intEnd), strNL)
    If intEndLineStart = 0 Then
        intEndLineStart = 1
    Else
        intEndLineStart = intEndLineStart + intNLLen
    End If

    ' Prefix includes up to start marker line ending
    Dim strPrefix, strSuffix, strFinalBlock
    strPrefix = Left(strContent, intStartLineEnd - 1)
    strSuffix = Mid(strContent, intEndLineStart)
    If strNL = vbLf Then
        strFinalBlock = Replace(strNewBlock, vbCrLf, vbLf)
    Else
        strFinalBlock = strNewBlock
    End If

    ReplaceBetweenMarkers = strPrefix & strFinalBlock & strNL & strSuffix
End Function
