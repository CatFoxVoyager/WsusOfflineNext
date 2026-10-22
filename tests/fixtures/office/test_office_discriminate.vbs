' *** WSUS Offline Update - Office 16.0 Discrimination Unit Tests ***
Option Explicit

Dim strOfficeProductName, strOfficeProductFamily, strOfficeEOLStatus, numOfficeIsC2R

Sub SimulateDetermineOffice16Product(strC2RIds, strMSOVersion)
  Dim arrayVer, numBuild

  strOfficeProductName = "Office 2016"
  strOfficeProductFamily = "Office 2016"
  strOfficeEOLStatus = "EOL (End of Life - Oct 2025)"
  numOfficeIsC2R = 0

  If InStr(1, strC2RIds, "2024", vbTextCompare) > 0 Then
    strOfficeProductName = "Office LTSC 2024"
    strOfficeProductFamily = "Office LTSC 2024"
    strOfficeEOLStatus = "Active (Supported until Oct 2029)"
    numOfficeIsC2R = 1
  ElseIf InStr(1, strC2RIds, "2021", vbTextCompare) > 0 Then
    strOfficeProductName = "Office LTSC 2021"
    strOfficeProductFamily = "Office LTSC 2021"
    strOfficeEOLStatus = "EOL (Supported until Oct 2026)"
    numOfficeIsC2R = 1
  ElseIf InStr(1, strC2RIds, "2019", vbTextCompare) > 0 Then
    strOfficeProductName = "Office 2019"
    strOfficeProductFamily = "Office 2019"
    strOfficeEOLStatus = "EOL (End of Life - Oct 2025)"
    numOfficeIsC2R = 1
  ElseIf (InStr(1, strC2RIds, "O365", vbTextCompare) > 0) Or (InStr(1, strC2RIds, "M365", vbTextCompare) > 0) Then
    strOfficeProductName = "Microsoft 365 Apps"
    strOfficeProductFamily = "Microsoft 365 Apps"
    strOfficeEOLStatus = "Channel Managed (C2R)"
    numOfficeIsC2R = 1
  Else
    arrayVer = Split(strMSOVersion, ".")
    If UBound(arrayVer) >= 2 Then
      If IsNumeric(arrayVer(2)) Then
        numBuild = CLng(arrayVer(2))
        If numBuild >= 17000 Then
          strOfficeProductName = "Office LTSC 2024"
          strOfficeProductFamily = "Office LTSC 2024"
          strOfficeEOLStatus = "Active (Supported until Oct 2029)"
          numOfficeIsC2R = 1
        ElseIf numBuild >= 14000 Then
          strOfficeProductName = "Office LTSC 2021"
          strOfficeProductFamily = "Office LTSC 2021"
          strOfficeEOLStatus = "EOL (Supported until Oct 2026)"
          numOfficeIsC2R = 1
        ElseIf numBuild >= 10000 Then
          strOfficeProductName = "Office 2019"
          strOfficeProductFamily = "Office 2019"
          strOfficeEOLStatus = "EOL (End of Life - Oct 2025)"
          numOfficeIsC2R = 1
        Else
          strOfficeProductName = "Office 2016 (MSI)"
          strOfficeProductFamily = "Office 2016"
          strOfficeEOLStatus = "EOL (End of Life - Oct 2025)"
          numOfficeIsC2R = 0
        End If
      Else
        strOfficeProductName = "Office 2016"
        strOfficeProductFamily = "Office 2016"
        strOfficeEOLStatus = "EOL (End of Life - Oct 2025)"
        numOfficeIsC2R = 0
      End If
    Else
      strOfficeProductName = "Office 2016"
      strOfficeProductFamily = "Office 2016"
      strOfficeEOLStatus = "EOL (End of Life - Oct 2025)"
      numOfficeIsC2R = 0
    End If
  End If
End Sub

' -------------------------------------------------------------
' State A: Office LTSC 2024
' -------------------------------------------------------------
SimulateDetermineOffice16Product "ProPlus2024Volume", "16.0.17932.20162"
If (strOfficeProductName <> "Office LTSC 2024") Or (InStr(strOfficeEOLStatus, "Active") = 0) Or (numOfficeIsC2R <> 1) Then
  WScript.Echo "FAIL: State A (Office LTSC 2024) expected 'Office LTSC 2024' / Active, got " & strOfficeProductName & " / " & strOfficeEOLStatus
  WScript.Quit 1
