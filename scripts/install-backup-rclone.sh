#!/usr/bin/env bash
set -euo pipefail
[[ "$EUID" == 0 ]] || { echo 'Run as root' >&2; exit 1; }
# Keep the distro client untouched; only the backup service uses this runtime.
python3 - <<'PY'
import hashlib
import io
import os
from pathlib import Path
import platform
import subprocess
import zipfile

version = "v1.75.2"
architecture = {"x86_64": "amd64", "aarch64": "arm64"}.get(platform.machine())
if not architecture:
    raise SystemExit("Unsupported backup runtime architecture")
target = Path("/usr/local/lib/kartochki-backup/rclone")
if target.exists():
    current = subprocess.check_output([str(target), "version"], text=True).splitlines()[0]
    if current == f"rclone {version}":
        print(f"Backup runtime already installed: {current}")
        raise SystemExit(0)
name = f"rclone-{version}-linux-{architecture}.zip"
url = f"https://downloads.rclone.org/{version}/"

def fetch(resource):
    return subprocess.check_output(["curl", "-fsSL", "--connect-timeout", "10", "--max-time", "90", resource])

manifest = fetch(url + "SHA256SUMS").decode()
expected = next(line.split()[0] for line in manifest.splitlines()
                if line.split() and line.split()[-1].lstrip("*") == name)
data = fetch(url + name)
if hashlib.sha256(data).hexdigest() != expected:
    raise SystemExit("Official rclone archive checksum mismatch")
target.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
temporary = target.with_suffix(".partial")
try:
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        temporary.write_bytes(archive.read(f"rclone-{version}-linux-{architecture}/rclone"))
    temporary.chmod(0o755)
    os.replace(temporary, target)
finally:
    temporary.unlink(missing_ok=True)
print(f"Installed SHA256-verified backup runtime: rclone {version}")
PY
