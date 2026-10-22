@echo off
rem *** Author: T. Wittrock, Kiel ***
rem ***   - Next Edition -   ***

verify other 2>nul
setlocal enableextensions enabledelayedexpansion
if errorlevel 1 goto NoExtensions

if /i "%~1"==":SortCheckpointsFirst" goto RunSortCheckpointsFirst

rem clear vars storing parameters
set SECONLY=
set EXC_STATICS=
set IGNORE_BL=

if "%UPDATE_LOGFILE%"=="" set UPDATE_LOGFILE=%SystemRoot%\wsusofflineupdate.log

set UPDATEID_DEBUG=0

if "%TEMP%"=="" goto NoTemp
pushd "%TEMP%"
if errorlevel 1 goto NoTempDir
popd
if "%OS_NAME%"=="" goto NoOSName
if "%OS_LANG%"=="" goto NoOSLang
if "%OS_ARCH%"=="" goto NoOSArch

:EvalParams
if "%1"=="" goto NoMoreParams
if /i "%1"=="/seconly" set SECONLY=1
if /i "%1"=="/excludestatics" set EXC_STATICS=1
if /i "%1"=="/ignoreblacklist" set IGNORE_BL=1
shift /1
goto EvalParams

:EvalStatics
if not exist %1 goto :eof
for %%i in (%1) do if %%~zi==0 goto :eof
if exist "%TEMP%\StaticUpdateIds.txt" del "%TEMP%\StaticUpdateIds.txt"
for /F "tokens=1* delims=kbKB,;" %%i in (%1) do (
  if exist "%TEMP%\MissingUpdateIds.txt" (
    %SystemRoot%\System32\find.exe /I "%%i" "%TEMP%\MissingUpdateIds.txt" >nul 2>&1
    if errorlevel 1 echo %%i>>"%TEMP%\StaticUpdateIds.txt"
  ) else (
    echo %%i>>"%TEMP%\StaticUpdateIds.txt"
  )
)
if not exist "%TEMP%\StaticUpdateIds.txt" goto :eof
if exist "%TEMP%\InstalledUpdateIds.txt" (
  %SystemRoot%\System32\findstr.exe /L /I /V /G:"%TEMP%\InstalledUpdateIds.txt" "%TEMP%\StaticUpdateIds.txt" >>"%TEMP%\AllStaticUpdateIds.txt"
) else (
  type "%TEMP%\StaticUpdateIds.txt" >>"%TEMP%\AllStaticUpdateIds.txt"
)
del "%TEMP%\StaticUpdateIds.txt"
goto :eof

