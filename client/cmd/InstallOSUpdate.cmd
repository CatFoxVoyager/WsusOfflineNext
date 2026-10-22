@echo off
rem *** Author: T. Wittrock, Kiel ***
rem ***   - Next Edition -   ***

verify other 2>nul
setlocal enableextensions enabledelayedexpansion
if errorlevel 1 goto NoExtensions

rem clear vars storing parameters
set SELECT_OPTIONS=
set VERIFY_FILES=
set DISM_PROGRESS=
set COPY_TO_TEMP=
set ERRORS_AS_WARNINGS=
set IGNORE_ERRORS=

set RECALL_REQUIRED=
set REBOOT_REQUIRED=

if "%DIRCMD%" NEQ "" set DIRCMD=
if "%UPDATE_LOGFILE%"=="" set UPDATE_LOGFILE=%SystemRoot%\wsusofflineupdate.log
if "%HASHDEEP_PATH%"=="" (
  if /i "%OS_ARCH%"=="x64" (set HASHDEEP_PATH=..\bin\hashdeep64.exe) else (set HASHDEEP_PATH=..\bin\hashdeep.exe)
)

if "%~1"=="" goto NoParam

set FILE_FULL_PATH=%~1

set SpaceHelper=
:RemoveSpaces
if "%FILE_FULL_PATH:~-1%"==" " (
  set FILE_FULL_PATH=%FILE_FULL_PATH:~0,-1%
  set SpaceHelper=%SpaceHelper% 
  goto RemoveSpaces
)

if "%FILE_FULL_PATH%"=="%~1" goto FileFullPathParsed
if not "%SpaceHelper%"=="" if "%FILE_FULL_PATH%%SpaceHelper%"=="%~1" goto FileFullPathParsed
goto InvalidParam
:FileFullPathParsed
if not exist "%FILE_FULL_PATH%" goto ParamFileNotFound

set FILE_FULL_PATH_DISPLAY=%FILE_FULL_PATH%

set FILE_NAME=
for /F %%i in ("%FILE_FULL_PATH%") do (
  set FILE_NAME=%%~nxi
)
if "%FILE_NAME%"=="" goto ParamInvalidFileName

if "%TEMP%"=="" goto NoTemp
pushd "%TEMP%"
if errorlevel 1 goto NoTempDir
popd

shift /1
:EvalParams
if "%~1"=="" goto NoMoreParams
if /i "%~1"=="/endevalparams" (
  shift /1
  goto NoMoreParams
)
if /i "%~1"=="/selectoptions" (
  set SELECT_OPTIONS=1
  shift /1
  goto EvalParams
)
if /i "%~1"=="/verify" (
  set VERIFY_FILES=1
  shift /1
  goto EvalParams
)
if /i "%~1"=="/showdismprogress" (
  set DISM_PROGRESS=1
  shift /1
  goto EvalParams
)
if /i "%~1"=="/copytotemp" (
  set COPY_TO_TEMP=1
  shift /1
  goto EvalParams
)
if /i "%~1"=="/errorsaswarnings" (
  set ERRORS_AS_WARNINGS=1
  shift /1
  goto EvalParams
)
if /i "%~1"=="/ignoreerrors" (
  set IGNORE_ERRORS=1
  shift /1
  goto EvalParams
)

:NoMoreParams
rem cache file in %TEMP% if requested
if "%COPY_TO_TEMP%"=="1" (
  set FILE_FULL_PATH=%TEMP%\%FILE_NAME%
  if exist "!FILE_FULL_PATH!" del "!FILE_FULL_PATH!"
  copy "%FILE_FULL_PATH_DISPLAY%" "!FILE_FULL_PATH!" >nul 2>&1
  if errorlevel 1 goto CacheError
  if not exist "!FILE_FULL_PATH!" goto CacheError
)

set IS_CORE_OS_UPDATE=0
echo %FILE_FULL_PATH_DISPLAY% %FILE_NAME% | %SystemRoot%\System32\findstr.exe /I /C:"\w100" /C:"\win\glb\" /C:"\win\" /C:"\wou_SSU" /C:"windows10.0-" /C:"windows11.0-" /C:"SSU-" >nul 2>&1
if not errorlevel 1 set IS_CORE_OS_UPDATE=1

