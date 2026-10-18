set -euo pipefail
log() { echo "dots: $*"; }
die() {
  echo "dots: $*" >&2
  exit 1
}
# dots install refreshed sudo at its start, so a root command here never prompts.
root() { sudo -n "$@"; }
