shell_dir := justfile_directory() / "shell"
qt6_bin := "/usr/lib64/qt6/bin"

# run the shell against the live session (Ctrl-C to stop)
run:
    qs -p {{ shell_dir }}

# nested niri window running the shell — test without touching the live session
dev:
    niri -c {{ justfile_directory() }}/dev/niri-dev.kdl

# format all QML in place
fmt:
    find {{ shell_dir }} -name '*.qml' -exec {{ qt6_bin }}/qmlformat -i {} +

# benchmarks: cold start, idle RSS, 60s idle CPU, launcher latency
bench:
    bash {{ justfile_directory() }}/bin/bench

# apply dotfiles
apply:
    chezmoi apply

# update dev toolchains: mise-managed tools (node/deno) + rust via rustup
update:
    mise up
    rustup update

# update EVERYTHING: dnf, dotfiles, prebuilts, source builds, toolchains,
# cargo tools, gh extensions. `just update-all --emacs` adds the Emacs rebuild.
update-all *args:
    bash {{ justfile_directory() }}/bin/update-all {{ args }}