:NoMoreParams
rem *** Add statically defined update ids ***
if "%EXC_STATICS%"=="1" goto ListFiles
if exist "%TEMP%\AllStaticUpdateIds.txt" del "%TEMP%\AllStaticUpdateIds.txt"
if "%OS_NAME%"=="w100" (
  call :EvalStatics ..\static\custom\StaticUpdateIds-%OS_NAME%-%OS_VER_BUILD%-%OS_ARCH%.txt
  call :EvalStatics ..\static\StaticUpdateIds-%OS_NAME%-%OS_VER_BUILD%-%OS_ARCH%.txt
  call :EvalStatics ..\static\custom\StaticUpdateIds-%OS_NAME%-%OS_VER_BUILD%.txt
  call :EvalStatics ..\static\StaticUpdateIds-%OS_NAME%-%OS_VER_BUILD%.txt
  if exist ..\static\StaticUpdateIds-%OS_NAME%-%OS_VER_BUILD%-dotnet4-%DOTNET4_RELEASE%.txt (
    call :EvalStatics ..\static\custom\StaticUpdateIds-%OS_NAME%-%OS_VER_BUILD%-dotnet4-%DOTNET4_RELEASE%.txt
    call :EvalStatics ..\static\StaticUpdateIds-%OS_NAME%-%OS_VER_BUILD%-dotnet4-%DOTNET4_RELEASE%.txt
    if "%DOTNET35_VER_MAJOR%%DOTNET35_VER_MINOR%"=="%DOTNET35_VER_TARGET_MAJOR%%DOTNET35_VER_TARGET_MINOR%" (
      call :EvalStatics ..\static\custom\StaticUpdateIds-%OS_NAME%-%OS_VER_BUILD%-dotnet.txt
      call :EvalStatics ..\static\StaticUpdateIds-%OS_NAME%-%OS_VER_BUILD%-dotnet.txt
    )
  ) else (
    call :EvalStatics ..\static\custom\StaticUpdateIds-%OS_NAME%-%OS_VER_BUILD%-dotnet.txt
    call :EvalStatics ..\static\StaticUpdateIds-%OS_NAME%-%OS_VER_BUILD%-dotnet.txt
  )
) else (
  if "%SECONLY%"=="1" (
    call :EvalStatics ..\static\custom\StaticUpdateIds-%OS_NAME%-%OS_ARCH%-seconly.txt
    call :EvalStatics ..\static\StaticUpdateIds-%OS_NAME%-%OS_ARCH%-seconly.txt
    call :EvalStatics ..\static\custom\StaticUpdateIds-%OS_NAME%-seconly.txt
    call :EvalStatics ..\static\StaticUpdateIds-%OS_NAME%-seconly.txt
    call :EvalStatics ..\static\custom\StaticUpdateIds-%OS_NAME%-dotnet%DOTNET35_VER_MAJOR%%DOTNET35_VER_MINOR%-seconly.txt
    call :EvalStatics ..\static\StaticUpdateIds-%OS_NAME%-dotnet%DOTNET35_VER_MAJOR%%DOTNET35_VER_MINOR%-seconly.txt
    call :EvalStatics ..\static\custom\StaticUpdateIds-%OS_NAME%-dotnet4-%DOTNET4_RELEASE%-seconly.txt
    call :EvalStatics ..\static\StaticUpdateIds-%OS_NAME%-dotnet4-%DOTNET4_RELEASE%-seconly.txt
  ) else (
    call :EvalStatics ..\static\custom\StaticUpdateIds-%OS_NAME%-%OS_ARCH%.txt
    call :EvalStatics ..\static\StaticUpdateIds-%OS_NAME%-%OS_ARCH%.txt
    call :EvalStatics ..\static\custom\StaticUpdateIds-%OS_NAME%.txt
    call :EvalStatics ..\static\StaticUpdateIds-%OS_NAME%.txt
    call :EvalStatics ..\static\custom\StaticUpdateIds-%OS_NAME%-dotnet%DOTNET35_VER_MAJOR%%DOTNET35_VER_MINOR%.txt
    call :EvalStatics ..\static\StaticUpdateIds-%OS_NAME%-dotnet%DOTNET35_VER_MAJOR%%DOTNET35_VER_MINOR%.txt
    call :EvalStatics ..\static\custom\StaticUpdateIds-%OS_NAME%-dotnet4-%DOTNET4_RELEASE%.txt
    call :EvalStatics ..\static\StaticUpdateIds-%OS_NAME%-dotnet4-%DOTNET4_RELEASE%.txt
  )
)
if "%O2K16_VER_MAJOR%" NEQ "" (
  call :EvalStatics ..\static\custom\StaticUpdateIds-o2k16.txt
  call :EvalStatics ..\static\StaticUpdateIds-o2k16.txt
)
for %%i in ("%TEMP%\AllStaticUpdateIds.txt") do if %%~zi==0 del %%i
if exist "%TEMP%\AllStaticUpdateIds.txt" (
  if exist "%TEMP%\MissingUpdateIds.txt" (
    if exist "%TEMP%\MissingDynamicIds.txt" del "%TEMP%\MissingDynamicIds.txt"
    ren "%TEMP%\MissingUpdateIds.txt" MissingDynamicIds.txt
    type "%TEMP%\AllStaticUpdateIds.txt" >>"%TEMP%\MissingUpdateIds.txt"
    type "%TEMP%\MissingDynamicIds.txt" >>"%TEMP%\MissingUpdateIds.txt"
    del "%TEMP%\MissingDynamicIds.txt"
    del "%TEMP%\AllStaticUpdateIds.txt"
  ) else (
    ren "%TEMP%\AllStaticUpdateIds.txt" MissingUpdateIds.txt
  )
)

