# Whose Bug Is It, and What To Do About It

Read this once the diagnosis is done and you know what failed.

Adapted from omarchy's `reporting.md`. Theirs is about filing upstream to a
project the user only consumes; here the top layer is the user's **own** repo,
sitting on this machine, so the useful split is different.

## Tell the layers apart

Be strict. This machine is a configuration layer (chezmoi + a Quickshell shell)
over Fedora Asahi. A crash inside a third-party application — a browser, a file
manager, a GTK or Qt library — is almost always an upstream bug in **that**
project.

The dotfiles' sphere of control is roughly:

- `~/.dotfiles/bin/*` — every script the desktop runs
- the Quickshell shell under `~/.dotfiles/shell` and its services
- the niri, foot, tmux, helix and kakoune configuration it ships
- its themes and the theme-apply pipeline
- the chezmoi scripts under `home/.chezmoiscripts`
- how it packages and configures what it installs

A crash in a program these merely install is **not** a dotfiles bug unless the
packaging or configuration is implicated — a wrong flag, a bad config file, a
missing dependency, an environment variable set here.

Below that sits Fedora's packaging, and below that the Asahi kernel and mesa
stack. A GPU or firmware crash on Apple silicon is very often an Asahi-specific
issue rather than a bug in the application that happened to be drawing.

## If it is the dotfiles' own bug

This is the common case worth acting on, and there is no issue to file: the repo
is right here. Say what you found, propose the fix, and let the user decide
whether to make it now. Follow the repo's rules — CLAUDE.md, and the porting and
verification conventions the existing code documents in place.

Do not commit or push unless asked.

## If it belongs to an upstream project

Say so and stop. Naming the right project and linking its tracker is useful;
filing there yourself is not part of this, with one exception below.

Two things make an upstream report worth the maintainer's time, and both are
usually missing from a first-pass diagnosis:

- a **symbolized** stack, or a clear statement that symbols were unavailable
- a **reproduction** — or an honest "seen once, not reproducible"

If you have neither, the honest report is that the crash happened and could not
be characterized. That is a fine thing to tell the user and a poor thing to file.

## If the user asks you to file it

Three conditions, all required:

1. **It is a verified bug**, established on evidence, in a project that takes
   issues. Not a question, not a suspicion.
2. **The user has explicitly agreed.** Show the exact title and body you propose
   and wait for a yes. Never file unprompted.
3. **The machine can file it** — `gh auth status` must succeed. If it does not,
   do not authenticate anything; hand the user the finished text instead.

Search before filing, including closed issues — a matching issue closed as fixed,
when the crash still reproduces, is a regression, and that is worth far more than
another duplicate:

```bash
gh search issues --repo <owner>/<repo> "<program> crash"
```

`gh search issues` accepts only `open` or `closed` for `--state` and errors on
anything else; leaving it off searches both, which is what you want.

If a plausible match comes back, read it fully (`gh issue view <n> --repo
<owner>/<repo> --comments`) and confirm it is genuinely the same failure — the
same program crashing is not the same bug if the trigger or the stack differs.
Add to it only when you have something the thread lacks: a different
reproduction, a symbolized stack where it has none, a narrower trigger, a version
where it regressed. A comment that only says it happens to you too is noise.

Include system details: `rpm -q <package>`, `uname -r`, that this is Fedora
Asahi on aarch64, and the desktop is niri + Quickshell rather than GNOME or KDE —
that last one matters more often than people expect for anything touching
Wayland, portals or the tray.

`gh` cannot attach media. If a screenshot would help, save one and give the user
the path to drag into the web form.

## Signing

End any issue or comment with a line naming the model and agent harness that
produced it, so a human reader knows it was machine-authored:

> Filed by \<model name\> via \<agent harness\>.

Use your actual model and harness names. If you are not certain of them, say so
plainly rather than inventing a version string.
