#!/usr/bin/env bash
# The mobile toolchain the dactyl engine's native hosts build with
# (github.com/lareysbd/dactyl; docs/mobile-toolchain-2026-09-13.md): the
# Android SDK, NDK and build-tools, Gradle for bootstrapping a wrapper, the
# Rust Android targets, and Swift through swiftly. Everything is user-level
# and guarded; the three dnf packages it leans on (java-25-openjdk-devel,
# clang, lld) come from the manifest, so a fresh apply orders itself.
#
# The Android half mirrors dactyl's android/setup-toolchain.sh step for step
# and pins the same versions: that script writes the repo's local.properties,
# this one is what every machine runs first, and dactyl's CI installs the
# same platform, build-tools and NDK, which is why the numbers are not
# "latest". When one moves, move the other.
#
# Swift: swift.org publishes Fedora 39 toolchains and nothing newer, so
# swiftly is told --platform fedora39 on every Fedora here (the MacBook was
# set up that way by hand 2026-09-02 and `swift test` has been green since).
# Only swift and swiftc are linked into ~/.local/bin: swiftly's bin dir also
# proxies clang, lld and lldb, and putting it on PATH would shadow the
# distribution's clang that the Android linker shims run on the Macs.
#
# Warn-not-abort, stdin closed, same as 03-dev-toolchain: an unattended apply
# must neither hang nor stop the scripts after it.
set -uo pipefail
export PATH="$HOME/.cargo/bin:$PATH"
exec </dev/null

warn() { echo "mobile-toolchain: $*" >&2; }

ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
CMDLINE_TOOLS_ZIP=commandlinetools-linux-15859902_latest.zip
CMDLINE_TOOLS_SHA256=4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583
PLATFORM=android-37.0
BUILD_TOOLS=37.0.0
NDK=29.0.14206865
ARM_TOOLS=https://github.com/Commit451/android-arm-build-tools/releases/download/platform-tools-37.0.0
GRADLE=9.7.1
GRADLE_HOME="$HOME/.local/opt/gradle-$GRADLE"
SWIFTLY=1.1.3
SWIFT=6.3.3
SWIFT_PLATFORM=fedora39
SWIFTLY_HOME="$HOME/.local/share/swiftly"

# ------------------------------------------------------------ rust targets
if [ -x "$HOME/.cargo/bin/rustup" ]; then
  "$HOME/.cargo/bin/rustup" target add aarch64-linux-android x86_64-linux-android >/dev/null 2>&1 \
    || warn "rustup target add failed (offline?)"
else
  warn "rustup missing (03-dev-toolchain skipped?) — Android targets not added"
fi

