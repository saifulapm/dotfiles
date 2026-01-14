--
-- Nova Theme Menu for Elephant/Walker
--
Name = "novathemes"
NamePretty = "Nova Themes"

local function file_exists(path)
    local f = io.open(path, "r")
    if f then f:close() return true end
    return false
end

local function first_image_in_dir(dir)
    local handle = io.popen("ls -1 '" .. dir .. "' 2>/dev/null | head -n 1")
    if handle then
        local file = handle:read("*l")
        handle:close()
        if file and file ~= "" then return dir .. "/" .. file end
    end
    return nil
end

function GetEntries()
    local entries = {}
    local dotfiles = os.getenv("DOTFILES") or (os.getenv("HOME") .. "/.dotfiles")
    local theme_dir = dotfiles .. "/themes"

    local handle = io.popen("find -L '" .. theme_dir .. "' -mindepth 1 -maxdepth 1 -type d 2>/dev/null")
    if not handle then return entries end

    for theme_path in handle:lines() do
        local theme_name = theme_path:match(".*/(.+)$")
        if theme_name then
            local preview_path = theme_path .. "/preview.png"
            if not file_exists(preview_path) then
                preview_path = theme_path .. "/preview.jpg"
            end
            if not file_exists(preview_path) then
                preview_path = first_image_in_dir(theme_path .. "/backgrounds")
            end

            if preview_path and file_exists(preview_path) then
                local display_name = theme_name:gsub("[-_]", " ")
                display_name = display_name:gsub("(%a)([%w]*)", function(f, r)
                    return f:upper() .. r:lower()
                end)

                table.insert(entries, {
                    Text = display_name,
                    Preview = preview_path,
                    PreviewType = "file",
                    Actions = { activate = "theme set " .. theme_name }
                })
            end
        end
    end
    handle:close()
    return entries
end
