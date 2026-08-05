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
