# The mobile toolchain on every machine — 2026-09-13

The dactyl engine (github.com/lareysbd/dactyl) has two native hosts, an
Android app and a Swift package, and both were provable only on the MacBook:
Java, the Android SDK and NDK, Gradle, the Rust Android targets and Swift had
been installed there by hand across milestones 2 and 5 (2026-09-02) and never
recorded anywhere but the repo's own `android/setup-toolchain.sh` and a wiki
page. Moving the checkout to the NUC on 2026-09-08 showed the gap: `cargo`
and `node` were there, nothing else was, and the gate's git hooks were not
linked either. This apply-driven install closes it for all three machines.

## What lands, and from where

| piece | version | via |
| --- | --- | --- |
| java-25-openjdk-devel, clang, lld | Fedora's | `packages/manifest.toml`, so the sudo happens in `run_before_00` like every other package |
| Android command-line tools, platform 37, build-tools 37.0.0, NDK 29.0.14206865, adb | pinned | `run_after_56-mobile-toolchain.sh` → `~/Android/Sdk` |
| arm64 aapt2 and zipalign, AGP override | Commit451 platform-tools-37.0.0 | the same script, Macs only, plus a line in `~/.gradle/gradle.properties` |
| Gradle | 9.7.1 | the same script → `~/.local/opt/gradle-9.7.1` |
| Rust targets aarch64- and x86_64-linux-android | rustup's | the same script |
| swiftly, Swift | 1.1.3, 6.3.3 on `--platform fedora39` | the same script → `~/.local/share/swiftly`, `swift` and `swiftc` linked into `~/.local/bin` |
| `ANDROID_HOME`, `platform-tools` on PATH | | `00-env.fish` and `dot_bashrc.d/10-dev.sh` |
| the three git hook stubs | the workflow checkout's | `run_after_46-workflow.sh`, same dev-box rule as its skills |

The versions are the ones dactyl's `android/setup-toolchain.sh` installs and
its CI job uses, on purpose: the two scripts are the same recipe in two
homes, and a local green must mean what a CI green means. When one moves,
move the other. Swift is on `fedora39` because swift.org publishes no newer
Fedora toolchain; it has run on Fedora 44 since the MacBook's hand install.

## What a machine has to do once

Nothing beyond `chezmoi apply`. The dnf line runs with the rest of the
manifest; the SDK, Gradle and Swift steps are user-level and guarded, so a
second apply is a no-op, and `swiftly install` is given
`--post-install-file` so it never reaches for sudo from inside an apply (the
file it would write is empty on a Fedora desktop, and a non-empty one is
printed as a warning to fold into the manifest).

## How to see it worked

```sh
java -version                      # openjdk 25
ls ~/Android/Sdk/ndk               # 29.0.14206865
adb version                        # platform-tools on PATH
swift --version                    # 6.3.3
rustup target list --installed     # the two -linux-android targets
```

And in a dactyl checkout, the two builds that used to need the MacBook:

```sh
cargo build -p engine-android --release && host-android/gradlew -p host-android :app:testDebugUnitTest
cargo build -p engine-ios --release && swift test --package-path host-ios
```
