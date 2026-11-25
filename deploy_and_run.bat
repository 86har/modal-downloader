@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
set "ROOT=%~dp0"
set "ENGINE=%ROOT%engine"
cd /d "%ROOT%"

if not exist "%ENGINE%\venv\Scripts\python.exe" (
    echo 仮想環境が見つかりません。先に setup.bat を実行してください。
    pause
    exit /b 1
)

REM ===== GitHub に新しいコードがあれば自動更新 =====
REM (更新で run.bat 自身も置き換わるため、更新後は新しい版で起動し直す)
set "SHA_FILE=%ROOT%.repo_sha.txt"
set "REMOTE_SHA="
for /f "usebackq delims=" %%S in (`powershell -NoProfile -Command "try { (Invoke-RestMethod -Uri 'https://api.github.com/repos/86har/modal-app/commits/HEAD' -Headers @{Accept='application/vnd.github.sha'} -TimeoutSec 5).ToString().Trim() } catch { '' }"`) do set "REMOTE_SHA=%%S"

set "LOCAL_SHA="
if exist "%SHA_FILE%" set /p LOCAL_SHA=<"%SHA_FILE%"

if not defined KREA_UPDATED if defined REMOTE_SHA if /i not "!REMOTE_SHA!"=="!LOCAL_SHA!" (
    echo 新しいコードを検出したため、更新します。
    call "%ROOT%update.bat" nopause
    if errorlevel 1 (
        echo 更新に失敗しました。現在のバージョンで起動します。
    ) else (
        >"%SHA_FILE%" echo !REMOTE_SHA!
        set "KREA_UPDATED=1"
        start "" "%~f0" %*
        exit /b 0
    )
)

set "GEN="
if exist "%ENGINE%\gen.py"       set "GEN=%ENGINE%\gen.py"
if exist "%ENGINE%\modal\gen.py" set "GEN=%ENGINE%\modal\gen.py"
if not defined GEN (
    echo gen.py が見つかりません。update.bat を実行してください。
    pause
    exit /b 1
)

if not exist "%ROOT%config.json" echo ※ config.json が無いため、既定の設定で起動します。

REM プログラムから参照できるように config.json の場所を環境変数で渡す
set "KREA_CONFIG=%ROOT%config.json"
set "PYTHONUTF8=1"
set "VIRTUAL_ENV=%ENGINE%\venv"
set "PATH=%ENGINE%\venv\Scripts;%PATH%"

for %%F in ("%GEN%") do set "GENDIR=%%~dpF"

REM config.json のハッシュを記録（必要なら残す）
set "HASH_FILE=%ROOT%.config_hash.txt"
if exist "%ROOT%config.json" (
    set "NEWHASH="
    for /f "usebackq delims=" %%H in (`powershell -NoProfile -Command "(Get-FileHash -LiteralPath '%ROOT%config.json' -Algorithm SHA256).Hash"`) do set "NEWHASH=%%H"

    set "OLDHASH="
    if exist "!HASH_FILE!" set /p OLDHASH=<"!HASH_FILE!"

    if /i not "!NEWHASH!"=="!OLDHASH!" (
        >"!HASH_FILE!" echo !NEWHASH!
    )
)

REM 常に -d を付与して起動する
set "DEPLOY_FLAG=-d"

REM batファイルを経由せず「cmd /c」で起動する。
REM (batファイル実行中に Ctrl+C を押すと出る「Terminate batch job (Y/N)?」を避けるため)
REM 正常終了したらウィンドウは自動で閉じ、エラー終了のときだけ内容を確認できるよう一時停止する
set CMDLINE="%ENGINE%\venv\Scripts\python.exe" "%GEN%" %DEPLOY_FLAG% %*
start "Krea" /D "%GENDIR%" cmd /c "%CMDLINE% || pause"
exit /b 0