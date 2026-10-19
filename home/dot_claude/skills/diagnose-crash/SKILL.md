---
name: diagnose-crash
description: >
  Diagnose why a program crashed on this machine, from a systemd-coredump core dump.
  Use when a process has segfaulted, aborted, or otherwise dumped core, when asked
  why an application crashed or disappeared, or when a "Process crashed:" desktop
  notification is acted on. Triggers: crash, segfault, SIGSEGV, SIGABRT, core dump,
  coredumpctl, "why did X crash", "X keeps crashing", backtrace symbolization.
  Covers deciding whose bug it is, and reporting one that is ours — see reporting.md.
---

# Diagnosing a Crash

Work from evidence. The goal is an honest account of what happened, not a
plausible-sounding story.

## Establish the facts

`coredumpctl info <pid>` is the starting point. Beyond the backtrace, note the
**command line** the process was started with — it usually reveals what the
program was working on when it died, which is often the whole answer.

`coredumpctl list` shows whether this crash is a one-off or a pattern. Repeated
crashes of the same program, or several programs dying together, point somewhere
different than a single failure does.

Cores are vacuumed long before the journal entries are, so `coredumpctl list`
under-reports history. When the question is "how often does this happen", ask
the journal instead — it keeps the structured record even once the core is gone:

```bash
journalctl --since "7 days ago" -o json MESSAGE_ID=fc2e22bc6ee647b6b90729ab34a250b1 |
  jq -r '[.COREDUMP_COMM, .COREDUMP_SIGNAL_NAME, .COREDUMP_EXE] | @tsv'
```

## Rule out the boring causes first

Check resource exhaustion before blaming the program: `free -h`, and the journal
for OOM kills. A process killed by the OOM killer is not a bug in that process.

This machine runs systemd-oomd with a deliberately aggressive tier (95% memory
pressure over 60s) and swap on zram, so pressure kills are a real possibility
here rather than a theoretical one. `journalctl -u systemd-oomd` covers it.

## Correlate against the timeline

The crash timestamp is the most underused piece of evidence. Compare it against:

- **Filesystem mtimes.** A directory or file whose mtime lands on the same second
  as the crash strongly suggests what triggered it.
- **The journal** around that moment, for related warnings from the same or
  neighbouring processes.
- **Recent package updates.** A crash that starts right after an update points at
  the update. `dnf history` and `journalctl -u dnf-makecache` date them; on this
  machine `just update-all` is what performs them.

## Read the whole core, not just frame 0

Thread stacks other than the crashing one show what work was **in flight** —
thumbnailers, image loaders, IPC readers, GPU queues. That context often explains
the trigger even when the crashing frame itself cannot be symbolized.

Note any third-party code in the address space: file-manager or browser
extensions, plugins, out-of-tree drivers. In-process third-party code is a common
crash source and worth flagging — but do not pin blame on it without evidence
that it is actually implicated.

## Symbolize when you can

This is Fedora, which runs a public debuginfod server. It is already configured
system-wide in `/etc/debuginfod`, so `DEBUGINFOD_URLS` is usually set for you —
the explicit assignment below only matters in an environment that stripped it:

```bash
core=$(mktemp -t crash-XXXXXX.core)
trap 'rm -f "$core"' EXIT
coredumpctl dump <pid> --output="$core"
DEBUGINFOD_URLS="https://debuginfod.fedoraproject.org/" \
  gdb -q <executable> "$core" \
  -batch -ex 'set debuginfod enabled on' -ex 'bt'
```

`dnf debuginfo-install <package>` is the local alternative when debuginfod has
nothing, and `gdb` itself is not installed by default here — say so rather than
installing it unasked.

This is aarch64 (Apple silicon under Asahi). Frames from x86-only tooling, and
advice written for x86 register names, do not apply.

A core is a verbatim copy of the process's memory and can hold passwords, tokens,
and private documents. Write it to a fresh `mktemp` path rather than a predictable
shared one, and delete it when you are done — never leave it lying in `/tmp`.

Many packages publish no debug symbols. When frames stay unresolved, say so —
never invent function names to fill the gap. An unsymbolized stack still has
shape: which library each frame belongs to, and whether the crash came from a
signal handler, a main loop, or a worker thread.

## Report

1. What crashed, and what it was doing at the time.
2. The most likely mechanism — separating clearly what the evidence **proves**
   from what you are **inferring**.
3. Whether any user data was lost, and where it can be recovered from. Check the
   trash before concluding anything is gone.
4. Whether it is likely to recur, and what would avoid or fix it.

Be straight about the limits of the evidence. If the cause is genuinely
ambiguous, say so rather than assembling confidence out of guesswork.

**Leave the system as you found it.** Diagnosis reads; it does not fix, tidy, or
reconfigure. The one thing to clean up is your own: delete the core you extracted
above, which is a copy of the crashed process's memory.

## Whose bug is it

Most application crashes are upstream bugs in those applications, not this
configuration's doing. Before offering to file or fix anything, read
[`reporting.md`](reporting.md) — it covers how to tell the layers apart and what
to do in each case.
