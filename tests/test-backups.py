"""Linux regression checks; no Docker daemon or cloud credentials required."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


source = Path(__file__).resolve().parents[1] / "scripts"
with tempfile.TemporaryDirectory(prefix="kartochki-backup-test-") as directory:
    app = Path(directory)
    (app / "bin").mkdir()
    complete = app / "backups/complete"
    complete.mkdir(parents=True)
    for name in ("backup-postgres.sh", "backup-all-to-yandex-disk.sh"):
        shutil.copy(source / name, app / name)
    (app / "rclone.conf").write_text("dummy")
    env = os.environ | {"APP_DIR": directory, "PATH": f"{app / 'bin'}:{os.environ['PATH']}"}
    docker = app / "bin/docker"
    docker.write_text("#!/bin/bash\necho partial\nexit 1\n")
    docker.chmod(0o700)
    old = app / "backups/postgres/kartochki-postgres-old.sql.gz"
    old.parent.mkdir()
    old.write_text("keep")
    os.utime(old, (0, 0))
    result = subprocess.run(["bash", str(app / "backup-postgres.sh")], env=env, capture_output=True)
    assert result.returncode != 0
    assert list(old.parent.iterdir()) == [old], "Failed dump was published or old dump was pruned"
    print("PASS: failed pg_dump leaves no partial backup and preserves old dumps")

    docker.write_text('''#!/bin/bash
case "$*" in
  *'exec -T postgres'*) echo 'SELECT 1;' ;;
  *'exec -T backend'*) tar -czf - --files-from /dev/null ;;
  *'images --format json'*) echo '[]' ;;
  *) exit 2 ;;
esac
''')
    marker = complete / "last-success"
    marker.write_text("previous-success")
    old_archive = complete / "kartochki-complete-old.tar.gz"
    old_archive.write_text("keep")
    os.utime(old_archive, (0, 0))
    rclone = app / "bin/rclone"
    rclone.write_text('''#!/bin/bash
printf '%s\n' "$*" >> "$APP_DIR/rclone-calls"
exit 1
''')
    rclone.chmod(0o700)
    result = subprocess.run(["bash", str(app / "backup-all-to-yandex-disk.sh")], env=env, capture_output=True)
    assert result.returncode != 0
    assert marker.read_text() == "previous-success" and old_archive.exists()
    assert " delete " not in (app / "rclone-calls").read_text()
    assert not list(complete.glob(".staging.*"))
    print("PASS: upload failure preserves success marker and old archives, cleans staging")

    rclone.write_text('''#!/bin/bash
case "$*" in *" cat "*) echo wrong-remote-bytes;; esac
exit 0
''')
    result = subprocess.run(["bash", str(app / "backup-all-to-yandex-disk.sh")], env=env, capture_output=True)
    assert result.returncode != 0 and b"Remote checksum mismatch" in result.stderr
    assert marker.read_text() == "previous-success" and old_archive.exists()
    print("PASS: checksum mismatch fails without advancing success or pruning")

    rclone.write_text('''#!/usr/bin/env python3
import os
from pathlib import Path
import shutil
import sys
args = sys.argv[1:]
remote = Path(os.environ["APP_DIR"]) / "mock-remote"
if "copyto" in args:
    index = args.index("copyto")
    target = remote.with_suffix(".sha256") if args[index + 2].endswith(".sha256") else remote
    shutil.copyfile(args[index + 1], target)
elif "cat" in args:
    sys.stdout.buffer.write(remote.read_bytes())
''')
    result = subprocess.run(["bash", str(app / "backup-all-to-yandex-disk.sh")], env=env, capture_output=True)
    assert result.returncode == 0, result.stderr.decode()
    assert "kartochki-online/complete/kartochki-complete-" in marker.read_text()
    assert (app / "mock-remote.sha256").exists()
    assert not old_archive.exists(), "Retention should run after verified upload"
    assert not list(complete.glob(".staging.*"))
    print("PASS: verified upload publishes checksum and success marker, then applies retention")
