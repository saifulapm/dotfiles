// Ports ~/.claude/statusline.py into pi, so the two agents read the same:
//   model │ ◈ ctx% │ repo (branch*) │ thinking
//
// pi has no statusLine setting; a footer component is the equivalent seam.
// setFooter *replaces* pi's own footer, so the readout it drew on the right
// (↑in ↓out Rread Wwrite CH% $cost) goes with it. That is the trade for a line
// that matches Claude Code's. Delete this file to get pi's footer back.
import { execFile } from "node:child_process";
import { basename } from "node:path";
import { promisify } from "node:util";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { truncateToWidth } from "@earendil-works/pi-tui";

const run = promisify(execFile);

// statusline.py's own 256-colour codes rather than pi theme colours: copying
// them is what makes the two lines identical. The cost is that this footer
// does not follow the pi theme the way the default one does.
const CYAN = "38;5;39";
const GREEN = "38;5;42";
const ORANGE = "38;5;208";
const GREY = "38;5;245";
const DIM = "38;5;240";
const YELLOW = "38;5;178";
const c = (code: string, s: string) => `\x1b[${code}m${s}\x1b[0m`;

// Claude Code re-runs statusline.py at most every refreshInterval (10s). pi
// calls render() on every frame, so the dirty check needs the same ceiling or
// a large repo pays a `git status` per keystroke.
const DIRTY_TTL_MS = 10_000;
const GIT_TIMEOUT_MS = 1000;

async function git(cwd: string, ...args: string[]): Promise<string> {
	try {
		const { stdout } = await run("git", ["-C", cwd, "--no-optional-locks", ...args], {
			timeout: GIT_TIMEOUT_MS,
		});
		return stdout.trim();
	} catch {
		return "";
	}
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", (_event, ctx) => {
		// Footers are a terminal thing; -p and --mode json have no TUI.
		if (ctx.mode !== "tui") return;

		ctx.ui.setFooter((tui, _theme, footerData) => {
			// The branch comes from footerData, which pi already watches and
			// caches. Only the repo root and the dirty flag cost a subprocess,
			// so only those are cached here.
			let cachedCwd = "";
			let repoRoot: string | null = null;
			let dirty = false;
			let checkedAt = 0;
			let inFlight = false;

			const refresh = (cwd: string) => {
				if (inFlight) return;
				inFlight = true;
				void (async () => {
					try {
						if (cwd !== cachedCwd) {
							cachedCwd = cwd;
							repoRoot = (await git(cwd, "rev-parse", "--show-toplevel")) || null;
						}
						dirty = repoRoot ? (await git(cwd, "status", "--porcelain")) !== "" : false;
						checkedAt = Date.now();
					} finally {
						inFlight = false;
						tui.requestRender();
					}
				})();
			};

			return {
				dispose: footerData.onBranchChange(() => {
					checkedAt = 0; // a branch change is a new working tree
					tui.requestRender();
				}),
				invalidate() {},
				render(width: number): string[] {
					const cwd = ctx.cwd;
					if (cwd !== cachedCwd || Date.now() - checkedAt > DIRTY_TTL_MS) refresh(cwd);

					let model = ctx.model?.name ?? ctx.model?.id ?? "?";
					if ((ctx.model?.contextWindow ?? 0) >= 1_000_000) model += " (1M context)";

					const pct = `${Math.round(ctx.getContextUsage()?.percent ?? 0)}%`;

					// null outside a repo, "detached" on a detached HEAD.
					const branch = footerData.getGitBranch();
					const where = branch
						? `${c(GREEN, basename(repoRoot ?? cwd))} (${c(GREEN, branch)}${dirty ? c(ORANGE, "*") : ""})`
						: c(GREY, basename(cwd) || cwd);

					// Typed without "off", but the runtime uses it for a model
					// that reasons with thinking turned off.
					const level = ctx.thinkingLevel as string | undefined;
					const think =
						!level || level === "off" ? c(DIM, "○ no-think") : c(GREY, `◖ ${level}`);

					const sep = c(DIM, "│");
					return [
						truncateToWidth(
							`${c(CYAN, model)} ${sep} ${c(YELLOW, "◈")} ${c(GREEN, pct)} ${sep} ${where} ${sep} ${think}`,
							width,
						),
					];
				},
			};
		});
	});
}
