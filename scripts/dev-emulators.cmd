@echo off
rem エミュレータを起動する（仕様書 12.6）— Windows 用
rem
rem dev-emulators.sh の中身をそのまま Windows のコマンドプロンプト向けに
rem 書き直したもの。中身は同じなので、片方を直したらもう片方も直すこと。
rem
rem   scripts\dev-emulators.cmd
rem
rem 停止するときは Ctrl+C。データは毎回消える。
setlocal

rem このバッチが置かれている場所（scripts\）の 1 つ上＝リポジトリのルートへ移動する。
cd /d "%~dp0.."

rem エミュレータ専用のダミープロジェクト。
rem demo- で始まる ID を使うと、Firebase CLI がクラウドへ一切アクセスしなくなる。
rem （firebase login も不要）
set PROJECT=demo-musiclist

where firebase >nul 2>&1
if errorlevel 1 (
  echo [エラー] firebase コマンドが見つかりません。
  echo         次を実行してください: npm install -g firebase-tools
  exit /b 1
)

echo ==^> functions の依存パッケージを確認
if not exist "functions\node_modules" (
  rem npm は npm.cmd なので call を付けないと、ここで制御が戻らず処理が終わってしまう。
  pushd functions
  call npm install
  if errorlevel 1 (popd & exit /b 1)
  popd
)

echo ==^> functions をビルド
pushd functions
call npm run build
if errorlevel 1 (
  echo [エラー] functions のビルドに失敗しました。
  popd
  exit /b 1
)
popd

echo ==^> エミュレータを起動（プロジェクト: %PROJECT%）
echo     管理画面: http://127.0.0.1:4000
echo.
echo     別のコマンドプロンプトで次を実行するとアプリが繋がります:
echo       flutter run -d chrome --dart-define=USE_EMULATOR=true
echo.

rem localhost がプロキシ経由になる環境だと、エミュレータ同士の通信が失敗する。
rem 念のため除外しておく。
if defined NO_PROXY (set NO_PROXY=%NO_PROXY%,127.0.0.1,localhost,::1) else (set NO_PROXY=127.0.0.1,localhost,::1)
set no_proxy=%NO_PROXY%

call firebase emulators:start --project %PROJECT%
