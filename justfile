# nested niri running this checkout's shell on its own session bus
dev:
    bin/dots-dev

test:
    node --test 'shell/lib/**/*.test.mjs'

# speed budgets against a fresh nested session
bench:
    bin/dots-bench
