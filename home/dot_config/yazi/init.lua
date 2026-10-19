function Tabs:redraw() return {} end
function Tabs.height() return 0 end

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

Status:children_add(function(self)
	local h = self._current.hovered
	if h and h.link_to then
		return " -> " .. tostring(h.link_to)
	else
		return ""
	end
end, 3300, Status.LEFT)

require("folder-rules"):setup()
