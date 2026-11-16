#!/usr/bin/env bash
# Export all workflows as separate JSON files and commit them to a local Git repo (./workflow-export).
# If that repo has an "origin" remote, the commit is pushed too. Credentials are NOT exported.
# Use a PRIVATE repository: workflows can contain hard-coded values you would not want public.
set -euo pipefail

cd "$(dirname "$0")/.."

EXPORT_DIR="./workflow-export"
CONTAINER_DIR="/home/node/.n8n/workflow-export"

echo "Exporting workflows inside the n8n container..."
docker compose exec -T -u node n8n sh -c "rm -rf '$CONTAINER_DIR' && mkdir -p '$CONTAINER_DIR'"
docker compose exec -T -u node n8n n8n export:workflow --backup --output="$CONTAINER_DIR/"

echo "Copying files to $EXPORT_DIR/workflows ..."
mkdir -p "$EXPORT_DIR"
rm -rf "$EXPORT_DIR/workflows"
mkdir -p "$EXPORT_DIR/workflows"
docker compose cp "n8n:$CONTAINER_DIR/." "$EXPORT_DIR/workflows/"

cd "$EXPORT_DIR"
[ -d .git ] || git init -q
git add -A
if git diff --cached --quiet; then
  echo "No workflow changes since the last export."
else
  git commit -q -m "Workflow export $(date +%F_%H%M)"
  echo "Committed changes."
fi

if git remote get-url origin >/dev/null 2>&1; then
  git push -q origin HEAD
  echo "Pushed to origin."
else
  echo "No remote set. Add one with: git -C workflow-export remote add origin <private-repo-url>"
fi
