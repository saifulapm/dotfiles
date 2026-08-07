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

require("git"):setup()
require("folder-rules"):setup()

-- Blank status bar, but NOT the upstream no-status plugin: that one also
-- grows the file area over the freed row (Tab.layout h+1), which hands the
-- screen's bottom row to the preview pane — and a full-height sixel there
-- (tall PDFs) makes foot scroll the whole alternate screen one line per DEC
-- sixel semantics. The result was the held-j corruption: header row gone
-- first, then every diff repaint one row off (debugged 2026-08-07; 100%
-- repro parking the cursor on a tall PDF). Keeping the row empty preserves
-- the minimal look and the sixel guard row.
Status.redraw = function() return {} end