# ---------------------------------------------------------------- android
missing=()
for tool in java clang ld.lld; do
  command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if ((${#missing[@]})); then
  warn "missing ${missing[*]} — the manifest's java-25-openjdk-devel, clang and lld have not landed; skipping the Android SDK until they do"
else
  tools="$ANDROID_HOME/cmdline-tools/latest"
  if [ ! -x "$tools/bin/sdkmanager" ]; then
    tmp=$(mktemp -d)
    if curl -sSfL -o "$tmp/tools.zip" "https://dl.google.com/android/repository/$CMDLINE_TOOLS_ZIP" \
      && echo "$CMDLINE_TOOLS_SHA256  $tmp/tools.zip" | sha256sum -c - >/dev/null \
      && unzip -q "$tmp/tools.zip" -d "$tmp"; then
      mkdir -p "$ANDROID_HOME/cmdline-tools"
      mv "$tmp/cmdline-tools" "$tools" && echo "mobile-toolchain: Android command-line tools installed"
    else
      warn "command-line tools download or checksum failed"
    fi
    rm -rf "$tmp"
  fi
  if [ -x "$tools/bin/sdkmanager" ]; then
    # Guarded on all three directories, so an apply that changes nothing
    # makes no call to Google. sdkmanager is a Java launcher, which is why
    # java is checked above; the `android` binary beside it is x86_64 only.
    if [ ! -d "$ANDROID_HOME/ndk/$NDK" ] || [ ! -d "$ANDROID_HOME/platforms/$PLATFORM" ] || [ ! -d "$ANDROID_HOME/build-tools/$BUILD_TOOLS" ]; then
      # printf finishes before sdkmanager exits, so no SIGPIPE under pipefail.
      printf 'y\n%.0s' $(seq 50) | "$tools/bin/sdkmanager" --licenses >/dev/null 2>&1
      "$tools/bin/sdkmanager" "platforms;$PLATFORM" "build-tools;$BUILD_TOOLS" "ndk;$NDK" >/dev/null 2>&1 \
        && echo "mobile-toolchain: platform $PLATFORM, build-tools $BUILD_TOOLS and NDK $NDK installed" \
        || warn "sdkmanager failed (offline?)"
    fi
  fi
  # Google ships x86_64 build tools only: the Macs swap in arm64 aapt2 and
  # zipalign and point AGP at that aapt2, since AGP otherwise runs the one
  # it fetches from Maven, which cannot run there.
  if [ "$(uname -m)" = aarch64 ] && [ -d "$ANDROID_HOME/build-tools/$BUILD_TOOLS" ]; then
    bt="$ANDROID_HOME/build-tools/$BUILD_TOOLS"
    if ! file "$bt/aapt2" | grep -q aarch64; then
      tmp=$(mktemp -d)
      if (cd "$tmp" && curl -sSfL -O "$ARM_TOOLS/aapt2" -O "$ARM_TOOLS/zipalign" -O "$ARM_TOOLS/SHA256SUMS" \
          && grep -E ' (aapt2|zipalign)$' SHA256SUMS | sha256sum -c - >/dev/null); then
        install -m 755 "$tmp/aapt2" "$tmp/zipalign" "$bt/" && echo "mobile-toolchain: arm64 aapt2 and zipalign swapped in"
      else
        warn "arm64 build tools download or checksum failed"
      fi
      rm -rf "$tmp"
    fi
    mkdir -p "$HOME/.gradle"
    prop="android.aapt2FromMavenOverride=$bt/aapt2"
    grep -qxF "$prop" "$HOME/.gradle/gradle.properties" 2>/dev/null || echo "$prop" >>"$HOME/.gradle/gradle.properties"
  fi
  if [ ! -x "$GRADLE_HOME/bin/gradle" ]; then
    tmp=$(mktemp -d)
    if curl -sSfL -o "$tmp/gradle.zip" "https://services.gradle.org/distributions/gradle-$GRADLE-bin.zip" \
      && echo "$(curl -sSfL "https://services.gradle.org/distributions/gradle-$GRADLE-bin.zip.sha256")  $tmp/gradle.zip" | sha256sum -c - >/dev/null; then
      mkdir -p "$HOME/.local/opt"
      unzip -q "$tmp/gradle.zip" -d "$HOME/.local/opt" && echo "mobile-toolchain: gradle $GRADLE installed"
    else
      warn "gradle download or checksum failed"
    fi
    rm -rf "$tmp"
  fi
fi

# ------------------------------------------------------------------ swift
if [ ! -x "$SWIFTLY_HOME/bin/swiftly" ]; then
  tmp=$(mktemp -d)
  if curl -sSfL -o "$tmp/swiftly.tar.gz" "https://download.swift.org/swiftly/linux/swiftly-$SWIFTLY-$(uname -m).tar.gz" \
    && tar xzf "$tmp/swiftly.tar.gz" -C "$tmp"; then
    # init moves the binary into SWIFTLY_BIN_DIR and writes config.json; the
    # profile is left alone (see the header) and the toolchain comes next,
    # pinned rather than "latest".
    SWIFTLY_HOME_DIR="$SWIFTLY_HOME" SWIFTLY_BIN_DIR="$SWIFTLY_HOME/bin" \
      "$tmp/swiftly" init --platform "$SWIFT_PLATFORM" --skip-install --no-modify-profile --quiet-shell-followup --assume-yes >/dev/null 2>&1 \
      && echo "mobile-toolchain: swiftly $SWIFTLY installed" \
      || warn "swiftly init failed"
  else
    warn "swiftly download failed"
  fi
  rm -rf "$tmp"
fi
if [ -x "$SWIFTLY_HOME/bin/swiftly" ] && [ ! -d "$SWIFTLY_HOME/toolchains/$SWIFT" ]; then
  # --post-install-file: the system packages a toolchain wants are written to
  # a file rather than installed with sudo from inside an apply. Every one of
  # them is on a Fedora desktop already (libicu, sqlite, libxml2, libcurl,
  # libedit, libuuid, python3), so the file comes out empty; a non-empty one
  # is printed for the manifest to pick up.
  post=$(mktemp)
  if SWIFTLY_HOME_DIR="$SWIFTLY_HOME" SWIFTLY_BIN_DIR="$SWIFTLY_HOME/bin" \
      "$SWIFTLY_HOME/bin/swiftly" install "$SWIFT" --use --assume-yes --post-install-file "$post" >/dev/null 2>&1; then
    echo "mobile-toolchain: swift $SWIFT installed"
    [ -s "$post" ] && warn "swift wants system packages this apply did not install — add them to the manifest: $(tr '\n' ' ' <"$post")"
  else
    warn "swift $SWIFT install failed (offline, or no gpg for the signature check?)"
  fi
  rm -f "$post"
fi
if [ -x "$SWIFTLY_HOME/bin/swift" ]; then
  mkdir -p "$HOME/.local/bin"
  for bin in swift swiftc; do
    dest="$HOME/.local/bin/$bin"
    [ "$(readlink "$dest" 2>/dev/null)" = "$SWIFTLY_HOME/bin/$bin" ] && continue
    if [ -L "$dest" ] || [ ! -e "$dest" ]; then
      ln -sfn "$SWIFTLY_HOME/bin/$bin" "$dest" && echo "mobile-toolchain: linked ~/.local/bin/$bin"
    else
      warn "$dest is a real file — leaving it alone"
    fi
  done
fi

exit 0
