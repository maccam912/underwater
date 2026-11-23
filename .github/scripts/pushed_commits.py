"""Enumerate every revision in a branch push, including intermediate commits."""
import json
import math
import os
import subprocess
from pathlib import Path

event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
head = os.environ["GITHUB_SHA"]
commits = [head]
if os.environ["GITHUB_EVENT_NAME"] == "push":
    before = event["before"]
    if before != "0" * 40:
        # A force-push can make the old tip unavailable to an ordinary clone.
        if subprocess.run(["git", "cat-file", "-e", before], capture_output=True).returncode:
            subprocess.run(["git", "fetch", "--no-tags", "origin", before], check=True)
        revisions = [f"{before}..{head}"]
    else:
        revisions = [head, "--not", "--tags=build-*"]
    commits = subprocess.check_output(
        ["git", "rev-list", "--topo-order", "--reverse", *revisions], text=True
    ).splitlines() or [head]

# Each matrix job normally tests one commit. Larger pushes share runners while
# leaving room for both native operating systems in GitHub's 256-job matrix.
width = max(1, math.ceil(len(commits) / 128))
batches = []
for start in range(0, len(commits), width):
    batch = [{"sha": sha, "index": start + i} for i, sha in enumerate(commits[start:start + width])]
    batches.append({"label": batch[-1]["sha"][:12], "commits": batch})
with open(os.environ["GITHUB_OUTPUT"], "a") as output:
    print("batches=" + json.dumps(batches, separators=(",", ":")), file=output)