if "%VERIFY_FILES%" NEQ "1" goto SkipVerification
if not exist %HASHDEEP_PATH% (
  if "%IS_CORE_OS_UPDATE%"=="1" (
    echo ERROR: Hashdeep utility not found. Core OS update %FILE_NAME% cannot be verified ^(fail-closed^).
    echo %DATE% %TIME% - Error: Hashdeep utility not found. Core OS update %FILE_NAME% skipped ^(fail-closed^)>>%UPDATE_LOGFILE%
    goto IntegrityError
  ) else (
    echo Warning: Hash computing utility %HASHDEEP_PATH% not found.
    echo %DATE% %TIME% - Warning: Hash computing utility not found - skipping verification>>%UPDATE_LOGFILE%
    echo %FILE_FULL_PATH_DISPLAY%>>"%TEMP%\wou_verification_skipped.txt"
    goto SkipVerification
  )
)
echo Verifying integrity of %FILE_FULL_PATH_DISPLAY%...
rem FIXME: This expects a relative path and might fail, when an absolute path is passed
set HASH_FILE_FOUND=0
set HASH_FILE=hashes-w100-%OS_ARCH%.txt
for /F "tokens=2,3 delims=\" %%i in ("%FILE_FULL_PATH_DISPLAY%") do (
  if exist ..\md\hashes-%%i-%%j.txt (
    set HASH_FILE_FOUND=1
    set HASH_FILE=hashes-%%i-%%j.txt
    %SystemRoot%\System32\findstr.exe /L /I /C:%FILE_NAME% ..\md\hashes-%%i-%%j.txt >nul 2>&1
    if errorlevel 1 (
      if "!IS_CORE_OS_UPDATE!"=="1" (
        echo ERROR: No hash entry found for core OS update %FILE_NAME% in !HASH_FILE! - skipping installation ^(fail-closed^).
        echo %DATE% %TIME% - Error: No hash entry found for %FILE_NAME% in !HASH_FILE! - skipped ^(fail-closed^)>>%UPDATE_LOGFILE%
        goto IntegrityError
      ) else (
        echo Warning: No hash entry found for %FILE_NAME% in !HASH_FILE! - skipping verification.
        echo %DATE% %TIME% - Warning: No hash entry found for %FILE_NAME% in !HASH_FILE! - skipping verification>>%UPDATE_LOGFILE%
        echo %FILE_FULL_PATH_DISPLAY%>>"%TEMP%\wou_verification_skipped.txt"
        goto SkipVerification
      )
    )
    %SystemRoot%\System32\findstr.exe /L /I /C:%% /C:%FILE_NAME% ..\md\hashes-%%i-%%j.txt >"%TEMP%\hash-%%i-%%j.txt"
    %HASHDEEP_PATH% -a -b -k "%TEMP%\hash-%%i-%%j.txt" "%FILE_FULL_PATH%"
    if errorlevel 1 (
      if exist "%TEMP%\hash-%%i-%%j.txt" del "%TEMP%\hash-%%i-%%j.txt"
      goto IntegrityError
    )
    if exist "%TEMP%\hash-%%i-%%j.txt" del "%TEMP%\hash-%%i-%%j.txt"
    goto SkipVerification
  )
  if exist ..\md\hashes-%%i.txt (
    set HASH_FILE_FOUND=1
    set HASH_FILE=hashes-%%i.txt
    %SystemRoot%\System32\findstr.exe /L /I /C:%FILE_NAME% ..\md\hashes-%%i.txt >nul 2>&1
    if errorlevel 1 (
      if "!IS_CORE_OS_UPDATE!"=="1" (
        echo ERROR: No hash entry found for core OS update %FILE_NAME% in !HASH_FILE! - skipping installation ^(fail-closed^).
        echo %DATE% %TIME% - Error: No hash entry found for %FILE_NAME% in !HASH_FILE! - skipped ^(fail-closed^)>>%UPDATE_LOGFILE%
        goto IntegrityError
      ) else (
        echo Warning: No hash entry found for %FILE_NAME% in !HASH_FILE! - skipping verification.
        echo %DATE% %TIME% - Warning: No hash entry found for %FILE_NAME% in !HASH_FILE! - skipping verification>>%UPDATE_LOGFILE%
        echo %FILE_FULL_PATH_DISPLAY%>>"%TEMP%\wou_verification_skipped.txt"
        goto SkipVerification
      )
    )
    %SystemRoot%\System32\findstr.exe /L /I /C:%% /C:%FILE_NAME% ..\md\hashes-%%i.txt >"%TEMP%\hash-%%i.txt"
    %HASHDEEP_PATH% -a -b -k "%TEMP%\hash-%%i.txt" "%FILE_FULL_PATH%"
    if errorlevel 1 (
      if exist "%TEMP%\hash-%%i.txt" del "%TEMP%\hash-%%i.txt"
      goto IntegrityError
    )
    if exist "%TEMP%\hash-%%i.txt" del "%TEMP%\hash-%%i.txt"
    goto SkipVerification
  )
  set HASH_FILE=hashes-%%i.txt
)
if "!HASH_FILE_FOUND!"=="0" (
  if "!IS_CORE_OS_UPDATE!"=="1" (
    echo ERROR: No hash entry found for core OS update %FILE_NAME% in !HASH_FILE! - skipping installation ^(fail-closed^).
    echo %DATE% %TIME% - Error: No hash entry found for %FILE_NAME% in !HASH_FILE! - skipped ^(fail-closed^)>>%UPDATE_LOGFILE%
    goto IntegrityError
  ) else (
    echo Warning: No hash entry found for %FILE_NAME% in !HASH_FILE! - skipping verification.
    echo %DATE% %TIME% - Warning: No hash entry found for %FILE_NAME% in !HASH_FILE! - skipping verification>>%UPDATE_LOGFILE%
    echo %FILE_FULL_PATH_DISPLAY%>>"%TEMP%\wou_verification_skipped.txt"
    goto SkipVerification
  )
)
:SkipVerification
if "%FILE_FULL_PATH:~-4%"==".exe" goto InstExe
if "%FILE_FULL_PATH:~-4%"==".msi" goto InstMsi
if "%FILE_FULL_PATH:~-4%"==".msu" goto InstMsu
if "%FILE_FULL_PATH:~-4%"==".zip" goto InstZip
if "%FILE_FULL_PATH:~-4%"==".cab" goto InstCab
goto UnsupType

