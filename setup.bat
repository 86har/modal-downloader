@echo off
chcp 65001 >nul
set "HERE=%~dp0"
set "WANT=3.13.17"
set "SELF=%~f0"

for %%I in ("%~dp0.") do set "HN=%%~nxI"
if /i "%HN%"=="boot" (
    set "BOOT=%HERE%"
    for %%I in ("%~dp0..") do set "ROOT=%%~fI\"
    set "FIRST_RUN="
) else (
    set "ROOT=%HERE%"
    set "BOOT=%HERE%boot\"
    set "FIRST_RUN=1"
)
set "ENGINE=%ROOT%engine"
set "EXT=%ROOT%extentions"

if not exist "%BOOT%" mkdir "%BOOT%"
if defined FIRST_RUN (
    if exist "%ROOT%update.bat" move /y "%ROOT%update.bat" "%BOOT%update.bat" >nul
    if exist "%ROOT%deploy_and_run.bat" move /y "%ROOT%deploy_and_run.bat" "%BOOT%deploy_and_run.bat" >nul
)
cd /d "%BOOT%"

if exist "%BOOT%config.json" goto :cfg_done
set "CFG_WATCH=%USERPROFILE%\Downloads\outputs"
set "CFG_GPU=A10"
set "IN="
set /p "IN=画像の監視フォルダ [%CFG_WATCH%]: "
if defined IN set "CFG_WATCH=%IN%"
powershell -NoProfile -Command "[pscustomobject]@{WATCH_DIR=$env:CFG_WATCH;GPU=$env:CFG_GPU} | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath '%BOOT%config.json'" || goto :error
echo config.json を作成しました。
:cfg_done

if not exist "%ENGINE%" mkdir "%ENGINE%"

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

"%VPY%" -m pip install --upgrade pip || goto :error
"%VPY%" -m pip install flask watchdog modal || goto :error

"%VPY%" -m modal setup || goto :error

powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=(Get-Content -LiteralPath $env:SELF -Encoding UTF8 | Where-Object { $_ -like '#PS#*' } | ForEach-Object { $_.Substring(4) }) -join [Environment]::NewLine; & ([scriptblock]::Create($s)); exit $LASTEXITCODE" || goto :error

if not defined FIRST_RUN set "KREA_IN_SETUP=1"
if not exist "%BOOT%update.bat" (
    echo update.bat が見つかりません。setup.bat と同じ場所に置いてください。
    goto :error
)
call "%BOOT%update.bat" nopause || goto :error

echo.
echo 完了しました。run.bat で起動できます。
pause

(goto) 2>nul & del "%~f0"
exit /b 0

:error
echo.
echo エラーが発生したため中断しました。
pause
exit /b 1

#PS#$ErrorActionPreference = 'Stop'
#PS#[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
#PS#$vpy = $env:VPY
#PS#
#PS#function ToPlain($s) { [System.Net.NetworkCredential]::new('', $s).Password }
#PS#function AskYN($msg) { $a = Read-Host "$msg [y/N]"; return ($a -match '^[yY]') }
#PS#
#PS## ---- CivitAI トークン検証 ----
#PS#function Test-Civitai($tok) {
#PS#  try {
#PS#    Invoke-RestMethod -Uri 'https://civitai.com/api/v1/me' -Headers @{ Authorization = "Bearer $tok" } -TimeoutSec 20 | Out-Null
#PS#    return 'ok'
#PS#  } catch {
#PS#    $r = $_.Exception.Response
#PS#    if ($r -and ([int]$r.StatusCode -in 401, 403)) { return 'invalid' }
#PS#    return 'error: ' + $_.Exception.Message
#PS#  }
#PS#}
#PS#
#PS## ---- CivitAI ----
#PS#while ($true) {
#PS#  $tp = ToPlain (Read-Host 'CivitAI トークン')
#PS#  Write-Host 'CivitAI トークンを確認中...'
#PS#  $res = Test-Civitai $tp
#PS#  if ($res -eq 'ok') { Write-Host 'CivitAI トークン: OK'; break }
#PS#  if ($res -eq 'invalid') { Write-Host 'CivitAI トークンが無効です。もう一度入力してください。'; continue }
#PS#  Write-Host "CivitAI トークンを確認できませんでした ($res)"
#PS#  if (AskYN 'このまま登録しますか') { break }
#PS#}
#PS#
#PS## ---- MEGA（認証・検証なし） ----
#PS#$e = (Read-Host 'MEGA メールアドレス').Trim()
#PS#$pp = ToPlain (Read-Host 'MEGA パスワード')
#PS#
#PS## ---- modal secret 登録 ----
#PS#& $vpy -m modal secret create krea2-tokens ('CIVITAI_TOKEN=' + $tp) ('MEGA_EMAIL=' + $e) ('MEGA_PASS=' + $pp) --force
#PS#exit $LASTEXITCODE
