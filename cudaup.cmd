@echo off
setlocal ENABLEDELAYEDEXPANSION

rem ------------------------------------------------------------
rem Defaults
rem ------------------------------------------------------------
set "OS=win64"
set "CPU="
set "WS="

set "DO_GET=0"
set "DO_UPDATE=0"
set "DO_PACKS=0"
set "DO_MAKE=0"
set "DO_CLEAN=0"
set "LAZDIR="

if "%~1"=="" goto :usage

:parse_args
if "%~1"=="" goto :args_done

if /I "%~1"=="-g"        set "DO_GET=1"    & shift & goto :parse_args
if /I "%~1"=="--get"     set "DO_GET=1"    & shift & goto :parse_args

if /I "%~1"=="-u"        set "DO_UPDATE=1" & shift & goto :parse_args
if /I "%~1"=="--update"  set "DO_UPDATE=1" & shift & goto :parse_args

if /I "%~1"=="-p"        set "DO_PACKS=1"  & shift & goto :parse_args
if /I "%~1"=="--packs"   set "DO_PACKS=1"  & shift & goto :parse_args

if /I "%~1"=="-m"        set "DO_MAKE=1"   & shift & goto :parse_args
if /I "%~1"=="--make"    set "DO_MAKE=1"   & shift & goto :parse_args

if /I "%~1"=="--clean"   set "DO_CLEAN=1"  & shift & goto :parse_args

if /I "%~1"=="-l"        set "LAZDIR=%~2"  & shift & shift & goto :parse_args
if /I "%~1"=="--lazdir"  set "LAZDIR=%~2"  & shift & shift & goto :parse_args

if /I "%~1"=="-o"        set "OS=%~2"      & shift & shift & goto :parse_args
if /I "%~1"=="--os"      set "OS=%~2"      & shift & shift & goto :parse_args

if /I "%~1"=="-c"        set "CPU=%~2"     & shift & shift & goto :parse_args
if /I "%~1"=="--cpu"     set "CPU=%~2"     & shift & shift & goto :parse_args

if /I "%~1"=="-w"        set "WS=%~2"      & shift & shift & goto :parse_args
if /I "%~1"=="--ws"      set "WS=%~2"      & shift & shift & goto :parse_args

if /I "%~1"=="-h"        goto :usage
if /I "%~1"=="--help"    goto :usage

echo Unknown option: %~1
goto :usage

:args_done

set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%"

set "REPO_FILE=cudaup.repos"
set "PACK_FILE=cudaup.packets"

if "%DO_CLEAN%"=="1"  call :do_clean
if "%DO_GET%"=="1"    call :do_get
if "%DO_UPDATE%"=="1" call :do_update

if "%DO_PACKS%"=="1" (
    if not defined LAZDIR (
        echo Error: Lazarus directory not given. Use -l ^<path-to-Lazarus^>.
        goto :end
    )
    if not exist "%LAZDIR%\lazbuild.exe" (
        echo Error: "%LAZDIR%\lazbuild.exe" not found.
        goto :end
    )
    call :do_packs
)

if "%DO_MAKE%"=="1" (
    if not defined LAZDIR (
        echo Error: Lazarus directory not given. Use -l ^<path-to-Lazarus^>.
        goto :end
    )
    if not exist "%LAZDIR%\lazbuild.exe" (
        echo Error: "%LAZDIR%\lazbuild.exe" not found.
        goto :end
    )
    call :do_make
)

goto :end

rem ------------------------------------------------------------
rem --clean : remove FPC output dirs under src\*\*\lib\*-*
rem ------------------------------------------------------------
:do_clean
echo Cleaning FPC output dirs under src\...
if exist "src" (
    for /d /r "src" %%L in (lib) do (
        for /d %%T in ("%%L\*-*") do (
            if exist "%%T" (
                echo   removing "%%T"
                rd /s /q "%%T"
            )
        )
    )
)
exit /b

rem ------------------------------------------------------------
rem -g / --get : add/init submodules under src\ from cudaup.repos
rem             (uses -f so src can stay in .gitignore)
rem ------------------------------------------------------------
:do_get
where git >nul 2>nul
if errorlevel 1 (
    echo Error: git.exe not found in PATH.
    exit /b 1
)

if not exist "src" mkdir "src"

for /f "usebackq delims=" %%R in ("%REPO_FILE%") do (
    set "URL=%%R"
    rem trim spaces
    set "URL=!URL: =!"
    if "!URL!"=="" (
        rem skip empty line
    ) else if "!URL:~0,1!"=="#" (
        rem skip commented line
    ) else (
        for %%N in (!URL!) do set "NAME=%%~nN"
        rem if not already in .gitmodules, add as submodule
        git config -f .gitmodules "submodule.src/!NAME!.url" >nul 2>&1
        if errorlevel 1 (
            echo Adding submodule src/!NAME! ^(!URL!^)
            git submodule add -f "!URL!" "src/!NAME!"
        ) else (
            echo Submodule src/!NAME! already configured.
        )
    )
)

echo Syncing and initializing submodules...
git submodule sync >nul 2>&1
git submodule update --init --recursive
exit /b