:InstExe
if "%SELECT_OPTIONS%" NEQ "1" (
  rem This can be improved by using %*, but %* is not affected by shift-operations
  set INSTALL_SWITCHES=%1 %2 %3 %4 %5 %6 %7 %8 %9
) else (
  set INSTALL_SWITCHES=
)
rem remove spaces at begin/end of "INSTALL_SWITCHES"
:InstExe_CleanSwitchBegin
if "!INSTALL_SWITCHES!"=="" goto InstExe_Cleaned
if "!INSTALL_SWITCHES:~0,1!"==" " (
  set INSTALL_SWITCHES=!INSTALL_SWITCHES:~1!
  goto InstExe_CleanSwitchBegin
)
:InstExe_CleanSwitchEnd
if "!INSTALL_SWITCHES!"=="" goto InstExe_Cleaned
if "!INSTALL_SWITCHES:~-1!"==" " (
  set INSTALL_SWITCHES=!INSTALL_SWITCHES:~0,-1!
  goto InstExe_CleanSwitchEnd
)
:InstExe_Cleaned
if "!INSTALL_SWITCHES!"=="" (
  if exist ..\opt\OptionList.txt (
    for /F "tokens=1,2 delims=," %%a in (..\opt\OptionList.txt) do (
      if "%FILE_NAME%"=="%%a" (
        set INSTALL_SWITCHES=%%b
        rem echo InstallOSUpdate: Found match in OptionList.txt for %FILE_NAME%, install switches set to "%%b"
        goto InstExe_FoundOptions
      )
    )
  )
)
if "!INSTALL_SWITCHES!"=="" (
  if exist ..\opt\OptionList-wildcard.txt (
    for /F "tokens=1,2 delims=," %%a in (..\opt\OptionList-wildcard.txt) do (
      echo %FILE_NAME% | %SystemRoot%\System32\find.exe /I "%%a" >nul 2>&1
      if not errorlevel 1 (
        set INSTALL_SWITCHES=%%b
        rem echo InstallOSUpdate: Found match in OptionList-wildcard.txt for %FILE_NAME% ^(^*%%a^*^), install switches set to "%%b"
        goto InstExe_FoundOptions
      )
    )
  )
)
if "!INSTALL_SWITCHES!"=="" (
  set INSTALL_SWITCHES=/q /z
  rem echo InstallOSUpdate: Using default install switches "/q /z"
)
:InstExe_FoundOptions
echo Installing %FILE_FULL_PATH_DISPLAY%...
"%FILE_FULL_PATH%" !INSTALL_SWITCHES!
set ERR_LEVEL=%errorlevel%
rem echo InstallOSUpdate: ERR_LEVEL=%ERR_LEVEL%
if "%ERR_LEVEL%"=="0" (
  goto InstSuccess
) else if "%ERR_LEVEL%"=="1641" (
  set REBOOT_REQUIRED=1
  goto InstSuccess
) else if "%ERR_LEVEL%"=="3010" (
  set REBOOT_REQUIRED=1
  goto InstSuccess
) else if "%ERR_LEVEL%"=="3011" (
  set RECALL_REQUIRED=1
  goto InstSuccess
) else if "%ERR_LEVEL%"=="2359301" (
  set REBOOT_REQUIRED=1
  goto InstSuccess
) else if "%ERR_LEVEL%"=="2359302" (
  rem "already installed"
  goto InstSuccess
) else if "%ERR_LEVEL%"=="-2145124329" (
  rem "0x80240017: WU_E_NOT_APPLICABLE / superseded"
  goto InstSkipped
)
if "%IGNORE_ERRORS%"=="1" goto InstSuccess
goto InstFailure

