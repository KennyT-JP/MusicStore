@echo off
rem Windows launcher. The real logic lives in test-all.mjs.
rem Keep this file ASCII-only -- see dev-emulators.cmd for why.
where node >nul 2>&1
if errorlevel 1 (
  echo Node.js 20 or later is required. https://nodejs.org/
  exit /b 1
)
node "%~dp0test-all.mjs" %*
