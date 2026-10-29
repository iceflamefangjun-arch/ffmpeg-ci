"""Apply the actual FFmpeg patch chain to temporary sources.

This check does not configure or compile anything and does not change the source
cache. Run under WSL with --ffmpeg-source pointing to the existing upstream Git
repository.
"""

import argparse
import io
from pathlib import Path
import re
import subprocess
import tarfile
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def archive(source, revision, destination):
    data = subprocess.check_output(["git", "-C", str(source), "archive", revision])
    with tarfile.open(fileobj=io.BytesIO(data)) as files:
        files.extractall(destination, filter="data")


def apply(patch, destination, strict=False):
    # Keep b.sh's default fuzz for unchanged historical patches; changed patches
    # must apply with exact context. Do not rewrite unrelated patches here.
    result = subprocess.run(["patch", "--batch", "--fuzz=0" if strict else "--fuzz=2", "-p1"],
                            input=patch.read_bytes().replace(b"\r\n", b"\n"),
                            cwd=destination, capture_output=True)
    if result.returncode:
        raise RuntimeError(f"{patch.name}:\n" + result.stdout.decode("utf-8", "replace")
                           + result.stderr.decode("utf-8", "replace"))
    print("PASS", patch.name, flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ffmpeg-source", type=Path, required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="disc-patches-") as directory:
        ffmpeg = Path(directory) / "ffmpeg"
        ffmpeg.mkdir()
        archive(args.ffmpeg_source, "n7.1.1", ffmpeg)
        script = (ROOT / "ffmpeg/b.sh").read_text(encoding="utf-8")
        patches = re.findall(r'^patch .*<\$\{CURRENTPATH\}/([^\s]+\.patch)', script, re.M)
        if not patches:
            raise RuntimeError("No active FFmpeg patches found in b.sh")
        for name in patches:
            apply(ROOT / "ffmpeg" / name, ffmpeg, strict=name.startswith(("0029-", "0031-", "0032-")))
    print("All patches applied cleanly; no compilation performed.")