:InstMsi
echo Installing %FILE_FULL_PATH_DISPLAY%...
pushd %~dp1
%SystemRoot%\System32\msiexec.exe /i "%FILE_FULL_PATH%" /qn /norestart
set ERR_LEVEL=%errorlevel%
rem echo InstallOSUpdate: ERR_LEVEL=%ERR_LEVEL%
popd
if "%ERR_LEVEL%"=="0" (
  goto InstSuccess
) else if "%ERR_LEVEL%"=="1641" (
  set REBOOT_REQUIRED=1
  goto InstSuccess
) else if "%ERR_LEVEL%"=="3010" (
  set REBOOT_REQUIRED=1
  goto InstSuccess
) else if "%ERR_LEVEL%"=="3011" (
  set RECALL_REQUIRED=1
  goto InstSuccess
)
if "%IGNORE_ERRORS%"=="1" goto InstSuccess
goto InstFailure

:InstMsu
echo Installing %FILE_FULL_PATH_DISPLAY%...
%SystemRoot%\System32\wusa.exe "%FILE_FULL_PATH%" /quiet /norestart
set ERR_LEVEL=%errorlevel%
rem echo InstallOSUpdate: ERR_LEVEL=%ERR_LEVEL%
if "%ERR_LEVEL%"=="0" (
  goto InstSuccess
) else if "%ERR_LEVEL%"=="1641" (
  set REBOOT_REQUIRED=1
  goto InstSuccess
) else if "%ERR_LEVEL%"=="3010" (
  set REBOOT_REQUIRED=1
  goto InstSuccess
) else if "%ERR_LEVEL%"=="3011" (
  set RECALL_REQUIRED=1
  goto InstSuccess
) else if "%ERR_LEVEL%"=="2359301" (
  set REBOOT_REQUIRED=1
  goto InstSuccess
) else if "%ERR_LEVEL%"=="2359302" (
  rem "already installed"
  goto InstSuccess
) else if "%ERR_LEVEL%"=="-2145124329" (
  rem "0x80240017: WU_E_NOT_APPLICABLE / superseded"
  goto InstSkipped
)
if "%IGNORE_ERRORS%"=="1" goto InstSuccess
goto InstFailure

