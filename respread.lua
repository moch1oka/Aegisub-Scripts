script_name = "Respread"
script_description = "Replace line text, spreading the new text evenly across the existing ASS tag blocks."
script_author = "17"
script_version = "3.3"

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

-- Optional step: glue every space to the character before it, so spaces never
-- take a tag of their own (a leading space is glued to the next character).
local function attach_spaces(units)
    local merged = {}
    local lead = ""
    for _, u in ipairs(units) do
        if u == " " then
            if #merged > 0 then
                merged[#merged] = merged[#merged] .. u
            else
                lead = lead .. u
            end
        else
            merged[#merged + 1] = lead .. u
            lead = ""
        end
    end
    if lead ~= "" then merged[#merged + 1] = lead end
    return merged
end

-- A unit ends a word if it carries a trailing space or is an explicit line break.
local function ends_word(unit)
    return unit:sub(-1) == " " or unit == "\\N" or unit == "\\n"
end

-- Used when there are fewer units than tags: the spare (empty) tags are placed right
-- after word ends, so the silent beat falls between words instead of inside one.
-- At most one empty tag per gap. Returns nil when that is not possible (single word,
-- or more spare tags than gaps) so the caller can fall back to even spreading.
local function place_in_word_gaps(units, n_tags)
    local n_units = #units
    local extra = n_tags - n_units

    local gaps = {}
    for i = 1, n_units - 1 do
        if ends_word(units[i]) then gaps[#gaps + 1] = i end
    end
    local n_gaps = #gaps
    if n_gaps == 0 or extra > n_gaps then return nil end

    local empty_after = {}
    for j = 0, extra - 1 do
        local g = math.floor((j + 0.5) * n_gaps / extra) + 1
        empty_after[gaps[g]] = true
    end

    local slots = {}
    for i = 1, n_units do
        slots[#slots + 1] = units[i]
        if empty_after[i] then slots[#slots + 1] = "" end
    end
    return slots
end

local function normalize_new_text(text)
    text = text:gsub("\r\n?", "\n")
    text = text:gsub("^\n+", ""):gsub("\n+$", "")
    text = text:gsub("\n", "\\N")
    return text
end

-- mode: "plain" | "attach" | "gaps"
local function process_line(original_text, new_text, mode)
    local tags = extract_tag_groups(original_text)

    if #tags == 0 then return new_text end

    local chars = split_text(new_text)
    if mode ~= "plain" then chars = attach_spaces(chars) end
    local n_tags = #tags
    local n_chars = #chars
    local text_per_tag = {}

    for i = 1, n_tags do
        text_per_tag[i] = ""
    end

    local gap_slots = nil
    if mode == "gaps" and n_tags > 1 and n_chars < n_tags then
        gap_slots = place_in_word_gaps(chars, n_tags)
    end

    if n_tags == 1 then
        text_per_tag[1] = new_text
    elseif gap_slots then
        text_per_tag = gap_slots
    else
        for i = 1, n_chars do
            local idx = math.floor((i - 1 + 0.5) * n_tags / n_chars) + 1
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
        {class="textbox", name="new_text", x=0, y=1, width=4, height=6, text=""},

        {class="label", x=0, y=7, width=4, height=1, label="Plain: every character, spaces included, counts equally."},
        {class="label", x=0, y=8, width=4, height=1, label="Attach spaces: each space sticks to the letter before it."},
        {class="label", x=0, y=9, width=4, height=1, label="Attach + gaps: same, and spare tags go to the gaps between words."}
    }

    local btn_plain = "Plain"
    local btn_attach = "Attach spaces"
    local btn_gaps = "Attach + gaps"
    local modes = {[btn_plain] = "plain", [btn_attach] = "attach", [btn_gaps] = "gaps"}
    local buttons = {btn_plain, btn_attach, btn_gaps, "Cancel"}
    local pressed, result = aegisub.dialog.display(dialog_config, buttons, {ok = btn_plain, cancel = "Cancel"})

    local mode = modes[pressed]
    if not mode then return end

    local new_text = normalize_new_text(result.new_text)
    if new_text == "" then
        aegisub.log("No new text entered, nothing changed.\n")
        return
    end

    local changed, skipped = 0, 0

    for _, i in ipairs(selected_lines) do
        local line = subtitles[i]

        if is_drawing(line.text) then
            skipped = skipped + 1
        else
            line.text = process_line(line.text, new_text, mode)
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