:ListFiles
rem *** List update files ***
if exist "%TEMP%\InstalledUpdateIds.txt" del "%TEMP%\InstalledUpdateIds.txt"
if exist "%TEMP%\UpdatesToInstall.txt" del "%TEMP%\UpdatesToInstall.txt"
for %%i in ("%TEMP%\MissingUpdateIds.txt") do if %%~zi==0 del %%i
if not exist "%TEMP%\MissingUpdateIds.txt" goto FinalizeUpdates
echo.>"%TEMP%\ExcludeList.txt"
if "%IGNORE_BL%"=="1" goto IgnoreBL
if exist ..\exclude\ExcludeList.txt (
  type ..\exclude\ExcludeList.txt >"%TEMP%\ExcludeList.txt"
)
if exist ..\exclude\custom\ExcludeList.txt (
  type ..\exclude\custom\ExcludeList.txt >>"%TEMP%\ExcludeList.txt"
)
:IgnoreBL
if "%OS_ARCH%"=="x64" (set OS_SEARCH_DIR=%OS_NAME%-%OS_ARCH%) else (set OS_SEARCH_DIR=%OS_NAME%)
for /F "usebackq tokens=1,2 delims=," %%i in ("%TEMP%\MissingUpdateIds.txt") do (
  if exist "%TEMP%\Update.txt" del "%TEMP%\Update.txt"
  %SystemRoot%\System32\find.exe /I "%%i" "%TEMP%\ExcludeList.txt" >nul 2>&1
  if errorlevel 1 (
    if not "%%j"=="" (
      rem dynamisch ermittelte Updates als CAB
      for %%k in (%OS_LANG% glb) do (
        if exist ..\UpdateTable\UpdateTable-%OS_NAME%-%%k.csv (
          for /F "tokens=1,2 delims=," %%l in (..\UpdateTable\UpdateTable-%OS_NAME%-%%k.csv) do (
            if "%%l"=="%%j" (
              if "%OS_NAME%"=="w100" (
                if exist "..\%OS_SEARCH_DIR%\%%k\%OS_VER_BUILD_INTERNAL%" (
                  call ListUpdateFile.cmd %%m ..\%OS_SEARCH_DIR%\%%k\%OS_VER_BUILD_INTERNAL% /searchleftmost /append
                  if errorlevel 1 (
                    call ListUpdateFile.cmd %%m ..\%OS_SEARCH_DIR%\%%k /searchleftmost /append
                    if errorlevel 1 (
                      rem echo Warning: Update file %%m ^(id: %%j^) not found.
                      echo %DATE% %TIME% - Warning: Update file %%m ^(id: %%j^) not found>>%UPDATE_LOGFILE%
                    )
                  )
                ) else (
                  call ListUpdateFile.cmd %%m ..\%OS_SEARCH_DIR%\%%k /searchleftmost /append
                  if errorlevel 1 (
                    rem echo Warning: Update file %%m ^(id: %%j^) not found.
                    echo %DATE% %TIME% - Warning: Update file %%m ^(id: %%j^) not found>>%UPDATE_LOGFILE%
                  )
                )
              ) else (
                call ListUpdateFile.cmd %%m ..\%OS_SEARCH_DIR%\%%k /searchleftmost /append
                if errorlevel 1 (
                  rem echo Warning: Update file %%m ^(id: %%j^) not found.
                  echo %DATE% %TIME% - Warning: Update file %%m ^(id: %%j^) not found>>%UPDATE_LOGFILE%
                )
              )
            )
          )
        )
      )
      if not "%O2K16_VER_MAJOR%"=="" (
        for %%k in (%O2K16_LANG% glb) do (
          if exist ..\UpdateTable\UpdateTable-o2k16-%%k.csv (
            for /F "tokens=1,2 delims=," %%l in (..\UpdateTable\UpdateTable-o2k16-%%k.csv) do (
              if "%%l"=="%%j" (
                call ListUpdateFile.cmd %%m ..\o2k16\%%k /searchleftmost /append
                if errorlevel 1 (
                  rem echo Warning: Update file %%m ^(id: %%j^) not found.
                  echo %DATE% %TIME% - Warning: Update file %%m ^(id: %%j^) not found>>%UPDATE_LOGFILE%
                )
              )
            )
          )
        )
      )
    )
    rem statisch definierte Windows-Updates als CAB/MSU/...
    if not exist "%TEMP%\Update.txt" (
      for %%l in (%OS_LANG% glb) do (
        if "%OS_NAME%"=="w100" (
          if exist "..\%OS_SEARCH_DIR%\%%l\%OS_VER_BUILD_INTERNAL%" (
            if %IE_VER_MAJOR%%IE_VER_MINOR%0 GEQ 9100 (
              call ListUpdateFile.cmd ie%IE_VER_MINOR%-*%%i ..\%OS_SEARCH_DIR%\%%l\%OS_VER_BUILD_INTERNAL%
            ) else (
              call ListUpdateFile.cmd ie%IE_VER_MAJOR%-*%%i ..\%OS_SEARCH_DIR%\%%l\%OS_VER_BUILD_INTERNAL%
            )
            call ListUpdateFile.cmd windows*%%i ..\%OS_SEARCH_DIR%\%%l\%OS_VER_BUILD_INTERNAL% /searchleftmost
            call ListUpdateFile.cmd %%i ..\%OS_SEARCH_DIR%\%%l\%OS_VER_BUILD_INTERNAL%
          )
        )
        if %IE_VER_MAJOR%%IE_VER_MINOR%0 GEQ 9100 (
          call ListUpdateFile.cmd ie%IE_VER_MINOR%-*%%i ..\%OS_SEARCH_DIR%\%%l
        ) else (
          call ListUpdateFile.cmd ie%IE_VER_MAJOR%-*%%i ..\%OS_SEARCH_DIR%\%%l
        )
        call ListUpdateFile.cmd windows*%%i ..\%OS_SEARCH_DIR%\%%l /searchleftmost
        call ListUpdateFile.cmd %%i ..\%OS_SEARCH_DIR%\%%l
      )
    )
    rem statisch definierte Office-Updates als EXE
    if not exist "%TEMP%\Update.txt" (
      if not "%O2K16_VER_MAJOR%"=="" (
        for %%k in (%O2K16_LANG% glb) do (
          call ListUpdateFile.cmd %%i*%O2K16_ARCH% ..\o2k16\%%k
          call ListUpdateFile.cmd %%i ..\o2k16\%%k
        )
      )
    )
    if exist "%TEMP%\Update.txt" (
      if "%UPDATEID_DEBUG%"=="1" (
        if not exist "%SystemRoot%\wsusofflineupdate_Debug" (mkdir "%SystemRoot%\wsusofflineupdate_Debug" >nul)
        if "%%j"=="" (
          move /y "%TEMP%\Update.txt" "%SystemRoot%\wsusofflineupdate_Debug\ListUpdatesToInstall_%%i.txt" >nul
        ) else (
          move /y "%TEMP%\Update.txt" "%SystemRoot%\wsusofflineupdate_Debug\ListUpdatesToInstall_%%i_%%j.txt" >nul
        )
	  ) else (
        del "%TEMP%\Update.txt"
	  )
    ) else (
      set TMP_UPDATE_NAME=%%i
      if not "!TMP_UPDATE_NAME:~0,2!"=="kb" (set TMP_UPDATE_NAME=kb!TMP_UPDATE_NAME!)
      if "%%j"=="" (
        echo Warning: Update !TMP_UPDATE_NAME! not found.
        echo %DATE% %TIME% - Warning: Update !TMP_UPDATE_NAME! not found>>%UPDATE_LOGFILE%
      ) else (
        echo Warning: Update !TMP_UPDATE_NAME! ^(id: %%j^) not found.
        echo %DATE% %TIME% - Warning: Update !TMP_UPDATE_NAME! ^(id: %%j^) not found>>%UPDATE_LOGFILE%
      )
      set TMP_UPDATE_NAME=
    )
  ) else (
    for /F "tokens=1* delims=,;" %%k in ('%SystemRoot%\System32\findstr.exe /I "%%i" "%TEMP%\ExcludeList.txt"') do (
      if "%%l"=="" (
        echo Info: Skipping update %%k due to matching black list entry.
        echo %DATE% %TIME% - Info: Skipped update %%k due to matching black list entry>>%UPDATE_LOGFILE%
      ) else (
        echo Info: Skipping update %%k ^(%%l^) due to matching black list entry.
        echo %DATE% %TIME% - Info: Skipped update %%k ^(%%l^) due to matching black list entry>>%UPDATE_LOGFILE%
      )
    )
  )
)
:FinalizeUpdates
if exist "%TEMP%\MissingUpdateIds.txt" del "%TEMP%\MissingUpdateIds.txt"
if exist "%TEMP%\ExcludeList.txt" del "%TEMP%\ExcludeList.txt"
call :AddOfficeC2RUpdates %*
if exist "%TEMP%\UpdatesToInstall.txt" call :SortCheckpointsFirst
goto EoF

