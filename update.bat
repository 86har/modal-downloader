@echo off
chcp 65001 >nul
set "ROOT=%~dp0"
set "ENGINE=%ROOT%engine"
set "REPO_URL=https://github.com/86har/modal"
set "TMP_REPO=%ENGINE%\_repo"
cd /d "%ROOT%"

if not exist "%ENGINE%" (
    echo engine フォルダがありません。先に setup.bat を実行してください。
    goto :error
)

REM ===== 1. 最新ファイルを一時フォルダへ取得 =====
if exist "%TMP_REPO%" rmdir /s /q "%TMP_REPO%"
if exist "%ENGINE%\_zip_tmp" rmdir /s /q "%ENGINE%\_zip_tmp"

where git >nul 2>&1
if %errorlevel%==0 (
    echo git で取得します...
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

REM ===== 2. engine フォルダへ上書き =====
REM 同名ファイルは上書き、手元にだけあるファイルは残す
REM venv と config.json には触れない。secrets*.json は上書きしない
robocopy "%TMP_REPO%" "%ENGINE%" /E /IS /IT /XD .git venv /XF setup.bat update.bat run.bat config.json secrets.json "secrets copy.json" /NFL /NDL /NJH /NJS /NP >nul
if errorlevel 8 goto :error

REM ===== 3. 一時フォルダの削除 =====
rmdir /s /q "%TMP_REPO%"

echo.
echo 更新が完了しました。
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
