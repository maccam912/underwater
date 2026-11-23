"""Test each pushed checkout and package successful builds separately."""
import json
import os
import re
import subprocess
import sys
import tarfile
import zipfile
from hashlib import sha256
from pathlib import Path


def run(args, cwd):
    subprocess.run([str(x) for x in args], cwd=cwd, check=True)


def stamp_android_version(presets, version, code):
    # Keep original Godot serialization intact, including all other export presets.
    settings = presets.read_text()
    sections = re.split(r"(?m)^(\[preset\.\d+(?:\.options)?\])$", settings)
    for header, body in zip(sections[1::2], sections[2::2]):
        if not re.search(r'(?m)^name="Android"$', body):
            continue
        options = sections.index(header[:-1] + ".options]") + 1
        body = sections[options]
        body, codes = re.subn(r"(?m)^version/code=\d+$", f"version/code={code}", body)
        body, names = re.subn(r'(?m)^version/name="[^"]*"$', f'version/name="{version}"', body)
        if codes != 1 or names != 1:
            raise ValueError("Missing or duplicate version fields in the Android export preset")
        sections[options] = body
        presets.write_text("".join(sections))
        return
    raise ValueError("Missing Android export preset")


def package(checkout, output, sha, index):
    output.mkdir(parents=True)
    engine = os.environ["GODOT_BIN"]
    # Keep the APK upgradeable and expose its source revision in Android settings.
    run_number = int(os.environ["GITHUB_RUN_NUMBER"])
    code = run_number * 4096 + index
    version = f"0.{run_number}.{index + 1}+{sha[:12]}"
    stamp_android_version(checkout / "export_presets.cfg", version, code)
    binary_dir = output.parent / f"{sha}-binaries"
    binary_dir.mkdir()
    linux = binary_dir / "Underwater.x86_64"
    windows = binary_dir / "Underwater.exe"
    apk = output / "Underwater-Android.apk"
    mac = output / "Underwater-macOS.zip"
    for preset, file in [("Linux", linux), ("Windows", windows), ("macOS", mac), ("Android", apk)]:
        run([engine, "--headless", "--export-release", preset, file], checkout)
        if not file.exists() or file.stat().st_size < 100_000:
            raise ValueError(f"Incomplete {preset} export")
    linux.chmod(0o755)
    run([linux, "--headless", "--quit-after", "5"], binary_dir)
    tools = Path(os.environ["ANDROID_HOME"]) / "build-tools" / "36.0.0"
    run([tools / "apksigner", "verify", "--verbose", apk], checkout)
    metadata = subprocess.check_output([tools / "aapt", "dump", "badging", apk], text=True)
    expected = ("name='dev.maccam912.underwater'", f"versionCode='{code}'", f"versionName='{version}'")
    if not all(field in metadata for field in expected) or "application-debuggable" in metadata:
        raise ValueError("Unexpected APK package, version or debuggable flag")
    with zipfile.ZipFile(mac) as bundle:
        if not any(".app/Contents/MacOS/" in n and not n.endswith("/") for n in bundle.namelist()) or bundle.testzip():
            raise ValueError("Invalid macOS app bundle")
    with zipfile.ZipFile(output / "Underwater-Windows-x64.zip", "w", zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
        bundle.write(windows, windows.name)
    with tarfile.open(output / "Underwater-Linux-x64.tar.gz", "w:gz", compresslevel=6) as bundle:
        bundle.add(linux, arcname=linux.name)
    records = []
    for file in sorted(output.iterdir()):
        with file.open("rb") as asset:
            digest = sha256()
            for block in iter(lambda: asset.read(1024 * 1024), b""):
                digest.update(block)
        records.append(f"{digest.hexdigest()}  {file.name}")
    (output / "SHA256SUMS.txt").write_text("\n".join(records) + "\n")


def main():
    phase = sys.argv[1]
    workspace = Path.cwd()
    staging = Path(os.environ["RUNNER_TEMP"]) / "commit-builds"
    staging.mkdir(exist_ok=True)
    verified = staging / "tested"
    verified.mkdir(exist_ok=True)
    failed = []
    for commit in json.loads(os.environ["COMMIT_BATCH"]):
        sha = commit["sha"]
        checkout = staging / sha
        print(f"::group::{phase} {sha}", flush=True)
        try:
            if phase == "test":
                # Hydrate the detached revision too: some media may only exist
                # in intermediate commits of a multi-commit push.
                subprocess.run(["git", "worktree", "add", "--detach", checkout, sha],
                               cwd=workspace, env={**os.environ, "GIT_LFS_SKIP_SMUDGE": "1"}, check=True)
                run(["git", "lfs", "pull", "--include=", "--exclude=", "origin"], checkout)
                run(["git", "lfs", "fsck", sha], checkout)
                engine = os.environ["GODOT_BIN"]
                run([engine, "--headless", "--import", "--path", checkout], checkout)
                run([engine, "--headless", "--fixed-fps", "60", "--path", checkout, "--script", "res://tests/smoke.gd"], checkout)
                (verified / sha).touch()
            elif (verified / sha).exists():
                output = staging / "packages" / sha
                package(checkout, output, sha, commit["index"])
                releases = workspace / "build" / "ci-releases"
                releases.mkdir(exist_ok=True, parents=True)
                output.rename(releases / sha)
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            print(f"::error::{phase} failed for {sha}: {error}", flush=True)
            failed.append(sha)
        finally:
            print("::endgroup::", flush=True)
    return int(bool(failed))


if __name__ == "__main__":
    sys.exit(main())