:SortCheckpointsFirst
if not exist "%TEMP%\UpdatesToInstall.txt" goto :eof
if not exist ..\static\StaticUpdateIds-Checkpoints.txt if not exist %~dp0..\static\StaticUpdateIds-Checkpoints.txt goto :eof
set CHKPT_DEF_FILE=..\static\StaticUpdateIds-Checkpoints.txt
if not exist "%CHKPT_DEF_FILE%" set CHKPT_DEF_FILE=%~dp0..\static\StaticUpdateIds-Checkpoints.txt

for %%i in ("%TEMP%\UpdatesToInstall.txt") do if %%~zi==0 goto :eof

if exist "%TEMP%\wou_chkpt_patterns.txt" del "%TEMP%\wou_chkpt_patterns.txt"
for /F "usebackq tokens=2 delims=," %%c in ("%CHKPT_DEF_FILE%") do (
  if not "%%c"=="" >>"%TEMP%\wou_chkpt_patterns.txt" echo %%c
)
if not exist "%TEMP%\wou_chkpt_patterns.txt" goto :eof
for %%i in ("%TEMP%\wou_chkpt_patterns.txt") do if %%~zi==0 del "%TEMP%\wou_chkpt_patterns.txt"
if not exist "%TEMP%\wou_chkpt_patterns.txt" goto :eof

