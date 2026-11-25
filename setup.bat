@echo off
chcp 65001 >nul
set "ROOT=%~dp0"
set "ENGINE=%ROOT%engine"
set "WANT=3.13.17"
cd /d "%ROOT%"

REM ===== 0. config.json の作成(無い場合のみ) =====
if exist "%ROOT%config.json" goto :cfg_done
set "CFG_WATCH=%USERPROFILE%\Downloads\outputs"
set "CFG_GPU=A10"
set "IN="
set /p "IN=画像の監視フォルダ [%CFG_WATCH%]: "
if defined IN set "CFG_WATCH=%IN%"
set "IN="
set /p "IN=GPU の種類 (T4 / L4 / A10 / A100 / H100 など) [%CFG_GPU%]: "
if defined IN set "CFG_GPU=%IN%"
powershell -NoProfile -Command "[pscustomobject]@{WATCH_DIR=$env:CFG_WATCH;GPU=$env:CFG_GPU} | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath '%ROOT%config.json'" || goto :error
echo config.json を作成しました。
:cfg_done

if not exist "%ENGINE%" mkdir "%ENGINE%"

REM ===== 1. 仮想環境の作成 (engine\venv) =====
set "FOUND="
for /f "tokens=2" %%v in ('py -3.13 --version 2^>nul') do set "FOUND=%%v"
if not defined FOUND (
    echo Python 3.13 が見つかりません。インストールしてください。
    goto :error
)
echo 検出 Python: %FOUND%
if not "%FOUND%"=="%WANT%" (
    echo ※ 指定は %WANT% ですが %FOUND% が使われます。
    choice /c YN /m "続行しますか"
    if errorlevel 2 exit /b 1
)

if not exist "%ENGINE%\venv\Scripts\python.exe" (
    py -3.13 -m venv "%ENGINE%\venv" || goto :error
)
set "VPY=%ENGINE%\venv\Scripts\python.exe"

REM ===== 2. パッケージのインストール =====
"%VPY%" -m pip install --upgrade pip || goto :error
"%VPY%" -m pip install flask watchdog modal || goto :error

REM ===== 3. modal setup (ブラウザ認証) =====
"%VPY%" -m modal setup || goto :error

REM ===== 4-5. 認証情報の入力 と modal secret 作成 =====
set "PS=$t=Read-Host 'CivitAI トークン' -AsSecureString;"
set "PS=%PS% $e=Read-Host 'MEGA メールアドレス';"
set "PS=%PS% $p=Read-Host 'MEGA パスワード' -AsSecureString;"
set "PS=%PS% $tp=[System.Net.NetworkCredential]::new('',$t).Password;"
set "PS=%PS% $pp=[System.Net.NetworkCredential]::new('',$p).Password;"
set "PS=%PS% & '%VPY%' -m modal secret create krea2-tokens ('CIVITAI_TOKEN='+$tp) ('MEGA_EMAIL='+$e) ('MEGA_PASS='+$pp) --force;"
set "PS=%PS% exit $LASTEXITCODE"
powershell -NoProfile -ExecutionPolicy Bypass -Command "%PS%" || goto :error

REM ===== 6. GitHub から取得 → engine へ配置 → config.json 参照パッチ =====
REM (update.bat と同じ処理を呼び出します)
call "%ROOT%update.bat" nopause || goto :error

echo.
echo 完了しました。run.bat で起動できます。
pause
exit /b 0

:error
echo.
echo エラーが発生したため中断しました。
pause
exit /b 1
