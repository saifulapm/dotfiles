-- ~/.config/yazi/init.lua

-- Hide default tab bar (tabs shown in header)
function Tabs:redraw() return {} end
function Tabs.height() return 0 end

-- Tabs in header (right side)
Header:children_add(function()
	if #cx.tabs < 2 then
		return ui.Span("")
	end
	local s = ""
	for i = 1, #cx.tabs do
		local path = tostring(cx.tabs[i].current.cwd)
		local name = path:match("([^/]+)$") or "/"
		if i == cx.tabs.idx then
			s = s .. " [" .. i .. " " .. name .. "]"
		else
			s = s .. "  " .. i .. " " .. name .. " "
		end
	end
	return ui.Span(s):fg("blue")
end, 500, Header.RIGHT)

function Linemode:size_and_mtime()
	local time = math.floor(self._file.cha.mtime or 0)
	if time == 0 then
		time = ""
	elseif os.date("%Y", time) == os.date("%Y") then
		time = os.date("%b %d %H:%M", time)
	else
		time = os.date("%b %d  %Y", time)
	end

	local size = self._file:size()
	return string.format("%s %s", size and ya.readable_size(size) or "-", time)
end

-- require("full-border"):setup()

require("smart-enter"):setup({
	open_multi = true,
})

-- `order` is where the git signs sit within the linemode. The other half of
-- this plugin lives in yazi.toml as a pair of `prepend_fetchers` entries —
-- without those nothing ever computes a status and the signs stay blank, which
-- is how it sat from 2026-08-07 until 2026-08-18.
require("git"):setup({ order = 1500 })

require("folder-rules"):setup()

-- Bookmarks (2026-08-18). One key, `'`, opens the whole menu: the fixed hops
-- below, whatever ephemeral hops have been set this session, the directories
-- open in other tabs, and a fuzzy search over all of them via fzf. Paths chosen
-- from where work actually happens on this machine.
require("bunny"):setup({
	hops = {
		{ key = "~", path = "~", desc = "Home" },
		{ key = "d", path = "~/.dotfiles", desc = "Dotfiles" },
		{ key = "c", path = "~/.config", desc = "Config" },
		{ key = "s", path = "~/Sites", desc = "Sites" },
		{ key = { "s", "l" }, path = "~/Sites/laravel", desc = "Laravel sites" },
		{ key = { "s", "g" }, path = "~/Sites/github", desc = "GitHub checkouts" },
		{ key = { "s", "t" }, path = "~/Sites/tries", desc = "Tries" },
		{ key = "r", path = "~/ref", desc = "Reference repos" },
		{ key = "D", path = "~/Downloads", desc = "Downloads" },
		{ key = "t", path = "/tmp", desc = "/tmp" },
	},
	desc_strategy = "path",
	ephemeral = true,
	tabs = true,
	notify = false,
	fuzzy_cmd = "fzf",
})

-- Share the yank register between yazi instances (built-in plugin, nothing to
-- install): copy in the window opened by Mod+E, paste in the one a file picker
-- spawned.
require("session"):setup({
	sync_yanked = true,
})

-- Live re-theme. bin/theme-apply re-renders the flavor and then broadcasts
-- this kind to every running instance; `app:theme` rebuilds the theme from
-- disk, so a theme switch lands in an open yazi the way it already does in
-- kitty, btop and helix. The broadcast has to be a published message rather
-- than an emitted action: `ya emit` needs the caller to be inside a yazi
-- subshell, and `ya emit-to 0` does not broadcast actions.
ps.sub_remote("qshell-theme", function() ya.emit("app:theme", {}) end)

-- The status bar is back as of 2026-08-18, and the row it draws in was never
-- the problem. The held-j corruption debugged 2026-08-07 came from the upstream
-- no-status plugin, which does not merely blank the row — it grows the file
-- area over it (Tab.layout h+1), handing the screen's bottom row to the preview
-- pane. A full-height sixel there (tall PDFs) makes foot scroll the whole
-- alternate screen one line, per DEC sixel semantics. Blanking Status.redraw
-- kept the row reserved and avoided that; drawing a real status bar in the same
-- reserved row changes no geometry at all, so it cannot bring the bug back —
-- and yazi now runs in kitty, whose graphics protocol has no scroll semantics
-- to trip over in the first place. Getting permissions, position and live task
-- progress back is worth the row.

-- The symlink target, appended on the left (upstream tip).
Status:children_add(function(self)
	local h = self._current.hovered
	if h and h.link_to then
		return " -> " .. tostring(h.link_to)
	else
		return ""
	end
end, 3300, Status.LEFT)