if exist "%TEMP%\wou_chkpts.txt" del "%TEMP%\wou_chkpts.txt"
if exist "%TEMP%\wou_nonchkpts.txt" del "%TEMP%\wou_nonchkpts.txt"

%SystemRoot%\System32\findstr.exe /I /G:"%TEMP%\wou_chkpt_patterns.txt" "%TEMP%\UpdatesToInstall.txt" >"%TEMP%\wou_chkpts.txt" 2>nul
%SystemRoot%\System32\findstr.exe /V /I /G:"%TEMP%\wou_chkpt_patterns.txt" "%TEMP%\UpdatesToInstall.txt" >"%TEMP%\wou_nonchkpts.txt" 2>nul
del "%TEMP%\wou_chkpt_patterns.txt"

set CHKPT_FOUND=
if exist "%TEMP%\wou_chkpts.txt" (
  for %%i in ("%TEMP%\wou_chkpts.txt") do if %%~zi GTR 0 set CHKPT_FOUND=1
)

if defined CHKPT_FOUND (
  type "%TEMP%\wou_chkpts.txt" >"%TEMP%\UpdatesToInstall.txt"
  if exist "%TEMP%\wou_nonchkpts.txt" (
    type "%TEMP%\wou_nonchkpts.txt" >>"%TEMP%\UpdatesToInstall.txt"
    del "%TEMP%\wou_nonchkpts.txt"
  )
  del "%TEMP%\wou_chkpts.txt"
  echo %DATE% %TIME% - Info: Prioritized Checkpoint Cumulative Update packages to head of installation queue>>%UPDATE_LOGFILE%
) else (
  if exist "%TEMP%\wou_chkpts.txt" del "%TEMP%\wou_chkpts.txt"
  if exist "%TEMP%\wou_nonchkpts.txt" del "%TEMP%\wou_nonchkpts.txt"
)
goto :eof

:RunSortCheckpointsFirst
call :SortCheckpointsFirst
goto EoF

:AddOfficeC2RUpdates
if "%O2K16_IS_C2R%" NEQ "1" goto :eof
if "%1"=="/excludestatics" goto :eof
if exist %SystemRoot%\Temp\wou_c2r_tried.txt goto :eof

rem Map product family to C2R folder token
set "C2R_PROD="
if /i "%O2K16_PRODUCT_FAMILY%"=="Office LTSC 2024" set "C2R_PROD=o2k24"
if /i "%O2K16_PRODUCT_FAMILY%"=="Office LTSC 2021" set "C2R_PROD=o2k21"
if /i "%O2K16_PRODUCT_FAMILY%"=="Office 2019" set "C2R_PROD=o2k19"
if "%C2R_PROD%"=="" (
  if not "%O2K16_PRODUCT_NAME:2024=%"=="%O2K16_PRODUCT_NAME%" set "C2R_PROD=o2k24"
  if not "%O2K16_PRODUCT_NAME:2021=%"=="%O2K16_PRODUCT_NAME%" set "C2R_PROD=o2k21"
  if not "%O2K16_PRODUCT_NAME:2019=%"=="%O2K16_PRODUCT_NAME%" set "C2R_PROD=o2k19"
)
if "%C2R_PROD%"=="" goto :eof

rem Determine architecture token
set "C2R_ARCH=%O2K16_ARCH%"
if "%C2R_ARCH%"=="" set "C2R_ARCH=x64"

