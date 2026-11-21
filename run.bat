@echo off
chcp 65001 >nul
set "ROOT=%~dp0"
set "ENGINE=%ROOT%engine"
cd /d "%ROOT%"

if not exist "%ENGINE%\venv\Scripts\python.exe" (
    echo 仮想環境が見つかりません。先に setup.bat を実行してください。
    pause
    exit /b 1
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

for %%F in ("%GEN%") do cd /d "%%~dpF"
python "%GEN%" %*

echo.
pause
