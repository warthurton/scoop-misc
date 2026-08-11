@echo off
setlocal enabledelayedexpansion

pushd "%~dp0" || (
  echo Failed to change to script directory
  pause
  exit /b 1
)

:: Always resolve script directory separately (may be read-only)
set "SCRIPT_DIR=%CD%"
set "APP_DIR=%SCRIPT_DIR%\app"

:: Move all writable work to TEMP
set "WORK_DIR=%TEMP%\node-installer-%RANDOM%"
set "TEMP_DIR=%WORK_DIR%\temp"
set "DEST_DIR=%WORK_DIR%\node"

mkdir "%WORK_DIR%" >nul 2>&1
mkdir "%TEMP_DIR%" >nul 2>&1

SET PATH=C:\Windows\System32;%PATH%

set NODE_VERSION=v18.20.5
set BASE_URL=https://nodejs.org/download/release/%NODE_VERSION%/
set ARCHIVE_NAME=
set ARCHIVE_DIR=

IF NOT EXIST "%APP_DIR%\install.js" (
  echo [ERROR] To run the installer, please first unzip the archive
  pause
  exit /b 1
)

:: Check system Node.js
WHERE node >nul 2>&1
IF %ERRORLEVEL%==0 (
  echo .. Using system Node.js
  node "%APP_DIR%\install.js" "%LocalAPPData%"
  if errorlevel 1 (
    echo Failed to run install.js with system Node.js
    pause
    exit /b 1
  )
  GOTO :REGISTRY
)

echo .. System Node.js not found, downloading portable version...

IF "%PROCESSOR_ARCHITECTURE%"=="AMD64" (
  set ARCHIVE_NAME=node-%NODE_VERSION%-win-x64.zip
  set ARCHIVE_DIR=node-%NODE_VERSION%-win-x64
) ELSE (
  set ARCHIVE_NAME=node-%NODE_VERSION%-win-x86.zip
  set ARCHIVE_DIR=node-%NODE_VERSION%-win-x86
)

echo .. Downloading %BASE_URL%%ARCHIVE_NAME%

WHERE curl >nul 2>&1
if %errorlevel%==0 (
    curl -k -o "%TEMP_DIR%\%ARCHIVE_NAME%" "%BASE_URL%%ARCHIVE_NAME%"
) else (
    powershell -Command ^
      "Invoke-WebRequest -Uri '%BASE_URL%%ARCHIVE_NAME%' -OutFile '%TEMP_DIR%\%ARCHIVE_NAME%'"
)

if errorlevel 1 (
  echo Failed to download %ARCHIVE_NAME%
  pause
  exit /b 1
)

echo .. Extracting %ARCHIVE_NAME%...
powershell -Command "Expand-Archive -Path '%TEMP_DIR%\%ARCHIVE_NAME%' -DestinationPath '%DEST_DIR%' -Force"

if errorlevel 1 (
  echo Failed to extract %ARCHIVE_NAME%
  pause
  exit /b 1
)

"%DEST_DIR%\%ARCHIVE_DIR%\node.exe" "%APP_DIR%\install.js" "%LocalAPPData%"
if errorlevel 1 (
  echo Failed to run install.js with portable Node.js
  pause
  exit /b 1
)

:: Cleanup (safe because it's in TEMP now)
rmdir /s /q "%WORK_DIR%" 2>nul

:REGISTRY
echo.
echo .. Writing to Chrome Registry
REG ADD "HKCU\Software\Google\Chrome\NativeMessagingHosts\com.add0n.node" /ve /t REG_SZ /d "%LocalAPPData%\com.add0n.node\manifest-chrome.json" /f

echo .. Writing to Chromium Registry
REG ADD "HKCU\Software\Chromium\NativeMessagingHosts\com.add0n.node" /ve /t REG_SZ /d "%LocalAPPData%\com.add0n.node\manifest-chrome.json" /f

echo .. Writing to Edge Registry
REG ADD "HKCU\Software\Microsoft\Edge\NativeMessagingHosts\com.add0n.node" /ve /t REG_SZ /d "%LocalAPPData%\com.add0n.node\manifest-chrome.json" /f

echo .. Writing to Perplexity Comet Registry
REG ADD "HKCU\Software\Comet\NativeMessagingHosts\com.add0n.node" /ve /t REG_SZ /d "%LocalAPPData%\com.add0n.node\manifest-chrome.json" /f

echo .. Writing to Firefox Registry
FOR %%f in ("%LocalAPPData%") do SET SHORT_PATH=%%~sf
REG ADD "HKCU\SOFTWARE\Mozilla\NativeMessagingHosts\com.add0n.node" /ve /t REG_SZ /d "%SHORT_PATH%\com.add0n.node\manifest-firefox.json" /f

echo .. Writing to Waterfox Registry
REG ADD "HKCU\SOFTWARE\Waterfox\NativeMessagingHosts\com.add0n.node" /ve /t REG_SZ /d "%SHORT_PATH%\com.add0n.node\manifest-firefox.json" /f

echo .. Writing to Thunderbird Registry
REG ADD "HKCU\SOFTWARE\Thunderbird\NativeMessagingHosts\com.add0n.node" /ve /t REG_SZ /d "%SHORT_PATH%\com.add0n.node\manifest-firefox.json" /f

echo.
echo .. Native client is ready!
PAUSE