End If

' -------------------------------------------------------------
' State B: Office LTSC 2021
' -------------------------------------------------------------
SimulateDetermineOffice16Product "ProPlus2021Volume", "16.0.14332.20204"
If (strOfficeProductName <> "Office LTSC 2021") Or (InStr(strOfficeEOLStatus, "EOL") = 0) Or (numOfficeIsC2R <> 1) Then
  WScript.Echo "FAIL: State B (Office LTSC 2021) expected 'Office LTSC 2021' / EOL, got " & strOfficeProductName & " / " & strOfficeEOLStatus
  WScript.Quit 2
End If

' -------------------------------------------------------------
' State C: Office 2019
' -------------------------------------------------------------
SimulateDetermineOffice16Product "ProPlus2019Volume", "16.0.10336.20044"
If (strOfficeProductName <> "Office 2019") Or (InStr(strOfficeEOLStatus, "EOL") = 0) Or (numOfficeIsC2R <> 1) Then
  WScript.Echo "FAIL: State C (Office 2019) expected 'Office 2019' / EOL, got " & strOfficeProductName & " / " & strOfficeEOLStatus
  WScript.Quit 3
End If

' -------------------------------------------------------------
' State D: Office 2016 MSI (no C2R key, build 4266)
' -------------------------------------------------------------
SimulateDetermineOffice16Product "", "16.0.4266.1001"
If (strOfficeProductName <> "Office 2016 (MSI)") Or (InStr(strOfficeEOLStatus, "EOL") = 0) Or (numOfficeIsC2R <> 0) Then
  WScript.Echo "FAIL: State D (Office 2016 MSI) expected 'Office 2016 (MSI)' / EOL, got " & strOfficeProductName & " / " & strOfficeEOLStatus
  WScript.Quit 4
End If

' -------------------------------------------------------------
' State E: Fallback build threshold checks (no C2R key)
' -------------------------------------------------------------
' Fallback 2024 (build >= 17000)
SimulateDetermineOffice16Product "", "16.0.17932.21056"
If (strOfficeProductName <> "Office LTSC 2024") Or (InStr(strOfficeEOLStatus, "Active") = 0) Or (numOfficeIsC2R <> 1) Then
  WScript.Echo "FAIL: Fallback build 17932 expected 'Office LTSC 2024' / Active, got " & strOfficeProductName
  WScript.Quit 5
End If

' Fallback 2021 (build >= 14000)
SimulateDetermineOffice16Product "", "16.0.14332.20000"
If (strOfficeProductName <> "Office LTSC 2021") Or (InStr(strOfficeEOLStatus, "EOL") = 0) Or (numOfficeIsC2R <> 1) Then
  WScript.Echo "FAIL: Fallback build 14332 expected 'Office LTSC 2021' / EOL, got " & strOfficeProductName
  WScript.Quit 6
End If

' Fallback 2019 (build >= 10000)
SimulateDetermineOffice16Product "", "16.0.10336.10000"
If (strOfficeProductName <> "Office 2019") Or (InStr(strOfficeEOLStatus, "EOL") = 0) Or (numOfficeIsC2R <> 1) Then
  WScript.Echo "FAIL: Fallback build 10336 expected 'Office 2019' / EOL, got " & strOfficeProductName
  WScript.Quit 7
End If

' -------------------------------------------------------------
' State F: Microsoft 365 Apps
' -------------------------------------------------------------
SimulateDetermineOffice16Product "O365ProPlusRetail", "16.0.17932.20162"
If (strOfficeProductName <> "Microsoft 365 Apps") Or (InStr(strOfficeEOLStatus, "Channel Managed") = 0) Or (numOfficeIsC2R <> 1) Then
  WScript.Echo "FAIL: State F (M365 Apps) expected 'Microsoft 365 Apps' / Channel Managed, got " & strOfficeProductName
  WScript.Quit 8
End If

WScript.Echo "PASS: All Office discrimination states validated successfully."
WScript.Quit 0
