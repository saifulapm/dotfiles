# nested niri running this checkout's shell on its own session bus
dev:
    bin/dots-dev

# fails past 5 s, so the fast suite stays fast
test:
    timeout 5 node --test 'shell/lib/**/*.test.mjs'

# checks that each open a nested niri for a few seconds
test-dev:
    tests/dev/run.sh

# speed budgets against a fresh nested session
bench:
    bin/dots-bench

# dots install twice in a fresh fedora:44 container
test-install:
    tests/install/run.sh
