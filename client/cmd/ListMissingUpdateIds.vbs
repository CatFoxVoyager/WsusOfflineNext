' *** Author: T. Wittrock, Kiel ***

Option Explicit

Private Const strLogFileName  = "wsusofflineupdate.log"
Private Const strHideFileName = "HideList-seconly.txt"

Dim wshShell, objUpdateService, objUpdateSearcher, objSearchResult, objUpdate, objIDFile
Dim strTempFolder, strTextFileName, strArgument, strKBId
Dim objFSO, objTableDict, strOSName, strMissingFile

Private Sub LogInfo(objShell, strLine)
Dim objLogFile

  On Error Resume Next
  Set objLogFile = CreateObject("Scripting.FileSystemObject").OpenTextFile(objShell.ExpandEnvironmentStrings("%SystemRoot%") & "\" & strLogFileName, 8, True)
  objLogFile.WriteLine(Date & " " & Time & ",00 - Info: " & strLine)
  objLogFile.Close
End Sub

Private Function UpdateShouldBeHidden(objShell, strKBNumber)
Dim objExec

  On Error Resume Next
  If strKBNumber = "" Then
    UpdateShouldBeHidden = False
    Exit Function
  End If
  Set objExec = objShell.Exec(objShell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\find.exe /I """ & strKBNumber & """ ..\exclude\" & strHideFileName & " >nul 2>&1")
  Do While objExec.Status = 0
    WScript.Sleep 10
  Loop
  If objExec.ExitCode = 0 Then
    UpdateShouldBeHidden = True
    Exit Function
  End If
  If CreateObject("Scripting.FileSystemObject").FileExists("..\exclude\custom\" & strHideFileName) Then
    Set objExec = objShell.Exec(objShell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\find.exe /I """ & strKBNumber & """ ..\exclude\custom\" & strHideFileName & " >nul 2>&1")
    Do While objExec.Status = 0
      WScript.Sleep 10
    Loop
    If objExec.ExitCode = 0 Then
      UpdateShouldBeHidden = True
      Exit Function
    End If
  End If
  UpdateShouldBeHidden = False
End Function

' The generator deliberately excludes superseded updates from the medium download
' (exclude\ExcludeList-superseded*.txt). Some bundle identities list a helper file that IS on the
' medium alongside the excluded payload, so the installer kept reinstalling the helper on every
' pass while the identity could never become "installed" (measured: 101 passes in 12 h).
' An identity is therefore skipped when at least one of its UpdateTable files is not on the
' medium. /all mode and OS names without a table are never filtered.
Private Sub LoadUpdateTable()
Dim strTableFile, objTextStream, strLine, iPos, strID, strFile
  Set objTableDict = CreateObject("Scripting.Dictionary")
  objTableDict.CompareMode = 1
  strTableFile = "..\UpdateTable\UpdateTable-" & strOSName & "-glb.csv"
  If Not objFSO.FileExists(strTableFile) Then Exit Sub
  Set objTextStream = objFSO.OpenTextFile(strTableFile, 1, False, -2)
  Do Until objTextStream.AtEndOfStream
    strLine = objTextStream.ReadLine
    iPos = InStr(strLine, ",")
    If iPos > 1 Then
      strID = LCase(Left(strLine, iPos - 1))
      strFile = Mid(strLine, iPos + 1)
      If objTableDict.Exists(strID) Then
        objTableDict.Item(strID) = objTableDict.Item(strID) & "|" & strFile
      Else
        objTableDict.Add strID, strFile
      End If
    End If
  Loop
  objTextStream.Close
End Sub

Private Function UpdateIsIncomplete(strUpdateID, ByRef strMissingFile)
Dim arrFiles, i, strFile, strDir
  UpdateIsIncomplete = False
  strMissingFile = ""
  If strOSName = "" Then Exit Function
  If Not IsObject(objTableDict) Then LoadUpdateTable()
  If Not objTableDict.Exists(LCase(strUpdateID)) Then Exit Function
  arrFiles = Split(objTableDict.Item(LCase(strUpdateID)), "|")
  For i = 0 To UBound(arrFiles)
    strFile = Trim(arrFiles(i))
    If strFile <> "" Then
      If InStr(LCase(strFile), "-x64_") > 0 Then
        strDir = "..\" & strOSName & "-x64\glb\"
      Else
        strDir = "..\" & strOSName & "\glb\"
      End If
      If Not objFSO.FileExists(strDir & strFile) Then
        strMissingFile = strFile
        UpdateIsIncomplete = True
        Exit Function
      End If
    End If
  Next
End Function

Set wshShell = WScript.CreateObject("WScript.Shell")
Set objFSO = CreateObject("Scripting.FileSystemObject")
strTempFolder = wshShell.ExpandEnvironmentStrings("%TEMP%")
strTextFileName = strTempFolder & "\MissingUpdateIds.txt"
If WScript.Arguments.Count = 0 Then
  strArgument = ""
Else
  strArgument = WScript.Arguments(0)
End If
If WScript.Arguments.Count >= 2 Then
  strOSName = LCase(WScript.Arguments(1))
Else
  strOSName = ""
End If

On Error Resume Next
Set objUpdateService = CreateObject("Microsoft.Update.ServiceManager").AddScanPackageService("Offline Sync Service", strTempFolder & "\wsusscn2.cab")
' Report the FIRST failure: under On Error Resume Next the later statements (ServiceID on an
' unset service object, then Search) overwrite Err and used to hide the real HRESULT
' (e.g. 0x800B0109 = offline catalog signature not trusted) behind 0x5.
If Err.Number <> 0 Then
  LogInfo wshShell, "Error: offline scan failed in AddScanPackageService (0x" & Hex(Err.Number) & ": " & Err.Description & ")"
  WScript.Quit(2)
End If
Set objUpdateSearcher = CreateObject("Microsoft.Update.Session").CreateUpdateSearcher()
objUpdateSearcher.ServerSelection = 3 ' ssOthers
objUpdateSearcher.ServiceID = objUpdateService.ServiceID
If LCase(strArgument) = "/all" Then
  Set objSearchResult = objUpdateSearcher.Search("Type='Software'")
Else
  Set objSearchResult = objUpdateSearcher.Search("Type='Software' and IsInstalled=0 and IsHidden=0")
End If
If Err.Number <> 0 Then
  LogInfo wshShell, "Error: offline scan failed in Search (0x" & Hex(Err.Number) & ": " & Err.Description & ")"
  WScript.Quit(2)
End If

On Error Resume Next
Set objIDFile = CreateObject("Scripting.FileSystemObject").CreateTextFile(strTextFileName, True)
If objSearchResult.Updates.Count > 0 Then
  Set objIDFile = CreateObject("Scripting.FileSystemObject").CreateTextFile(strTextFileName, True)
  For Each objUpdate In objSearchResult.Updates
    If objUpdate.KBArticleIDs.Count > 0 Then
      strKBId = objUpdate.KBArticleIDs.Item(0)
    Else
      strKBId = ""
    End If
    If (LCase(strArgument) = "/seconly") And UpdateShouldBeHidden(wshShell, strKBId) Then
      If objUpdate.IsMandatory Then
        LogInfo wshShell, "Unable to hide mandatory update kb" & strKBId
      Else
        WScript.Echo "Hiding update kb" & strKBId & "..."
        objUpdate.IsHidden = True
        LogInfo wshShell, "Hid update kb" & strKBId
      End If
    Else
      If (LCase(strArgument) = "/all") And UpdateShouldBeHidden(wshShell, strKBId) Then
        WScript.Echo "Revealing update kb" & strKBId & "..."
        objUpdate.IsHidden = False
        LogInfo wshShell, "Revealed update kb" & strKBId
      End If
      If (strOSName <> "") And (LCase(strArgument) <> "/all") And UpdateIsIncomplete(objUpdate.Identity.UpdateID, strMissingFile) Then
        WScript.Echo "Skipping update kb" & strKBId & " (id: " & objUpdate.Identity.UpdateID & "): " & strMissingFile & " is not on the medium"
        LogInfo wshShell, "Warning: Skipped update kb" & strKBId & " (id: " & objUpdate.Identity.UpdateID & ") - " & strMissingFile & " is not on the medium"
      Else
        objIDFile.WriteLine(strKBId & "," & objUpdate.Identity.UpdateID)
      End If
    End If
  Next
End If
objIDFile.Close
WScript.Quit(0)
