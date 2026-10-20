{{- /* Called as (dict "chezmoi" .chezmoi "name" "<pin>"): sets the pin's values for this arch and defines pin_fetch and pin_done. */ -}}
{{- $versions := include (joinPath .chezmoi.workingTree "versions.toml") | fromToml -}}
{{- $arch := .chezmoi.arch | replace "arm64" "aarch64" | replace "amd64" "x86_64" -}}
{{- $pin := dict -}}
{{- range $versions.pin }}{{ if eq .name $.name }}{{ $pin = . }}{{ end }}{{ end -}}
{{- if not $pin }}{{ fail (printf "versions.toml has no pin %s" .name) }}{{ end -}}
{{- $url := $pin.url -}}
{{- $sha := $pin.sha256 -}}
{{- if kindIs "map" $url }}{{ $url = index $pin.url $arch }}{{ $sha = index $pin.sha256 $arch }}{{ end -}}
{{- if not $url }}{{ fail (printf "pin %s has no url for %s" .name $arch) }}{{ end -}}
pin_name={{ $pin.name | quote }}
pin_version={{ $pin.version | quote }}
pin_url={{ $url | replace "{version}" $pin.version | quote }}
pin_sha256={{ $sha | quote }}
# On disk, not in /tmp: /tmp is a small tmpfs on the Macs and a source build may not fit.
mkdir -p "$HOME/.cache"
pin_tmp=$(mktemp -d -p "$HOME/.cache" dots-pin-XXXXXX)
trap 'rm -rf "$pin_tmp"' EXIT
# pin_fetch: downloads the pin into a temp dir and prints its path; a wrong sha256 stops the install.
pin_fetch() {
  local file=$pin_tmp/${pin_url##*/}
  curl -fsSL -o "$file" "$pin_url" || die "pin $pin_name: could not download $pin_url"
  echo "$pin_sha256  $file" | sha256sum -c --status || die "pin $pin_name: sha256 of $pin_url is not $pin_sha256"
  echo "$file"
}
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
# dots update counts these lines as changed pins.
pin_done() { log "pin $pin_name $pin_version"; }