:InstZip
if not exist ..\bin\unzip.exe goto NoUnZip
set FILE_FULL_PATH_ONLY=
for /f "tokens=4 delims=\" %%i in ('echo %FILE_FULL_PATH_DISPLAY%') do (
  if not "%%i"=="" (
    set FILE_FULL_PATH_ONLY=%%~ni
  )
)
if "%FILE_FULL_PATH_ONLY%"=="" (
  echo ERROR: Extraction of %FILE_FULL_PATH_DISPLAY% failed
  echo %DATE% %TIME% - Error: Extraction of %FILE_FULL_PATH_DISPLAY% failed>>%UPDATE_LOGFILE%
  goto InstFailure
)
echo Unpacking %FILE_FULL_PATH_DISPLAY% to "%TEMP%\%FILE_FULL_PATH_ONLY%.msu"...
..\bin\unzip.exe -o -d "%TEMP%" "%FILE_FULL_PATH%" "%FILE_FULL_PATH_ONLY%.msu"
if not exist "%TEMP%\%FILE_FULL_PATH_ONLY%.msu" (
  echo ERROR: Installation file "%TEMP%\%FILE_FULL_PATH_ONLY%.msu" not found.
  echo %DATE% %TIME% - Error: Installation file "%TEMP%\%FILE_FULL_PATH_ONLY%.msu" not found>>%UPDATE_LOGFILE%
  goto InstFailure
)
echo Installing "%TEMP%\%FILE_FULL_PATH_ONLY%.msu"...
%SystemRoot%\System32\wusa.exe "%TEMP%\%FILE_FULL_PATH_ONLY%.msu" /quiet /norestart
set ERR_LEVEL=%errorlevel%
rem echo InstallOSUpdate: ERR_LEVEL=%ERR_LEVEL%
del "%TEMP%\%FILE_FULL_PATH_ONLY%.msu"
if "%ERR_LEVEL%"=="0" (
  goto InstSuccess
) else if "%ERR_LEVEL%"=="1641" (
  set REBOOT_REQUIRED=1
  goto InstSuccess
) else if "%ERR_LEVEL%"=="3010" (
  set REBOOT_REQUIRED=1
  goto InstSuccess
) else if "%ERR_LEVEL%"=="3011" (
  set RECALL_REQUIRED=1
  goto InstSuccess
)
if "%IGNORE_ERRORS%"=="1" goto InstSuccess
goto InstFailure

:InstCab
if exist %SystemRoot%\Sysnative\Dism.exe goto InstDism
if exist %SystemRoot%\System32\Dism.exe goto InstDism
echo Installing %FILE_FULL_PATH_DISPLAY%...
set ERR_LEVEL=0
if "%OS_ARCH%"=="x64" (set TOKEN_KB=3) else (set TOKEN_KB=2)
for /F "tokens=%TOKEN_KB% delims=-" %%i in ("%FILE_FULL_PATH_DISPLAY%") do (
  call SafeRmDir.cmd "%TEMP%\%%i"
  md "%TEMP%\%%i"
  %SystemRoot%\System32\expand.exe "%FILE_FULL_PATH%" -F:* "%TEMP%\%%i" >nul
  %SystemRoot%\System32\PkgMgr.exe /ip /m:"%TEMP%\%%i" /quiet /norestart
  set ERR_LEVEL=%errorlevel%
  call SafeRmDir.cmd "%TEMP%\%%i"
)
rem echo InstallOSUpdate: ERR_LEVEL=%ERR_LEVEL%
if "%ERR_LEVEL%"=="0" (
  goto InstSuccess
) else if "%ERR_LEVEL%"=="1641" (
  set REBOOT_REQUIRED=1
  goto InstSuccess
) else if "%ERR_LEVEL%"=="3010" (
  set REBOOT_REQUIRED=1
  goto InstSuccess
) else if "%ERR_LEVEL%"=="3011" (
  set RECALL_REQUIRED=1
  goto InstSuccess
)
if "%IGNORE_ERRORS%"=="1" goto InstSuccess
goto InstFailure

