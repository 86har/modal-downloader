@echo off
chcp 65001 >nul
set "HERE=%~dp0"
set "WANT=3.13.17"
set "SELF=%~f0"

REM ===== 配置の決定 =====
REM setup.bat を置いたフォルダを ROOT とし、bat 類は ROOT\boot にまとめる。
REM (すでに boot フォルダ内から実行された場合は、その1つ上を ROOT とする)
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
    REM 同じ階層にある update.bat を boot へ移す
    if exist "%ROOT%update.bat" move /y "%ROOT%update.bat" "%BOOT%update.bat" >nul
    if exist "%ROOT%deploy_and_run.bat" move /y "%ROOT%deploy_and_run.bat" "%BOOT%deploy_and_run.bat" >nul
)
cd /d "%BOOT%"

REM ===== 0. config.json の作成(無い場合のみ) =====
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

REM ===== 4-5. 認証情報の入力 → 検証 → modal secret 作成 =====
REM この bat 末尾の「#PS#」で始まる行が PowerShell 本体 (抽出して実行する)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=(Get-Content -LiteralPath $env:SELF -Encoding UTF8 | Where-Object { $_ -like '#PS#*' } | ForEach-Object { $_.Substring(4) }) -join [Environment]::NewLine; & ([scriptblock]::Create($s)); exit $LASTEXITCODE" || goto :error

REM ===== 6. GitHub から取得 → engine へ配置 → config.json 参照パッチ =====
REM (update.bat と同じ処理を呼び出します)
REM boot 内の setup.bat を直接実行している場合のみ、自分自身の上書きを避ける
if not defined FIRST_RUN set "KREA_IN_SETUP=1"
if not exist "%BOOT%update.bat" (
    echo update.bat が見つかりません。setup.bat と同じ場所に置いてください。
    goto :error
)
call "%BOOT%update.bat" nopause || goto :error

echo.
echo 完了しました。run.bat で起動できます。
pause

REM ===== 最後に自分自身 (setup.bat) を削除 =====
(goto) 2>nul & del "%~f0"
exit /b 0

:error
echo.
echo エラーが発生したため中断しました。
pause
exit /b 1

REM ===== 以下は PowerShell 本体 (cmd からは実行されない) =====
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
#PS## ---- MEGA ログイン検証 ----
#PS#function B64UDecode($s) {
#PS#  $s = $s.Replace('-', '+').Replace('_', '/')
#PS#  switch ($s.Length % 4) { 2 { $s += '==' } 3 { $s += '=' } }
#PS#  return [Convert]::FromBase64String($s)
#PS#}
#PS#function B64UEncode([byte[]]$b) { [Convert]::ToBase64String($b).TrimEnd('=').Replace('+', '-').Replace('/', '_') }
#PS#function MegaCall($body) {
#PS#  $id = Get-Random -Maximum 1000000000
#PS#  $json = ConvertTo-Json -InputObject @($body) -Compress
#PS#  $r = Invoke-RestMethod -Method Post -Uri "https://g.api.mega.co.nz/cs?id=$id" -Body $json -ContentType 'application/json' -TimeoutSec 20
#PS#  return @($r)[0]
#PS#}
#PS#function Test-Mega($email, $pw) {
#PS#  try {
#PS#    $r = MegaCall @{ a = 'us0'; user = $email.ToLower() }
#PS#    if ($r -is [int] -or $r -is [long]) {
#PS#      if ($r -eq -9) { return 'invalid' }
#PS#      return "error: API code $r"
#PS#    }
#PS#    if ($r.v -ne 2) { return 'unsupported' }   # 旧形式(v1)アカウントは未対応
#PS#    $salt = B64UDecode $r.s
#PS#    $kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes([Text.Encoding]::UTF8.GetBytes($pw), $salt, 100000, [Security.Cryptography.HashAlgorithmName]::SHA512)
#PS#    $key = $kdf.GetBytes(32)
#PS#    $uh = B64UEncode ($key[16..31])
#PS#    $r2 = MegaCall @{ a = 'us'; user = $email.ToLower(); uh = $uh }
#PS#    if ($r2 -is [int] -or $r2 -is [long]) {
#PS#      switch ($r2) {
#PS#        -9  { return 'invalid' }
#PS#        -26 { return '2fa' }
#PS#        -16 { return 'error: アカウントがブロックされています' }
#PS#        default { return "error: API code $r2" }
#PS#      }
#PS#    }
#PS#    return 'ok'
#PS#  } catch {
#PS#    return 'error: ' + $_.Exception.Message
#PS#  }
#PS#}
#PS#
#PS## ---- CivitAI ----
#PS#while ($true) {
#PS#  $tp = ToPlain (Read-Host 'CivitAI トークン' -AsSecureString)
#PS#  Write-Host 'CivitAI トークンを確認中...'
#PS#  $res = Test-Civitai $tp
#PS#  if ($res -eq 'ok') { Write-Host 'CivitAI トークン: OK'; break }
#PS#  if ($res -eq 'invalid') { Write-Host 'CivitAI トークンが無効です。もう一度入力してください。'; continue }
#PS#  Write-Host "CivitAI トークンを確認できませんでした ($res)"
#PS#  if (AskYN 'このまま登録しますか') { break }
#PS#}
#PS#
#PS## ---- MEGA ----
#PS#while ($true) {
#PS#  $e = (Read-Host 'MEGA メールアドレス').Trim()
#PS#  $pp = ToPlain (Read-Host 'MEGA パスワード' -AsSecureString)
#PS#  Write-Host 'MEGA アカウントを確認中...'
#PS#  $res = Test-Mega $e $pp
#PS#  if ($res -eq 'ok') { Write-Host 'MEGA ログイン: OK'; break }
#PS#  if ($res -eq 'invalid') { Write-Host 'メールアドレスまたはパスワードが正しくありません。もう一度入力してください。'; continue }
#PS#  if ($res -eq '2fa') {
#PS#    Write-Host 'MEGA: 2段階認証が有効なアカウントです (メール/パスワードの検証はできません)。'
#PS#    if (AskYN 'このまま登録しますか') { break } else { continue }
#PS#  }
#PS#  if ($res -eq 'unsupported') {
#PS#    Write-Host 'MEGA: 旧形式のアカウントのため、自動検証できません。'
#PS#  } else {
#PS#    Write-Host "MEGA を確認できませんでした ($res)"
#PS#  }
#PS#  if (AskYN 'このまま登録しますか') { break }
#PS#}
#PS#
#PS## ---- modal secret 登録 ----
#PS#& $vpy -m modal secret create krea2-tokens ('CIVITAI_TOKEN=' + $tp) ('MEGA_EMAIL=' + $e) ('MEGA_PASS=' + $pp) --force
#PS#exit $LASTEXITCODE
