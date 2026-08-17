# Saiful — global rules (all projects, all machines)

## Stack
Solo full-stack dev: Laravel/PHP, React + React Router, Inertia, shadcn/ui,
Shopify apps + themes (Shopify CLI), Node, and learning Go/Rust/Elisp.

## Hard rules
- Package manager is **pnpm — never Bun**; don't move a project to npm/yarn either.
- **Never install tools/packages or add new configs without asking per item
  first.** A broad task list is not blanket approval — name the item, wait
  for the yes.
- Emacs config lives in ~/.config/emacs (the saifulapm/emacs.d repo), edited
  and pushed there — never as a side effect of work in another repo. Language
  tooling targets Emacs + eglot; the second editor is the saifulapm/kakoune
  fork (built-in treesitter — never the distro kakoune, never kak-tree-sitter).
- Dotfiles are chezmoi-managed from ~/.dotfiles (symlink mode). New dotfiles
  belong in that source tree, not loose in $HOME.

## Dev layout on these machines
- Projects live in ~/Sites. https://<dir>.test serves
  ~/Sites/laravel/<dir>/public automatically (caddy + dnsmasq + local CA) — no
  per-site setup. ONLY that subdirectory is wildcard-served; anything under
  ~/Sites/github, ~/Sites/shopify_themes or ~/Sites/tries needs its own
  ~/.config/caddy/sites/<name>.caddy override to get a hostname.
- mysql:3306, postgres:5432, redis:6379, mailpit:1025 (UI :8025) are
  on-demand socket-activated podman containers: connecting wakes them, ~10 min
  idle stops them. A "stopped" DB container is NORMAL — never enable
  always-on services to fix it. mysql root has an empty password and postgres
  trusts local connections, deliberately (dev-only, loopback-only).
- PHP version per project: .php-version → the bin/php shim (system 8.5
  default; SCL 8.2/8.3/8.4). Node per project: .nvmrc via mise.