:InstDism
if "%DISM_PROGRESS%" NEQ "1" set DISM_QPARAM=/Quiet
if "%OS_NAME%"=="w100" (
  if "%WOU_MOCK_DISM_EXIT%"=="" (
    if exist %SystemRoot%\Sysnative\Dism.exe (
      for /F "tokens=3" %%i in ('%SystemRoot%\Sysnative\Dism.exe /Online /Get-PackageInfo /PackagePath:"%FILE_FULL_PATH%" /English ^| %SystemRoot%\System32\find.exe /I "Applicable"') do (
        if /i "%%i"=="No" goto InstSkipped
      )
    ) else (
      for /F "tokens=3" %%i in ('%SystemRoot%\System32\Dism.exe /Online /Get-PackageInfo /PackagePath:"%FILE_FULL_PATH%" /English ^| %SystemRoot%\System32\find.exe /I "Applicable"') do (
        if /i "%%i"=="No" goto InstSkipped
      )
    )
  )
)
echo Installing %FILE_FULL_PATH_DISPLAY%...
if "%WOU_MOCK_DISM_EXIT%" NEQ "" (
  set ERR_LEVEL=%WOU_MOCK_DISM_EXIT%
  goto DismExecuted
)
if exist %SystemRoot%\Sysnative\Dism.exe (
  %SystemRoot%\Sysnative\Dism.exe /Online %DISM_QPARAM% /NoRestart /Add-Package /PackagePath:"%FILE_FULL_PATH%" /IgnoreCheck
) else (
  %SystemRoot%\System32\Dism.exe /Online %DISM_QPARAM% /NoRestart /Add-Package /PackagePath:"%FILE_FULL_PATH%" /IgnoreCheck
)
set ERR_LEVEL=%errorlevel%
:DismExecuted
rem echo InstallOSUpdate: ERR_LEVEL=%ERR_LEVEL%
if "%ERR_LEVEL%"=="0" (
  goto InstSuccess
) else if "%ERR_LEVEL%"=="1641" (
  set REBOOT_REQUIRED=1
  goto InstSuccess
) else if "%ERR_LEVEL%"=="3010" (
  set REBOOT_REQUIRED=1
  goto InstSuccess
) else if "%ERR_LEVEL%"=="3011" (
  set RECALL_REQUIRED=1
  goto InstSuccess
) else if "%ERR_LEVEL%"=="-2146498530" (
  rem "0x800F081E: CBS_E_NOT_APPLICABLE / superseded"
  goto InstSkipped
)
if "%IGNORE_ERRORS%"=="1" goto InstSuccess
goto InstFailure

:NoExtensions
echo ERROR: No command extensions available.
goto Error

:NoParam
echo ERROR: Invalid parameter. Usage: %~n0 ^<filename^> [/selectoptions] [/verify] [/errorsaswarnings] [/ignoreerrors] [switches]
echo %DATE% %TIME% - Error: Invalid parameter. Usage: %~n0 ^<filename^> [/selectoptions] [/verify] [/errorsaswarnings] [/ignoreerrors] [switches]>>%UPDATE_LOGFILE%
goto Error

:InvalidParam
echo ERROR: Invalid file %FILE_FULL_PATH%
echo %DATE% %TIME% - Error: Invalid file %FILE_FULL_PATH%>>%UPDATE_LOGFILE%
goto Error

:ParamFileNotFound
echo ERROR: File %FILE_FULL_PATH% not found.
echo %DATE% %TIME% - Error: File %FILE_FULL_PATH% not found>>%UPDATE_LOGFILE%
goto Error

:ParamInvalidFileName
echo ERROR: Invalid file name %FILE_FULL_PATH%
echo %DATE% %TIME% - Error: Invalid file name %FILE_FULL_PATH%>>%UPDATE_LOGFILE%
goto Error

:NoTemp
echo ERROR: Environment variable TEMP not set.
echo %DATE% %TIME% - Error: Environment variable TEMP not set>>%UPDATE_LOGFILE%
goto Error

:NoTempDir
echo ERROR: Directory "%TEMP%" not found.
echo %DATE% %TIME% - Error: Directory "%TEMP%" not found>>%UPDATE_LOGFILE%
goto Error

:NoUnZip
echo ERROR: Utility ..\bin\unzip.exe not found.
echo %DATE% %TIME% - Error: Utility ..\bin\unzip.exe not found>>%UPDATE_LOGFILE%
goto InstFailure

:CacheError
echo ERROR: Failed to copy %FILE_FULL_PATH% to the temporary directory.
echo %DATE% %TIME% - Error: Failed to copy %FILE_FULL_PATH% to the temporary directory>>%UPDATE_LOGFILE%
goto InstFailure

:IntegrityError
echo ERROR: Integrity verification failed for %FILE_FULL_PATH_DISPLAY% (corrupt or unverified package).
echo %DATE% %TIME% - Error: Integrity verification failed (corrupt/missing hash): %FILE_FULL_PATH_DISPLAY%>>%UPDATE_LOGFILE%
echo %FILE_FULL_PATH_DISPLAY%>>"%TEMP%\wou_corrupt_updates.txt"
set ERR_LEVEL=9999
goto InstFailure

:UnsupType
echo ERROR: Unsupported file type (file: %FILE_FULL_PATH_DISPLAY%).
echo %DATE% %TIME% - Error: Unsupported file type (file: %FILE_FULL_PATH_DISPLAY%)>>%UPDATE_LOGFILE%
goto InstFailure

