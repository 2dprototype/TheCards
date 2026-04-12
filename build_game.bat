@echo off
setlocal EnableDelayedExpansion

echo ==============================================
echo Building DevilBridge Dev Release...
echo ==============================================
echo.

if not exist build mkdir build

echo [1/4] Creating .love file from client folder...
if exist build\DevilBridge.love del build\DevilBridge.love

:: Navigate into the client folder and zip its contents (not the folder itself)
pushd client
:: Use PowerShell to create zip with proper structure (main.lua at root)
powershell.exe -noprofile -command "Compress-Archive -Path * -DestinationPath '..\build\DevilBridge.zip' -Force"
popd

if exist build\DevilBridge.zip (
    :: Rename .zip to .love
    ren build\DevilBridge.zip DevilBridge.love
    echo Successfully created DevilBridge.love
) else (
    echo [ERROR] Failed to create DevilBridge.love!
    pause
    exit /b 1
)
echo.

echo [2/4] Checking for love.exe...
set "LOVE_EXE="
if exist "love\love.exe" set "LOVE_EXE=love\love.exe"

if defined LOVE_EXE (
    echo Found LOVE runtime at !LOVE_EXE!
) else (
    echo [ERROR] love.exe not found in love\ folder!
    echo Please place love.exe and its DLL files in the love\ folder.
    pause
    exit /b 1
)
echo.

echo [3/4] Building fused executable...
:: Create fused executable by appending .love to love.exe
copy /b "!LOVE_EXE!" + "build\DevilBridge.love" "build\bridge.exe" /Y >nul
if exist build\bridge.exe (
    echo Successfully created bridge.exe
) else (
    echo [ERROR] Failed to create bridge.exe!
    pause
    exit /b 1
)
echo.

echo [4/4] Copying required LÖVE DLL files for standalone execution...
:: Copy all DLL files from love folder to build folder
copy /Y "love\*.dll" "build\" >nul 2>&1
:: Copy license.txt (required by LÖVE license)
if exist "love\license.txt" copy /Y "love\license.txt" "build\" >nul

:: Check if critical DLLs are present
set "MISSING_DLLS="
if not exist "build\love.dll" set "MISSING_DLLS=!MISSING_DLLS! love.dll"
if not exist "build\lua51.dll" set "MISSING_DLLS=!MISSING_DLLS! lua51.dll"
if not exist "build\SDL2.dll" set "MISSING_DLLS=!MISSING_DLLS! SDL2.dll"

if defined MISSING_DLLS (
    echo [WARNING] Missing DLL files:!MISSING_DLLS!
    echo Please ensure all LÖVE DLL files are in the love\ folder.
) else (
    echo All required DLL files copied successfully.
)
echo.

echo [Optional] Copying Proxy Server...
if exist "proxy_go\proxy.exe" (
    copy /Y "proxy_go\proxy.exe" "build\" >nul
    if exist "proxy_go\.env" copy /Y "proxy_go\.env" "build\" >nul
    echo proxy.exe and environment variables copied successfully.
) else (
    echo [INFO] proxy_go\proxy.exe not found - skipping proxy server.
)

echo [Optional] Copying Game Launcher...
if exist "launcher\launcher.exe" (
    copy /Y "launcher\launcher.exe" "build\" >nul
    echo launcher.exe and environment variables copied successfully.
) else (
    echo [INFO] launcher\launcher.exe not found - skipping proxy server.
)

echo.
echo ==============================================
echo Build complete! Distribution files in \build folder:
echo ==============================================
echo Required files for distribution:
echo   - bridge.exe
echo   - love.dll
echo   - lua51.dll
echo   - SDL2.dll
echo   - OpenAL32.dll
echo   - mpg123.dll
echo   - license.txt
echo.
echo You can now distribute the contents of the build folder.
echo ==============================================
pause
endlocal