@echo off
rem 動作確認用のデータをエミュレータに入れる — Windows 用
rem
rem seed.sh を Windows のコマンドプロンプト向けに書き直したもの。
rem 片方を直したらもう片方も直すこと。
rem
rem   scripts\seed.cmd
rem
rem エミュレータが起動している状態で実行してください。
setlocal

cd /d "%~dp0"

if not exist "node_modules" (
  rem npm は npm.cmd なので call が要る。
  call npm install
  if errorlevel 1 exit /b 1
)

set FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099
set FIRESTORE_EMULATOR_HOST=127.0.0.1:8080

node seed-emulator.js
