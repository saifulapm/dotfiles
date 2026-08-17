#!/usr/bin/env bash
# Creates the $HOME directories the configs assume exist. ~/Sites is the
# projects root: fish's `try` scaffolds experiments into ~/Sites/tries,
# `sweep` prunes node_modules/vendor under it, and mise auto-trusts project
# configs inside it (trusted_config_paths in ~/.config/mise/config.toml).
# A script rather than source-state because chezmoi cannot represent an
# empty directory without a .keep file — which symlink mode would render
# as a stray symlink into the repo.
set -euo pipefail

mkdir -p "$HOME/Sites"

# GOBIN (~/.config/go/env homes go there) — pre-created because fish_add_path
# silently skips directories that don't exist yet, leaving GOBIN off PATH
# until a login after the first `go install`.
mkdir -p "$HOME/.local/share/go/bin"

# Mail (packages/manifest.toml: isync, notmuch, msmtp).
#   ~/Mail                     the maildir root, = notmuch's database.path
#   ~/.local/share/hey-mail    the HEY sender-decision databases (screened.db,
#                              thefeed.db, ledger.db, spam.db, bubble.db, …).
#                              NOT in the dotfiles repo on purpose: it is a
#                              list of everyone who emails you, and this repo
#                              is public.
#   ~/.local/state/hey-mail    sync + post-new hook logs and the sync lock
#   ~/.local/state/msmtp       msmtp's logfile, which msmtp will NOT create
#                              itself — it fails the send instead
# ~/Mail/icloud specifically, not just ~/Mail: mbsync creates the FOLDERS
# inside a MaildirStore but not the store root itself, and without it every
# invocation dies with "Maildir error: cannot open store" before it ever
# reaches the network.
mkdir -p "$HOME/Mail/icloud" \
         "$HOME/.local/share/hey-mail" \
         "$HOME/.local/state/hey-mail" \
         "$HOME/.local/state/msmtp"

exit 0
