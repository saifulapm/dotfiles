# nested niri running this checkout's shell on its own session bus
dev:
    bin/dots-dev

# fails past 5 s, so the fast suite stays fast
test:
    timeout 5 node --test 'shell/lib/**/*.test.mjs'

# dots sync between two scratch machines over a local alias remote
test-sync:
    #!/usr/bin/env bash
    # Every run works on scratch homes, so the real ~/.ssh must hash the same after it as before.
    ssh_tree() { find ~/.ssh -type f -print0 2>/dev/null | sort -z | xargs -0r sha256sum | sha256sum; }
    before=$(ssh_tree)
    node --test 'tests/sync/*.test.mjs'
    rc=$?
    [ "$(ssh_tree)" = "$before" ] || { echo "the real ~/.ssh changed during the sync tests" >&2; exit 1; }
    exit $rc

# dots subcommands and the home configs, on scratch homes with stubbed remotes
test-dots:
    node --test 'tests/dots/*.test.mjs' 'tests/home/*.test.mjs'

# checks that each open a nested niri for a few seconds
test-dev:
    tests/dev/run.sh

# speed budgets against a fresh nested session
bench:
    bin/dots-bench

# 30 minutes of simulated use in a nested session; fails when the shell's RSS drifts over 5 MiB
soak:
    bin/dots-soak

# dots install twice in a fresh fedora:44 container
test-install:
    tests/install/run.sh

# dots install then dots cutover twice on a v1 machine in a container with a live user manager
test-cutover:
    tests/cutover/run.sh

# the install test on another machine (the NUC for x86_64), whose own packages must not change
test-install-remote host:
    tests/install/remote.sh {{host}}
