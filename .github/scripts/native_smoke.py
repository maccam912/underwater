"""Start each exported desktop package on its native runner and record verified bytes."""
import hashlib
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import zipfile


def digest(archive):
    with archive.open("rb") as stream:
        value = hashlib.sha256()
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
        return value.hexdigest()


def verify_startup(log):
    # Godot can return success even when a GDScript initialization method fails.
    if re.search(r"^(?:SCRIPT ERROR|SHADER ERROR|ERROR|FATAL):", log, re.MULTILINE):
        raise RuntimeError("Godot reported a startup error")
    if re.search(r"ObjectDB instances were leaked at exit", log):
        raise RuntimeError("Godot leaked objects during shutdown")
    if not all(marker in log for marker in ("Godot Engine v", "res://game/dive.")):
        raise RuntimeError("The exported Underwater main scene did not load")


def unpack(archive, temp, system):
    if system == "macos":
        # ditto restores the app bundle's executable bits, symlinks and metadata.
        subprocess.run(["ditto", "-x", "-k", archive, temp], check=True)
        apps = list(temp.glob("*.app"))
        if len(apps) != 1:
            raise ValueError("Expected one macOS app at the root of the archive")
        contents = apps[0] / "Contents"
        with (contents / "Info.plist").open("rb") as info:
            executable = contents / "MacOS" / plistlib.load(info)["CFBundleExecutable"]
        if not os.access(executable, os.X_OK):
            raise ValueError(f"Bundle executable is not runnable: {executable}")
        return executable
    with zipfile.ZipFile(archive) as package:
        package.extractall(temp)
    return temp / "Underwater.exe"


def smoke(release, system):
    name = "Underwater-macOS.zip" if system == "macos" else "Underwater-Windows-x64.zip"
    archive = release / name
    check = f"{digest(archive)}  {name}"
    if check not in (release / "SHA256SUMS.txt").read_text().splitlines():
        raise ValueError(f"Checksum mismatch for {name}")
    with tempfile.TemporaryDirectory() as unpacked:
        temp = Path(unpacked)
        binary = unpack(archive, temp, system)
        log_path = temp / "startup.log"
        proc = subprocess.run([binary, "--headless", "--verbose", "--fixed-fps", "60", "--quit-after", "30", "--log-file", log_path],
                              cwd=temp, capture_output=True, text=True, errors="replace", timeout=90)
        log = log_path.read_text(errors="replace") if log_path.exists() else ""
        try:
            proc.check_returncode()
            verify_startup(log + "\n" + proc.stdout + "\n" + proc.stderr)
        except (RuntimeError, subprocess.CalledProcessError):
            print(proc.stdout + "\n" + proc.stderr + "\n" + log, flush=True)
            raise
    return check


def main():
    system = {"darwin": "macos", "win32": "windows"}[sys.platform]
    releases = sorted(Path("releases").glob("*/SHA256SUMS.txt"))
    if not releases:
        raise RuntimeError("No release packages downloaded")
    failed = False
    for manifest in releases:
        release = manifest.parent
        try:
            check = smoke(release, system)
            receipt = Path("native-passes") / release.name / f"{system}.sha256"
            receipt.parent.mkdir(parents=True, exist_ok=True)
            receipt.write_text(check + "\n", newline="\n")
            print(f"{release.name}: {system} packaged title started successfully", flush=True)
        except (OSError, RuntimeError, ValueError, zipfile.BadZipFile, subprocess.SubprocessError) as error:
            print(f"::error::{system} startup failed for {release.name}: {error}", flush=True)
            failed = True
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
