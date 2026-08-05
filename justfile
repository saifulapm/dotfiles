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

# benchmarks: cold start, idle RSS, idle CPU, launcher latency (built in step 8)
bench:
    @echo "bench: not implemented yet (step 8)"

# apply dotfiles
apply:
    chezmoi apply
