' *** Author: aker@wsusoffline ***

Option Explicit

Dim strVersion1, strVersion2, arrayVersion1, arrayVersion2, intMaxIndex
Dim i
Dim intPlusPos

If WScript.Arguments.Count < 2 Then
  WScript.Echo("ERROR: Missing argument.")
  WScript.Echo("Usage: " & WScript.ScriptName & " <version 1> <version 2>")
  WScript.Echo("       errorlevel 0: versions are equal")
  WScript.Echo("       errorlevel 1: parser error")
  WScript.Echo("       errorlevel 2: version 1 > version 2")
  WScript.Echo("       errorlevel 3: version 1 < version 2")
  WScript.Quit(1)
End If

strVersion1 = WScript.Arguments(0)
strVersion2 = WScript.Arguments(1)

If strVersion1 = "" Then
  WScript.Echo("ERROR: Invalid first argument.")
  WScript.Echo("Usage: " & WScript.ScriptName & " <version 1> <version 2>")
  WScript.Quit(1)
End If
If strVersion2 = "" Then
  WScript.Echo("ERROR: Invalid second argument.")
  WScript.Echo("Usage: " & WScript.ScriptName & " <version 1> <version 2>")
  WScript.Quit(1)
End If

' Build metadata (the "+..." suffix of a SemVer version) never affects
' precedence (Semantic Versioning 2.0.0, section 10), so it is stripped
' before the numeric comparison below: "5.0.0+2026.11" must compare
' exactly like "5.0.0". The exit protocol stays unchanged:
' errorlevel 0 equal / 1 parser error / 2 v1 > v2 / 3 v1 < v2.
intPlusPos = InStr(strVersion1, "+")
If intPlusPos > 0 Then
  strVersion1 = Left(strVersion1, intPlusPos - 1)
  If strVersion1 = "" Then
    WScript.Echo("ERROR: Invalid first argument.")
    WScript.Echo("Usage: " & WScript.ScriptName & " <version 1> <version 2>")
    WScript.Quit(1)
  End If
End If
intPlusPos = InStr(strVersion2, "+")
If intPlusPos > 0 Then
  strVersion2 = Left(strVersion2, intPlusPos - 1)
  If strVersion2 = "" Then
    WScript.Echo("ERROR: Invalid second argument.")
    WScript.Echo("Usage: " & WScript.ScriptName & " <version 1> <version 2>")
    WScript.Quit(1)
  End If
End If

arrayVersion1 = Split(strVersion1, ".")
arrayVersion2 = Split(strVersion2, ".")

For i = 0 To UBound(arrayVersion1)
  If IsNumeric(arrayVersion1(i)) = False Then
    WScript.Echo("ERROR: Invalid first argument.")
    WScript.Echo("Usage: " & WScript.ScriptName & " <version 1> <version 2>")
    WScript.Quit(1)
  End If
Next

For i = 0 To UBound(arrayVersion2)
  If IsNumeric(arrayVersion2(i)) = False Then
    WScript.Echo("ERROR: Invalid second argument.")
    WScript.Echo("Usage: " & WScript.ScriptName & " <version 1> <version 2>")
    WScript.Quit(1)
  End If
Next

If UBound(arrayVersion2) > UBound(arrayVersion1) Then
  intMaxIndex = UBound(arrayVersion1)
Else
  intMaxIndex = UBound(arrayVersion2)
End If

For i = 0 To intMaxIndex
  If CInt(arrayVersion1(i)) > CInt(arrayVersion2(i)) Then
    WScript.Quit(2)
  ElseIf CInt(arrayVersion1(i)) < CInt(arrayVersion2(i)) Then
    WScript.Quit(3)
  End If
Next


If UBound(arrayVersion1) > intMaxIndex Then
  For i = intMaxIndex To UBound(arrayVersion1)
    If CInt(arrayVersion1(i)) > 0 Then
      WScript.Quit(2)
    End If
  Next
ElseIf UBound(arrayVersion2) > intMaxIndex Then
  For i = intMaxIndex To UBound(arrayVersion2)
    If CInt(arrayVersion2(i)) > 0 Then
      WScript.Quit(3)
    End If
  Next
End If

WScript.Quit(0)