set "C2R_MEDIA_DIR="
if exist "..\office\c2r\%C2R_PROD%\%C2R_ARCH%" (
  set "C2R_MEDIA_DIR=..\office\c2r\%C2R_PROD%\%C2R_ARCH%"
) else if exist "..\office\c2r\%C2R_PROD%" (
  set "C2R_MEDIA_DIR=..\office\c2r\%C2R_PROD%"
) else if exist "%~dp0..\office\c2r\%C2R_PROD%\%C2R_ARCH%" (
  set "C2R_MEDIA_DIR=%~dp0..\office\c2r\%C2R_PROD%\%C2R_ARCH%"
) else if exist "%~dp0..\office\c2r\%C2R_PROD%" (
  set "C2R_MEDIA_DIR=%~dp0..\office\c2r\%C2R_PROD%"
)
if "%C2R_MEDIA_DIR%"=="" goto :eof

rem Get absolute path for SourcePath
pushd "%C2R_MEDIA_DIR%"
set "C2R_ABS_PATH=%CD%"
popd

rem Determine Channel and Edition
set "C2R_CHANNEL=%O2K16_C2R_CHANNEL%"
if "%C2R_CHANNEL%"=="" (
  if "%C2R_PROD%"=="o2k24" set "C2R_CHANNEL=PerpetualVL2024"
  if "%C2R_PROD%"=="o2k21" set "C2R_CHANNEL=PerpetualVL2021"
  if "%C2R_PROD%"=="o2k19" set "C2R_CHANNEL=PerpetualVL2019"
)
set "C2R_EDITION=64"
if /i "%C2R_ARCH%"=="x86" set "C2R_EDITION=32"

set "C2R_PID=%O2K16_PRODUCT_ID%"
if "%C2R_PID%"=="" (
  if "%C2R_PROD%"=="o2k24" set "C2R_PID=ProPlus2024Volume"
  if "%C2R_PROD%"=="o2k21" set "C2R_PID=ProPlus2021Volume"
  if "%C2R_PROD%"=="o2k19" set "C2R_PID=ProPlus2019Volume"
)

rem Generate servicing XML configuration
set "C2R_MANIFEST=%TEMP%\wou_c2r_update.xml"
(
  echo ^<Configuration^>
  echo   ^<Add SourcePath="%C2R_ABS_PATH%" OfficeClientEdition="%C2R_EDITION%" Channel="%C2R_CHANNEL%"^>
  echo     ^<Product ID="%C2R_PID%"^>
  echo       ^<Language ID="MatchOS" /^>
  echo     ^</Product^>
  echo   ^</Add^>
  echo   ^<Updates Enabled="TRUE" Channel="%C2R_CHANNEL%" /^>
  echo   ^<Display Level="None" AcceptEULA="TRUE" /^>
  echo   ^<Property Name="FORCEAPPSHUTDOWN" Value="TRUE" /^>
  echo ^</Configuration^>
)>"%C2R_MANIFEST%"

if exist "%C2R_MANIFEST%" (
  echo %C2R_MANIFEST%>>"%TEMP%\UpdatesToInstall.txt"
  echo %DATE% %TIME% - Info: Added Office Click-to-Run update manifest for %O2K16_PRODUCT_NAME% ^(%C2R_ARCH%^)>>%UPDATE_LOGFILE%
)
goto :eof

:NoExtensions
echo ERROR: No command extensions available.
goto Error

:NoTemp
echo ERROR: Environment variable TEMP not set.
echo %DATE% %TIME% - Error: Environment variable TEMP not set>>%UPDATE_LOGFILE%
goto Error

:NoTempDir
echo ERROR: Directory "%TEMP%" not found.
echo %DATE% %TIME% - Error: Directory "%TEMP%" not found>>%UPDATE_LOGFILE%
goto Error

:NoOSName
echo ERROR: Environment variable OS_NAME not set.
echo %DATE% %TIME% - Error: Environment variable OS_NAME not set>>%UPDATE_LOGFILE%
goto Error

:NoOSLang
echo ERROR: Environment variable OS_LANG not set.
echo %DATE% %TIME% - Error: Environment variable OS_LANG not set>>%UPDATE_LOGFILE%
goto Error

:NoOSArch
echo ERROR: Environment variable OS_ARCH not set.
echo %DATE% %TIME% - Error: Environment variable OS_ARCH not set>>%UPDATE_LOGFILE%
goto Error

:Error
endlocal
exit /b 1

:EoF
endlocal
