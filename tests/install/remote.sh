#!/usr/bin/env bash
# Runs the install test on another machine over ssh, from a bundle of the current branch, and fails if that host's own package set changed.
set -uo pipefail
{
host=${1:?usage: tests/install/remote.sh <ssh host>}
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
branch=$(git -C "$here" symbolic-ref --short -q HEAD) || { echo "FAIL: HEAD is detached, check out a branch" >&2; exit 1; }
work=.cache/dots-install-test
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

git -C "$here" bundle create -q "$tmp/repo.bundle" "$branch" || { echo "FAIL: could not bundle $branch"; exit 1; }
# ssh lands in the host's login shell, which may be fish, so the remote side is a bash file run as `bash file`.
cat >"$tmp/run.sh" <<EOF
set -uo pipefail
before=\$(rpm -qa | sort)
rm -rf ~/$work/repo
git clone -q --branch "$branch" ~/$work/repo.bundle ~/$work/repo || { echo "FAIL: could not clone the bundle"; exit 1; }
~/$work/repo/tests/install/run.sh
rc=\$?
after=\$(rpm -qa | sort)
if [ "\$before" = "\$after" ]; then
  echo "PASS: the host's rpm -qa is the same before and after (\$(wc -l <<<"\$after") packages)"
else
  echo "FAIL: the host's rpm -qa changed:"
  diff <(echo "\$before") <(echo "\$after")
  rc=1
fi
exit \$rc
EOF
ssh -o BatchMode=yes "$host" "mkdir -p ~/$work" || { echo "FAIL: cannot reach $host"; exit 1; }
scp -q "$tmp/repo.bundle" "$tmp/run.sh" "$host:$work/" || { echo "FAIL: could not copy to $host"; exit 1; }
ssh -o BatchMode=yes "$host" "bash ~/$work/run.sh"
exit
}
