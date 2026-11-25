@echo off
setlocal
chcp 65001 >nul
set "BOOT=%~dp0"
for %%I in ("%~dp0..") do set "ROOT=%%~fI\"
set "ENGINE=%ROOT%engine"
set "EXT=%ROOT%extentions"
set "REPO_URL=https://github.com/86har/modal-app"
set "TMP_REPO=%ENGINE%\_repo"
cd /d "%BOOT%"

if exist "%BOOT%update.bat.new" del "%BOOT%update.bat.new" >nul 2>&1

if not exist "%ENGINE%" (
    echo engine フォルダがありません。先に setup.bat を実行してください。
    goto :error
)

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

set "VPY=%ENGINE%\venv\Scripts\python.exe"
if not exist "%VPY%" set "VPY=py -3"
powershell -NoProfile -Command "$t=[IO.File]::ReadAllText('%~f0',[Text.Encoding]::UTF8); $i=$t.IndexOf('#PY_'+'BEGIN'); [IO.File]::WriteAllText('%ENGINE%\_patch.py',$t.Substring($i),(New-Object Text.UTF8Encoding($false)))" || goto :error

%VPY% "%ENGINE%\_patch.py" place "%ENGINE%" "%TMP_REPO%" "%EXT%"
if errorlevel 1 goto :place_failed

%VPY% "%ENGINE%\_patch.py" runner "%ROOT:~0,-1%" "%BOOT:~0,-1%" "%TMP_REPO%"
if errorlevel 1 goto :place_failed
rmdir /s /q "%TMP_REPO%"

%VPY% "%ENGINE%\_patch.py" patch "%ENGINE%"
set "PATCH_RC=%errorlevel%"
del "%ENGINE%\_patch.py" >nul 2>&1
if not "%PATCH_RC%"=="0" goto :error

for /f "usebackq delims=" %%S in (`powershell -NoProfile -Command "try { (Invoke-RestMethod -Uri 'https://api.github.com/repos/86har/modal-app/commits/HEAD' -Headers @{Accept='application/vnd.github.sha'} -TimeoutSec 5).ToString().Trim() } catch { '' }"`) do >"%BOOT%repo_sha.txt" echo %%S

echo.
echo 更新が完了しました。
if /i not "%~1"=="nopause" pause

if exist "%BOOT%update.bat.new" (
    (goto) 2>nul & move /y "%BOOT%update.bat.new" "%~f0" >nul
)
exit /b 0

:download_zip
powershell -NoProfile -Command "try { Invoke-WebRequest '%REPO_URL%/archive/refs/heads/%1.zip' -OutFile '%ENGINE%\repo.zip' -ErrorAction Stop; Expand-Archive '%ENGINE%\repo.zip' -DestinationPath '%ENGINE%\_zip_tmp' -Force; $d=(Get-ChildItem '%ENGINE%\_zip_tmp' -Directory | Select-Object -First 1).FullName; Move-Item $d '%TMP_REPO%'; exit 0 } catch { Write-Host $_; exit 1 }"
if exist "%ENGINE%\repo.zip" del "%ENGINE%\repo.zip"
if exist "%ENGINE%\_zip_tmp" rmdir /s /q "%ENGINE%\_zip_tmp"
exit /b

:place_failed
del "%ENGINE%\_patch.py" >nul 2>&1

:error
echo.
echo エラーが発生したため中断しました。
pause
exit /b 1

#PY_BEGIN
import os
import re
import shutil
import sys
from pathlib import Path


LOADER = '''import json
import os
from pathlib import Path

def _load_config():
    """config.json を探して読み込む。KREA_CONFIG 環境変数を優先し、
    無ければこのファイルの親フォルダを順にさかのぼって探す。"""
    candidates = []
    env = os.environ.get("KREA_CONFIG")
    if env:
        candidates.append(Path(env))
    for p in Path(__file__).resolve().parents:
        candidates += [p / "boot" / "config.json", p / "config.json"]
    for path in candidates:
        if path.is_file():
            try:
                return json.loads(path.read_text(encoding="utf-8-sig")), path.parent
            except Exception as e:
                print(f"[config] 読み込みに失敗しました: {path}: {e}")
    return {}, None

_cfg, _cfg_dir = _load_config()
'''

