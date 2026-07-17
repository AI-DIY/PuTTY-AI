@echo off
setlocal

rem Codex and some CI launchers can provide both PATH and Path entries.
rem MSBuild's .NET process launcher rejects that case-insensitive duplicate.
set "SANITIZED_PATH=%PATH%"
set PATH=
set "Path=%SANITIZED_PATH%"
set SANITIZED_PATH=

set "ROOT=%~dp0.."
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"

if not exist "%VSWHERE%" (
  echo Visual Studio Installer was not found.
  exit /b 1
)

for /f "usebackq tokens=*" %%I in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSROOT=%%I"
if not defined VSROOT (
  echo Visual Studio 2022 C++ Build Tools were not found.
  exit /b 1
)

call "%VSROOT%\Common7\Tools\VsDevCmd.bat" -arch=x64 -host_arch=x64
if errorlevel 1 exit /b %errorlevel%

if /i "%~1"=="diagnose" goto diagnose

set "CMAKE=%VSROOT%\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
if not exist "%CMAKE%" set "CMAKE=cmake"

"%CMAKE%" -S "%ROOT%\putty-src" -B "%ROOT%\build" -G "Visual Studio 17 2022" -A x64
if errorlevel 1 exit /b %errorlevel%

if /i "%~1"=="configure" exit /b 0

set "TARGET=putty"
if not "%~1"=="" set "TARGET=%~1"
"%CMAKE%" --build "%ROOT%\build" --config Release --target "%TARGET%"
exit /b %errorlevel%

:diagnose
where cl
echo VCToolsInstallDir=%VCToolsInstallDir%
echo WindowsSdkDir=%WindowsSdkDir%
exit /b 0
