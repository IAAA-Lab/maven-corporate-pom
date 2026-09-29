#!/bin/sh
# Dry-run GitLab pipeline creation for gitlab-ci.example.yml.
# Does not run jobs or publish packages.
set -eu

: "${CI_API_V4_URL:?Set CI_API_V4_URL, for example https://gitlab.example/api/v4}"
: "${CI_PROJECT_ID:?Set CI_PROJECT_ID to a disposable GitLab project id}"
: "${GITLAB_TOKEN:?Set GITLAB_TOKEN without committing it}"

command -v curl >/dev/null
command -v python3 >/dev/null

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CONFIG="$ROOT/gitlab-ci.example.yml"
REF=${DRY_RUN_REF:-}

python3 - "$CONFIG" "$CI_API_V4_URL" "$CI_PROJECT_ID" "$GITLAB_TOKEN" "$REF" <<'PY'
import json
import os
import sys
import urllib.error
import urllib.request

config_path, api, project_id, token, ref = sys.argv[1:]
with open(config_path, "r") as handle:
    content = handle.read()

body = {
    "content": content,
    "dry_run": True,
    "include_jobs": True,
}
if ref:
    body["ref"] = ref

request = urllib.request.Request(
    api.rstrip("/") + "/projects/" + project_id + "/ci/lint",
    data=json.dumps(body).encode("utf-8"),
    headers={
        "PRIVATE-TOKEN": token,
        "Content-Type": "application/json",
    },
    method="POST",
)

try:
    with urllib.request.urlopen(request) as response:
        payload = json.loads(response.read().decode("utf-8"))
except urllib.error.HTTPError as error:
    sys.stderr.write(error.read().decode("utf-8") + "\n")
    raise SystemExit(error.code)

json.dump(payload, sys.stdout, indent=2)
sys.stdout.write("\n")
if not payload.get("valid"):
    raise SystemExit("GitLab CI configuration is not valid")
print("GitLab CI configuration is valid")
if payload.get("jobs"):
    names = [job.get("name") for job in payload["jobs"]]
    print("Jobs: " + ", ".join(names))
PY