WATCH_BLOCK = LOADER + '''
_watch = os.path.expandvars(os.path.expanduser(
    _cfg.get("WATCH_DIR") or str(Path.home() / "Downloads" / "outputs")
))
if not os.path.isabs(_watch) and _cfg_dir:
    _watch = str(_cfg_dir / _watch)   # 相対パスは config.json のある場所が基準
WATCH_DIR = _watch
'''

GPU_BLOCK = LOADER + '''
GPU = _cfg.get("GPU") or "A10"
'''

OLD_CHECK = '''    if not os.path.isdir(WATCH_DIR):
        print(f"[viewer] フォルダが見つかりません: {WATCH_DIR}")
        sys.exit(1)
'''
NEW_CHECK = '''    os.makedirs(WATCH_DIR, exist_ok=True)
    print(f"[viewer] 監視フォルダ: {WATCH_DIR}")
'''


def patch_viewer(text):
    text, n = re.subn(r"^WATCH_DIR\s*=.*$", lambda m: WATCH_BLOCK.rstrip("\n"), text, count=1, flags=re.M)
    if n == 0:
        return None
    return text.replace(OLD_CHECK, NEW_CHECK)


def patch_modal_app(text):
    text, n = re.subn(r"^GPU\s*=\s*[\"'][^\"']*[\"'].*$", lambda m: GPU_BLOCK.rstrip("\n"), text, count=1, flags=re.M)
    return text if n else None


VIEWER_PYTHON_FUNC = '''def _viewer_python():
    # コンソールを持たない pythonw.exe があればそれを使う(空のウィンドウを出さない)
    if os.name == "nt":
        pyw = Path(sys.executable).with_name("pythonw.exe")
        if pyw.exists():
            return str(pyw)
    return sys.executable

'''


def patch_gen(text):
    if "def launch_viewer" not in text or "[sys.executable, str(VIEWER_PY)]" not in text:
        return None
    text = text.replace("subprocess.DETACHED_PROCESS", "subprocess.CREATE_NO_WINDOW")
    text = text.replace("[sys.executable, str(VIEWER_PY)]", "[_viewer_python(), str(VIEWER_PY)]")
    return text.replace("def launch_viewer", VIEWER_PYTHON_FUNC + "def launch_viewer", 1)


TARGETS = [
    ("viewer.py", patch_viewer, lambda t: "_load_config" in t),
    ("modal_app.py", patch_modal_app, lambda t: "_load_config" in t),
    ("gen.py", patch_gen, lambda t: "_viewer_python" in t),
]

def do_patch(ENGINE):
    status = 0
    for name, func, is_applied in TARGETS:
        paths = [p for p in ENGINE.rglob(name) if "venv" not in p.parts]
        if not paths:
            print(f"[patch] {name} が見つかりません")
            status = 1
            continue
        for path in paths:
            raw = path.read_bytes().decode("utf-8-sig")
            crlf = "\r\n" in raw
            text = raw.replace("\r\n", "\n")
            if is_applied(text):
                print(f"[patch] 適用済み: {path}")
                continue
            new = func(text)
            if new is None:
                print(f"[patch] 書き換え箇所が見つかりません(スキップ): {path}")
                status = 1
                continue
            if crlf:
                new = new.replace("\n", "\r\n")
            path.write_bytes(new.encode("utf-8"))
            print(f"[patch] パッチを適用しました: {path}")

    if status:
        print("[patch] 一部のパッチを適用できませんでしたが、続行します(既に修正済みの可能性があります)")
    return 0


ALWAYS_IGNORE = {".git", "__pycache__", "venv"}
TOP_IGNORE = {"engine", "extention", "extension", "_repo", "config.json",
              "setup.bat", "update.bat", "run.bat", "deploy_and_run.bat", "runner"}


