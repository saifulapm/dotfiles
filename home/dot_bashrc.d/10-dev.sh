# Toolchain wiring (managed by chezmoi — edit in ~/.dotfiles/home/dot_bashrc.d/)
export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME/bin:"*) ;;
  *) export PATH="$PNPM_HOME/bin:$PATH" ;;
esac

if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate bash)"
fi

# Repo helper: theme-set etc.
case ":$PATH:" in
  *":$HOME/.dotfiles/bin:"*) ;;
  *) export PATH="$HOME/.dotfiles/bin:$PATH" ;;
esac

# ~/.local/bin + ~/.cargo/bin — nothing on Fedora 44 adds these for bash
# (only fish's 00-env.fish did; audit 2026-08-08), so bash contexts missed
# every prebuilt binary and cargo tool the apply installs.
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
case ":$PATH:" in
  *":$HOME/.cargo/bin:"*) ;;
  *) export PATH="$HOME/.cargo/bin:$PATH" ;;
esac
