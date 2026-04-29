#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <role> [runner args...]" >&2
  exit 2
fi

role="$1"
shift

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
python_bin="${TEAMBUS_RUNNER_PYTHON:-/home/rdcraze/mcp/teambus/.venv/bin/python}"

export REPO_ROOT="${REPO_ROOT:-$repo_root}"

exec "$python_bin" "$repo_root/scripts/teambus_role_runner.py" \
  --config "$repo_root/runner/roles.json" \
  "$role" \
  "$@"