rem ------------------------------------------------------------
rem -u / --update : move submodules to latest commits on upstream
rem                 branches (according to .gitmodules)
rem ------------------------------------------------------------
:do_update
where git >nul 2>nul
if errorlevel 1 (
    echo Error: git.exe not found in PATH.
    exit /b 1
)

echo Updating submodules to latest upstream commits...
git submodule sync >nul 2>&1
git submodule update --init --recursive --remote
exit /b

rem ------------------------------------------------------------
rem -p / --packs : build+install Lazarus packages and rebuild IDE
rem ------------------------------------------------------------
:do_packs
for /f "usebackq delims=" %%P in ("%PACK_FILE%") do (
    set "PK=%%P"
    if "!PK!"=="" (
        rem skip
    ) else if "!PK:~0,1!"=="#" (
        rem skip commented line
    ) else (
        echo Building package !PK!
        "%LAZDIR%\lazbuild.exe" -q --lazarusdir="%LAZDIR%" "src\!PK!"
        echo Installing package !PK! into Lazarus...
        "%LAZDIR%\lazbuild.exe" -q --lazarusdir="%LAZDIR%" --add-package "src\!PK!"
    )
)
echo Rebuilding Lazarus IDE with installed packages...
"%LAZDIR%\lazbuild.exe" -q --lazarusdir="%LAZDIR%" --build-ide=
exit /b

rem ------------------------------------------------------------
rem -m / --make : build CudaText for given OS/CPU/WS
rem               (uses packages; pre-builds if -p not used)
rem ------------------------------------------------------------
:do_make
set "INC="

rem only add --os when not linux (matches original logic loosely)
if /I "%OS%" NEQ "linux" (
    set "INC=!INC! --os=%OS%"
)

rem default CPU for Windows if not specified
if /I "%OS%"=="win32" if not defined CPU set "CPU=i386"
if /I "%OS%"=="win64" if not defined CPU set "CPU=x86_64"

if defined CPU set "INC=!INC! --cpu=%CPU%"
if defined WS  set "INC=!INC! --ws=%WS%"

rem If packages were not installed via --packs, prebuild them locally
if "%DO_PACKS%"=="0" (
    for /f "usebackq delims=" %%P in ("%PACK_FILE%") do (
        set "PK=%%P"
        if "!PK!"=="" (
        ) else if "!PK:~0,1!"=="#" (
        ) else (
            echo Pre-building package !PK! ...
            "%LAZDIR%\lazbuild.exe" !INC! -q --lazarusdir="%LAZDIR%" "src\!PK!"
        )
    )
)

echo Building CudaText project...
if exist "src\CudaText\app\cudatext.exe" del /q "src\CudaText\app\cudatext.exe"
if exist "src\CudaText\app\cudatext"     del /q "src\CudaText\app\cudatext"

"%LAZDIR%\lazbuild.exe" !INC! -q --lazarusdir="%LAZDIR%" "src\CudaText\app\cudatext.lpi"

set "OUTDIR=bin\%OS%"
if defined CPU set "OUTDIR=%OUTDIR%-%CPU%"
if defined WS  set "OUTDIR=%OUTDIR%-%WS%"

if not exist "%OUTDIR%" mkdir "%OUTDIR%"

if /I "%OS%"=="win32" (
    copy /y "src\CudaText\app\cudatext.exe" "%OUTDIR%\cudatext.exe" >nul
) else if /I "%OS%"=="win64" (
    copy /y "src\CudaText\app\cudatext.exe" "%OUTDIR%\cudatext.exe" >nul
) else (
    if exist "src\CudaText\app\cudatext.exe" (
        copy /y "src\CudaText\app\cudatext.exe" "%OUTDIR%\cudatext.exe" >nul
    ) else (
        copy /y "src\CudaText\app\cudatext" "%OUTDIR%\cudatext" >nul
    )
)

echo Output copied to "%OUTDIR%"
exit /b

rem ------------------------------------------------------------
rem Usage
rem ------------------------------------------------------------
:usage
echo Usage: %~nx0 [options]
echo.
echo   -g  --get        add/init Git submodules under .\src\ from cudaup.repos  ^(uses -f^)
echo   -u  --update     update submodules to latest upstream commits
echo   -p  --packs      build and install Lazarus packages ^(cudaup.packets^) and rebuild IDE
echo   -m  --make       build CudaText from src\CudaText\app\cudatext.lpi
echo   -l  --lazdir     path to Lazarus dir ^(where lazbuild.exe lives^)
echo   -o  --os         target OS   ^(win32, win64, linux, ...; default win64^)
echo   -c  --cpu        target CPU  ^(i386, x86_64, arm, ...^)
echo   -w  --ws         widgetset   ^(gtk2, gtk3, qt5, cocoa, ...^)
echo       --clean      remove FPC temp dirs under src\*\*\lib\*-*
echo   -h  --help       show this help
echo.
echo Examples:
echo   %~nx0 -g
echo   %~nx0 -g -m -l C:\lazarus
echo   %~nx0 -g -p -m -l C:\lazarus
goto :end

:end
popd
endlocal
goto :EOF
