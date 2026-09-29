@echo off
setlocal

REM ======= ANPASSEN =======
set "CPPSHARP_DIR=%FRC_PROJ_DIR%\CppSharp"
set "SCRIPT=%~dp0package.sh"
set "LOG=%~dp0package_log.txt"
REM ========================

REM ---------- MSVC-Umgebung selbst setzen (das macht die Dev-Shell) ----------
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
    echo FEHLER: vswhere.exe nicht gefunden - Visual Studio 2022 installiert?
    pause
    exit /b 1
)

for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VS_PATH=%%i"

if not defined VS_PATH (
    echo FEHLER: Kein Visual Studio mit C++-Workload gefunden.
    echo Installiere die "Desktopentwicklung mit C++"-Workload im VS Installer.
    pause
    exit /b 1
)

echo Nutze Visual Studio: %VS_PATH%
call "%VS_PATH%\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 (
    echo FEHLER: vcvars64.bat konnte nicht ausgefuehrt werden.
    pause
    exit /b 1
)

REM ---------- Git Bash finden ----------
set "BASH=%ProgramFiles%\Git\bin\bash.exe"
if not exist "%BASH%" (
    echo FEHLER: Git Bash nicht gefunden: %BASH%
    pause
    exit /b 1
)

REM ---------- Build-Skript ausfuehren ----------
"%BASH%" "%~dp0package.sh"
set "EXITCODE=%errorlevel%"

echo.
echo ==============================
if "%EXITCODE%"=="0" (echo BUILD ERFOLGREICH) else (echo BUILD FEHLGESCHLAGEN - Exit-Code %EXITCODE%)
echo ==============================

REM Shell offen halten zum Nachschauen
echo.
pause