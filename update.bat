@echo off
setlocal
chcp 65001 >nul
set "ROOT=%~dp0"
set "ENGINE=%ROOT%engine"
set "REPO_URL=https://github.com/86har/modal-app"
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

REM ===== 2. 配置 (engine\modal / engine\extention) とパッチ適用 =====
REM リポジトリ内の構成が違っても、gen.py のあるフォルダを engine\modal へ、
REM extention フォルダを engine\extention へ置き、重複したファイルは整理します。
REM venv・config.json・secrets*.json には触れません。
set "VPY=%ENGINE%\venv\Scripts\python.exe"
if not exist "%VPY%" set "VPY=py -3"
powershell -NoProfile -Command "$t=[IO.File]::ReadAllText('%~f0',[Text.Encoding]::UTF8); $i=$t.IndexOf('#PY_'+'BEGIN'); [IO.File]::WriteAllText('%ENGINE%\_patch.py',$t.Substring($i),(New-Object Text.UTF8Encoding($false)))" || goto :error

%VPY% "%ENGINE%\_patch.py" place "%ENGINE%" "%TMP_REPO%"
if errorlevel 1 goto :place_failed

REM runner フォルダの bat (run / setup / deploy_and_run / update) を ROOT へ上書き
%VPY% "%ENGINE%\_patch.py" runner "%ROOT:~0,-1%" "%TMP_REPO%"
if errorlevel 1 goto :place_failed
rmdir /s /q "%TMP_REPO%"

REM ===== 3. config.json を参照するようにパッチを適用 =====
%VPY% "%ENGINE%\_patch.py" patch "%ENGINE%"
set "PATCH_RC=%errorlevel%"
del "%ENGINE%\_patch.py" >nul 2>&1
if not "%PATCH_RC%"=="0" goto :error

echo.
echo 更新が完了しました。
if /i not "%~1"=="nopause" pause

REM 実行中の update.bat 自身は直接上書きできないため、終了と同時に差し替える
if exist "%ROOT%update.bat.new" (
    (goto) 2>nul & move /y "%ROOT%update.bat.new" "%~f0" >nul
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
# update.bat から自動展開されるパッチスクリプト(何度実行しても同じ結果になります)
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
    candidates += [p / "config.json" for p in Path(__file__).resolve().parents]
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
    # viewer.py を別プロセスで起動するとき、空のコンソールウィンドウが出ないようにする
    if "def launch_viewer" not in text or "[sys.executable, str(VIEWER_PY)]" not in text:
        return None
    text = text.replace("subprocess.DETACHED_PROCESS", "subprocess.CREATE_NO_WINDOW")
    text = text.replace("[sys.executable, str(VIEWER_PY)]", "[_viewer_python(), str(VIEWER_PY)]")
    return text.replace("def launch_viewer", VIEWER_PYTHON_FUNC + "def launch_viewer", 1)


# (ファイル名, パッチ関数, 適用済みかどうかの判定)
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

    return status


ALWAYS_IGNORE = {".git", "__pycache__", "venv"}
# リポジトリ直下に置かれていても engine\modal へは入れないもの
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
                continue          # 手元の secrets は上書きしない
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


def do_place(engine, repo):
    gen = shallowest(repo, False, {"gen.py"})
    if gen is None:
        print("[place] リポジトリ内に gen.py が見つかりません")
        return 1
    src_modal = gen.parent
    ignore = set(TOP_IGNORE)
    if src_modal == repo:
        ignore.add("modal")       # 直下に gen.py がある場合、内側の modal は重複
    copy_tree(src_modal, engine / "modal", ignore)
    print(f"[place] {src_modal.relative_to(repo) if src_modal != repo else '(リポジトリ直下)'} -> engine\\modal")

    ext = shallowest(repo, True, {"extention", "extension"})
    if ext is None:
        print("[place] extention フォルダが見つかりません(スキップ)")
    else:
        copy_tree(ext, engine / "extention")
        print(f"[place] {ext.relative_to(repo)} -> engine\\extention")

    # 以前の版で engine 直下や modal の中に重複してできたものを整理
    for rel in ("gen.py", "modal_app.py", "flask",
                "modal/modal", "modal/extention", "modal/extension"):
        remove(engine / rel)
    # 旧版で engine 直下にできた空の出力フォルダ(中身がある場合は残す)
    for rel in ("output_images", "output_prompts"):
        d = engine / rel
        if d.is_dir() and all(f.name == ".gitkeep" for f in d.rglob("*") if f.is_file()):
            remove(d)
    return 0


def do_runner(root, repo):
    d = shallowest(repo, True, {"runner"})
    if d is None:
        print("[runner] runner フォルダが見つかりません(スキップ)")
        return 0
    for name in ("run.bat", "update.bat", "setup.bat", "deploy_and_run.bat"):
        src = d / name
        if not src.is_file():
            print(f"[runner] {name} がありません(スキップ)")
            continue
        text = src.read_bytes().decode("utf-8-sig").replace("\r\n", "\n").replace("\n", "\r\n")
        # update.bat は実行中なので .new として置き、終了時に差し替える
        dst = root / ("update.bat.new" if name == "update.bat" else name)
        dst.write_bytes(text.encode("utf-8"))
        print(f"[runner] {name} を更新しました")
    return 0


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "place":
        sys.exit(do_place(Path(sys.argv[2]), Path(sys.argv[3])))
    elif mode == "runner":
        sys.exit(do_runner(Path(sys.argv[2]), Path(sys.argv[3])))
    elif mode == "patch":
        sys.exit(do_patch(Path(sys.argv[2])))