def shallowest(root, want_dir, names):
    best, best_depth = None, None
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in ALWAYS_IGNORE]
        depth = len(Path(dirpath).relative_to(root).parts)
        found = [Path(dirpath) / n for n in (dirnames if want_dir else filenames) if n in names]
        if found and (best_depth is None or depth < best_depth):
            best, best_depth = found[0], depth
    return best


def copy_tree(src, dst, top_ignore=()):
    dst.mkdir(parents=True, exist_ok=True)
    for item in src.iterdir():
        if item.name in ALWAYS_IGNORE or item.name in top_ignore:
            continue
        target = dst / item.name
        if item.is_dir():
            copy_tree(item, target)
        else:
            if item.name.startswith("secrets") and item.suffix == ".json" and target.exists():
                continue
            shutil.copy2(item, target)


def remove(path):
    if path.is_dir():
        shutil.rmtree(path)
    elif path.exists():
        path.unlink()
    else:
        return False
    print(f"[place] 重複を削除しました: {path}")
    return True


def do_place(engine, repo, ext_dst):
    gen = repo / "modal" / "gen.py"
    if not gen.is_file():
        gen = shallowest(repo, False, {"gen.py"})
    if gen is None:
        print("[place] リポジトリ内に gen.py が見つかりません")
        return 1
    src_modal = gen.parent
    ignore = set(TOP_IGNORE)
    if src_modal == repo:
        ignore.add("modal")
    copy_tree(src_modal, engine / "modal", ignore)
    print(f"[place] {src_modal.relative_to(repo) if src_modal != repo else '(リポジトリ直下)'} -> engine\\modal")

    ext = shallowest(repo, True, {"extention", "extension"})
    if ext is None:
        print("[place] extention フォルダが見つかりません(スキップ)")
    else:
        copy_tree(ext, ext_dst)
        print(f"[place] {ext.relative_to(repo)} -> {ext_dst}")

    for rel in ("gen.py", "modal_app.py", "flask", "extention", "extension",
                "modal/modal", "modal/extention", "modal/extension"):
        remove(engine / rel)
    for rel in ("output_images", "output_prompts"):
        d = engine / rel
        if d.is_dir() and all(f.name == ".gitkeep" for f in d.rglob("*") if f.is_file()):
            remove(d)
    return 0


def do_runner(root, boot, repo):
    d = shallowest(repo, True, {"runner"})
    if d is None:
        print("[runner] runner フォルダが見つかりません(スキップ)")
        return 0
    dests = {"run.bat": root, "update.bat": boot,
             "setup.bat": boot, "deploy_and_run.bat": boot}
    for name, folder in dests.items():
        src = d / name
        if not src.is_file():
            print(f"[runner] {name} がありません(スキップ)")
            continue
        if name == "setup.bat" and os.environ.get("KREA_IN_SETUP"):
            print("[runner] setup.bat は実行中のためスキップします")
            continue
        data = src.read_bytes().decode("utf-8-sig").replace("\r\n", "\n").replace("\n", "\r\n").encode("utf-8")
        cur = folder / name
        if cur.is_file() and cur.read_bytes() == data:
            print(f"[runner] {name} は最新です")
            continue
        dst = folder / ("update.bat.new" if name == "update.bat" else name)
        dst.write_bytes(data)
        print(f"[runner] {name} を更新しました")
    old = boot / "run.bat"
    if old.is_file():
        old.unlink()
        print("[runner] boot\\run.bat(旧配置)を削除しました")
    return 0


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "place":
        sys.exit(do_place(Path(sys.argv[2]), Path(sys.argv[3]), Path(sys.argv[4])))
    elif mode == "runner":
        sys.exit(do_runner(Path(sys.argv[2]), Path(sys.argv[3]), Path(sys.argv[4])))
    elif mode == "patch":
        sys.exit(do_patch(Path(sys.argv[2])))
