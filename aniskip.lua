-- Importing mpv module
local mp = require 'mp'
local opts = require 'mp.options'
local utils = require 'mp.utils'
local msg = require 'mp.msg'
local input = require 'mp.input'

local options = { -- setting default options
    auto_skip = true, chapters = true,
    placeholder_title = "Black Clover S1E1",
    pause_on_input = true, aniskip_path = "ani-skip",
    osd_messages = true, not_found_warning = true
}

opts.read_options(options, "aniskip")

local times = {
    op_start = -1, op_end = -1, ed_start = -1, ed_end = -1
}

opts.read_options(times, "skip")

local old_chapters = {}

local function add_chapter(title, time)

    local chapter_list = mp.get_property_native("chapter-list")
    local chapter_index = (mp.get_property_number("chapter") or -1) + 2

    table.insert(chapter_list, chapter_index, { title = title, time = time })

    mp.set_property_native("chapter-list", chapter_list)

end

local function add_chapters()

    old_chapters = mp.get_property_native("chapter-list")
    msg.debug("old_chapters: " .. utils.to_string(old_chapters))
    mp.set_property_native("chapter-list", {})

    if times.op_start > 0 then add_chapter("Episode", 0) end
    if times.op_start >= 0 then add_chapter("Opening", times.op_start) end
    if times.op_end >= 0 then add_chapter("Episode", times.op_end) end
    if times.ed_start >= 0 then add_chapter("Ending", times.ed_start) end
    if times.ed_end >= 0 then add_chapter("Preview", times.ed_end) end

    msg.debug("new_chapters: " .. utils.to_string(mp.get_property_native("chapter-list")))

end

local function callback(success, result, error)

    if result then

        if result.status ~= 0 then

            if options.not_found_warning and options.osd_messages then
                mp.osd_message("ani-skip: Skip times not found!", 2)
            end

            times.op_start = -1
            times.op_end = -1
            times.ed_start = -1
            times.ed_end = -1

        else

            local stdout = result.stdout

            local str_op_start = tonumber(stdout:match("skip%-op_start=([%d%.]+)"))
            local str_op_end = tonumber(stdout:match("skip%-op_end=([%d%.]+)"))
            local str_ed_start = tonumber(stdout:match("skip%-ed_start=([%d%.]+)"))
            local str_ed_end = tonumber(stdout:match("skip%-ed_end=([%d%.]+)"))

            if str_op_start then times.op_start = tonumber(str_op_start) end
            if str_op_end then times.op_end = tonumber(str_op_end) end
            if str_ed_start then times.ed_start = tonumber(str_ed_start) end
            if str_ed_end then times.ed_end = tonumber(str_ed_end) end

            msg.trace("Found segments: " .. times.op_start .. " - " .. times.op_end .. " | " .. times.ed_start .. " - " .. times.ed_end)

        end

        if options.chapters then add_chapters() end

    end

end

local function parse_title_and_episode(filename)

    local title, season, episode = filename:match("^(.-) S(%d+)E(%d+)")

    msg.trace(("title: %s, season: %s, episode: %s"):format(title, season, episode))

    return ("(%s (Season %s))"):format(title, tostring(tonumber(season))), tonumber(episode)

end

local function query_segments(title, episode)

    mp.command_native_async({
        name = 'subprocess',
        args = { options.aniskip_path, "--query", title, "--episode", tostring(episode) },
        playback_only = false,
        capture_stdout = true,
    }, callback)

end

local function on_load()

    local path = mp.get_property("path", "")
    local _, filename = utils.split_path(path)

    local title, episode = parse_title_and_episode(filename)

    query_segments(title, episode)

end

local function manual_input()

    input.get({
        prompt = "Instert Title: ",
        submit = function (str)
            local title, episode = parse_title_and_episode(str)
            query_segments(title, episode)
            input.terminate()
        end,
        default_text = options.placeholder_title,
        cursor_position = #(options.placeholder_title) + 1,
    })

    if options.pause_on_input then
        mp.set_property_bool("pause", true)
    end

end

-- Function to check and skip if within the defined section
local function skip()
    local current_time = mp.get_property_number("time-pos")
    
    if not current_time or not options.auto_skip then
        return
    end

    -- Check for opening sequence
    if current_time >= times.op_start and current_time < times.op_end then
        mp.set_property_number("time-pos", times.op_end)
        msg.trace("Skipping from " .. times.op_start .. " to " .. times.op_end)
    end
    
    -- Check for ending sequence
    if current_time >= times.ed_start and current_time < times.ed_end then
        mp.set_property_number("time-pos", times.ed_end)
        msg.trace("Skipping from " .. times.ed_start .. " to " .. times.ed_end)
    end
end

local function toggle_autoskip()

    options.auto_skip = not options.auto_skip

    if options.osd_messages then
        mp.osd_message("ani-skip: auto-skip is " .. (options.auto_skip and "enabled" or "disabled"))
    end

end

local function toggle_chapters()

    options.chapters = not options.chapters

    if options.osd_messages then
        mp.osd_message("ani-skip: now displaying " .. (options.chapters and "ani-skip" or "original") .. " chapters")
    end

    if not options.chapters then
        mp.set_property_native("chapter-list", old_chapters)
    else add_chapters() end

end

-- Bind the function to be called whenever the time position is changed
mp.observe_property("time-pos", "number", skip)
mp.add_key_binding(nil, "auto-skip", toggle_autoskip)
mp.add_key_binding(nil, "chapters", toggle_chapters)
mp.add_key_binding(nil, "manual", manual_input)
mp.register_event("start-file", on_load)