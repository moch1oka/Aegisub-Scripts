script_name = "Respread"
script_description = "Replace line text, spreading the new text evenly across the existing ASS tag blocks."
script_author = "17"
script_version = "3.0"

local function is_drawing(text)
    return text:find("\\p[1-9]") ~= nil
end

-- Adjacent {...} blocks with nothing between them (e.g. {\an8}{\pos(10,20)})
-- are merged into ONE group, so new text is never inserted between them.
local function extract_tag_groups(line_text)
    local groups = {}
    local pos = 1
    local prev_end = nil
    while true do
        local s, e = line_text:find("{.-}", pos)
        if not s then break end
        local block = line_text:sub(s, e)
        if prev_end and s == prev_end + 1 then
            groups[#groups] = groups[#groups] .. block
        else
            groups[#groups + 1] = block
        end
        prev_end = e
        pos = e + 1
    end
    return groups
end

-- Splits text into UTF-8 characters, keeping together:
--   * combining marks (rare: decomposed Vietnamese like e + ^ + dot instead of ế)
--   * ASS escapes: \N, \n, \h
local function split_text(text)
    local chars = {}
    for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        local b1, b2 = char:byte(1, 2)
        -- U+0300..U+036F (combining marks) encoded as CC 80..CD AF
        local is_combining = #char == 2 and (b1 == 204 or (b1 == 205 and b2 <= 175))
        if is_combining and #chars > 0 then
            chars[#chars] = chars[#chars] .. char
        else
            chars[#chars + 1] = char
        end
    end

    local units = {}
    local i = 1
    while i <= #chars do
        local c, nxt = chars[i], chars[i + 1]
        if c == "\\" and (nxt == "N" or nxt == "n" or nxt == "h") then
            units[#units + 1] = c .. nxt
            i = i + 2
        else
            units[#units + 1] = c
            i = i + 1
        end
    end
    return units
end

local function normalize_new_text(text)
    text = text:gsub("\r\n?", "\n")
    text = text:gsub("^\n+", ""):gsub("\n+$", "")
    text = text:gsub("\n", "\\N")
    return text
end

local distribution_methods = {
    balanced = function(char_idx, n_chars, n_tags)
        return math.floor((char_idx - 1 + 0.5) * n_tags / n_chars) + 1
    end,

    linear = function(char_idx, n_chars, n_tags)
        if n_chars <= 1 then return 1 end
        return math.floor((char_idx - 1) * (n_tags - 1) / (n_chars - 1) + 0.5) + 1
    end
}

local function process_line(original_text, new_text, method)
    local tags = extract_tag_groups(original_text)

    if #tags == 0 then return new_text end

    local chars = split_text(new_text)
    local n_tags = #tags
    local n_chars = #chars
    local text_per_tag = {}

    for i = 1, n_tags do
        text_per_tag[i] = ""
    end

    if n_tags == 1 then
        text_per_tag[1] = new_text
    else
        local distribute = distribution_methods[method] or distribution_methods.balanced
        for i = 1, n_chars do
            local idx = distribute(i, n_chars, n_tags)
            text_per_tag[idx] = text_per_tag[idx] .. chars[i]
        end
    end

    local result = ""
    for i = 1, n_tags do
        result = result .. tags[i] .. text_per_tag[i]
    end
    return result
end

function macro_replace_text(subtitles, selected_lines, active_line)
    local dialog_config = {
        {class="label", x=0, y=0, width=4, height=1, label="New text to insert:"},
        {class="textbox", name="new_text", x=0, y=1, width=4, height=3, text=""},

        {class="label", x=0, y=4, width=4, height=1, label="Balanced - most even (e.g. 10 chars → 3 tags = [4][3][3])"},
        {class="label", x=0, y=5, width=4, height=1, label="Linear - symmetric, endpoint guarantee (e.g. 10 chars → 3 tags = [3][4][3])"}
    }

    local buttons = {"Balanced", "Linear", "Cancel"}
    local pressed, result = aegisub.dialog.display(dialog_config, buttons, {cancel = "Cancel"})

    if pressed == "Cancel" then return end

    local new_text = normalize_new_text(result.new_text)
    if new_text == "" then
        aegisub.log("No new text entered, nothing changed.\n")
        return
    end

    local method = "balanced"
    if pressed == "Linear" then
        method = "linear"
    end

    local changed, skipped = 0, 0

    for _, i in ipairs(selected_lines) do
        local line = subtitles[i]

        if is_drawing(line.text) then
            skipped = skipped + 1
        else
            line.text = process_line(line.text, new_text, method)
            subtitles[i] = line
            changed = changed + 1
        end
    end

    if skipped > 0 then
        aegisub.log("Skipped " .. skipped .. " vector drawing line(s).\n")
    end

    if changed > 0 then
        aegisub.set_undo_point(script_name)
    end
end

aegisub.register_macro(script_name, script_description, macro_replace_text)
