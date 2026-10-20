# pin_cargo <crate dir> <binary>...: builds the crate with cargo and installs each binary into ~/.local/bin; a failed build names the pin.
pin_cargo() {
  local dir=$1 bin
  shift
  cargo build --release --locked --manifest-path "$dir/Cargo.toml" --target-dir "$pin_tmp/target" || die "pin $pin_name: cargo build failed in ${dir#"$pin_tmp"/}"
  mkdir -p "$HOME/.local/bin"
  for bin; do
    # A rename, not a write over the old file, which a running copy (amx, hub local) still holds open.
    install -m 0755 "$pin_tmp/target/release/$bin" "$HOME/.local/bin/.$bin.new" && mv -f "$HOME/.local/bin/.$bin.new" "$HOME/.local/bin/$bin" || die "pin $pin_name: could not install $bin"
  done
}
