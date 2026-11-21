@echo off
chcp 65001 >nul
set "ROOT=%~dp0"
set "ENGINE=%ROOT%engine"
set "WANT=3.13.17"
set "REPO_URL=https://github.com/86har/modal"
set "TMP_REPO=%ENGINE%\_repo"
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
echo 検出した Python: %FOUND%
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

REM ===== 6. GitHub から取得 =====
if exist "%TMP_REPO%" rmdir /s /q "%TMP_REPO%"
if exist "%ENGINE%\_zip_tmp" rmdir /s /q "%ENGINE%\_zip_tmp"

where git >nul 2>&1
if %errorlevel%==0 (
    git clone --depth 1 %REPO_URL% "%TMP_REPO%" || goto :error
) else (
    echo git が無いため zip で取得します...
    call :download_zip main
    if not exist "%TMP_REPO%" call :download_zip master
    if not exist "%TMP_REPO%" (
        echo リポジトリの取得に失敗しました。
        goto :error
    )
)

REM ===== 7. engine フォルダへ配置 =====
robocopy "%TMP_REPO%" "%ENGINE%" /E /IS /IT /XD .git /XF setup.bat update.bat run.bat /NFL /NDL /NJH /NJS /NP >nul
if errorlevel 8 goto :error
rmdir /s /q "%TMP_REPO%"

echo.
echo 完了しました。run.bat で起動できます。
pause
exit /b 0

:download_zip
powershell -NoProfile -Command "try { Invoke-WebRequest '%REPO_URL%/archive/refs/heads/%1.zip' -OutFile '%ENGINE%\repo.zip' -ErrorAction Stop; Expand-Archive '%ENGINE%\repo.zip' -DestinationPath '%ENGINE%\_zip_tmp' -Force; $d=(Get-ChildItem '%ENGINE%\_zip_tmp' -Directory | Select-Object -First 1).FullName; Move-Item $d '%TMP_REPO%'; exit 0 } catch { Write-Host $_; exit 1 }"
if exist "%ENGINE%\repo.zip" del "%ENGINE%\repo.zip"
if exist "%ENGINE%\_zip_tmp" rmdir /s /q "%ENGINE%\_zip_tmp"
exit /b

:error
echo.
echo エラーが発生したため中断しました。
pause
exit /b 1