:InstSkipped
echo %FILE_FULL_PATH_DISPLAY%>>"%TEMP%\wou_clean_skipped_updates.txt"
echo Skipped inapplicable %FILE_FULL_PATH_DISPLAY%.
echo %DATE% %TIME% - Info: Skipped inapplicable %FILE_FULL_PATH_DISPLAY%>>%UPDATE_LOGFILE%
goto EoF

:InstSuccess
echo %FILE_FULL_PATH_DISPLAY%>>"%TEMP%\wou_installed_updates.txt"
echo %DATE% %TIME% - Info: Installed %FILE_FULL_PATH_DISPLAY%>>%UPDATE_LOGFILE%
goto EoF

:InstFailure
set IS_CHECKPOINT_ERROR=
if "%ERR_LEVEL%"=="-2146498529" set IS_CHECKPOINT_ERROR=1
if "%ERR_LEVEL%"=="-2146498168" set IS_CHECKPOINT_ERROR=1
if "%ERR_LEVEL%"=="-2146498504" set IS_CHECKPOINT_ERROR=1
if "%ERR_LEVEL%"=="14098" set IS_CHECKPOINT_ERROR=1

if "%IS_CHECKPOINT_ERROR%"=="1" (
  echo %FILE_FULL_PATH_DISPLAY%>>"%TEMP%\wou_checkpoint_failures.txt"
  echo ERROR: Missing Checkpoint Cumulative Update prerequisite for %FILE_FULL_PATH_DISPLAY% [errorlevel: %ERR_LEVEL%].
  echo %DATE% %TIME% - Error: Missing Checkpoint Cumulative Update prerequisite for %FILE_FULL_PATH_DISPLAY% [errorlevel: %ERR_LEVEL%]>>%UPDATE_LOGFILE%
)
if "%IGNORE_ERRORS%"=="1" goto EoF
if "%ERRORS_AS_WARNINGS%"=="1" (goto InstWarning) else (goto InstError)

:InstWarning
if "%ERR_LEVEL%" NEQ "9999" (
  echo %FILE_FULL_PATH_DISPLAY%>>"%TEMP%\wou_failed_updates.txt"
)
echo Warning: Installation of %FILE_FULL_PATH_DISPLAY% failed (errorlevel: %ERR_LEVEL%).
echo %DATE% %TIME% - Warning: Installation of %FILE_FULL_PATH_DISPLAY% failed (errorlevel: %ERR_LEVEL%)>>%UPDATE_LOGFILE%
goto EoF

:InstError
if "%ERR_LEVEL%" NEQ "9999" (
  echo %FILE_FULL_PATH_DISPLAY%>>"%TEMP%\wou_failed_updates.txt"
)
echo ERROR: Installation of %FILE_FULL_PATH_DISPLAY% failed (errorlevel: %ERR_LEVEL%).
echo %DATE% %TIME% - Error: Installation of %FILE_FULL_PATH_DISPLAY% failed (errorlevel: %ERR_LEVEL%)>>%UPDATE_LOGFILE%
goto Error

:Error
rem don't forget to cleanup cached files
if "%COPY_TO_TEMP%"=="1" (
  if "!FILE_FULL_PATH!" NEQ "" (
    if "!FILE_FULL_PATH_DISPLAY!" NEQ "" (
      rem check, if caching code already ran
      if "%FILE_FULL_PATH_DISPLAY%" NEQ "%FILE_FULL_PATH%" (
        if exist "!FILE_FULL_PATH!" del "!FILE_FULL_PATH!"
      )
    )
  )
)

endlocal
exit /b 1

:EoF
rem don't forget to cleanup cached files
if "%COPY_TO_TEMP%"=="1" (
  if "!FILE_FULL_PATH!" NEQ "" (
    if "!FILE_FULL_PATH_DISPLAY!" NEQ "" (
      rem check, if caching code already ran
      if "%FILE_FULL_PATH_DISPLAY%" NEQ "%FILE_FULL_PATH%" (
        if exist "!FILE_FULL_PATH!" del "!FILE_FULL_PATH!"
      )
    )
  )
)

if "%RECALL_REQUIRED%"=="1" (
  endlocal
  exit /b 3011
) else if "%REBOOT_REQUIRED%"=="1" (
  endlocal
  exit /b 3010
) else (
  endlocal
  exit /b 0
)
