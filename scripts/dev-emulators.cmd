@echo off
rem Windows launcher. The real logic lives in dev-emulators.mjs.
rem
rem IMPORTANT: keep this file ASCII-only.
rem cmd.exe reads a batch file using the console code page (CP932 on Japanese
rem Windows), so UTF-8 Japanese text here is decoded as garbage -- and the
rem garbage is then parsed as commands. Japanese messages belong in the .mjs:
rem Node writes to the Windows console as UTF-16, so they always come out right.
where node >nul 2>&1
if errorlevel 1 (
  echo Node.js 20 or later is required. https://nodejs.org/
  exit /b 1
)
node "%~dp0dev-emulators.mjs" %*
