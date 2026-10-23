# pin_cargo <crate dir> <binary>...: builds the crate with Fedora's cargo and rustc, since rustup's sit ahead on a user's PATH and cargo runs whichever rustc PATH finds first, and installs each binary into ~/.local/bin; a failed build names the pin. DOTS_CARGO is the tests' stub.
pin_cargo() {
  local dir=$1 bin cargo=${DOTS_CARGO:-/usr/bin/cargo}
  shift
  log "pin $pin_name: building with $cargo and /usr/bin/rustc"
  RUSTC=/usr/bin/rustc "$cargo" build --release --locked --manifest-path "$dir/Cargo.toml" --target-dir "$pin_tmp/target" || die "pin $pin_name: cargo build failed in ${dir#"$pin_tmp"/}"
  mkdir -p "$HOME/.local/bin"
  for bin; do
    # A rename, not a write over the old file, which a running copy (amx, hub local) still holds open.
    install -m 0755 "$pin_tmp/target/release/$bin" "$HOME/.local/bin/.$bin.new" && mv -f "$HOME/.local/bin/.$bin.new" "$HOME/.local/bin/$bin" || die "pin $pin_name: could not install $bin"
  done
}
