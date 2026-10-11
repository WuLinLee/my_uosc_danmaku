local mp = require("mp")
local utils = require("mp.utils")
local msg = require("mp.msg")

local STYLE_PATH_PROPERTY = "user-data/uosc_danmaku/style-defaults-path"
local STYLE_STATUS_PROPERTY = "user-data/uosc_danmaku/style-defaults-status"
local LIVE_FPS_MODE_PROPERTY = "user-data/uosc_danmaku/live-fps-mode"

local STYLE_KEYS = {
    "bold",
    "bold_mode",
    "fontname",
    "fontsize",
    "outline",
    "shadow",
    "scrolltime",
    "opacity",
    "displayarea",
    "density",
    "row_spacing",
    "balanced_lanes",
    "merge_tolerance",
    "max_screen_danmaku",
    "merge_without_style",
    "blacklist_enabled",
    "live_fps_mode",
}

local LIVE_FPS_MODES = {
    auto = true,
    ["60"] = true,
    ["80"] = true,
    ["120"] = true,
    display = true,
}

local function style_path()
    local configured = tostring(options.style_path or "")
    local path = configured ~= "" and configured or "~~/script-opts/uosc_danmaku_style.json"
    return mp.command_native({ "expand-path", path })
end

local function publish_style_state(status)
    mp.set_property_native(STYLE_PATH_PROPERTY, style_path())
    mp.set_property_native(STYLE_STATUS_PROPERTY, status)
    mp.set_property_native(LIVE_FPS_MODE_PROPERTY, options.live_fps_mode)
end

local function is_finite_number(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function valid_style_value(key, value)
    if key == "bold" or key == "merge_without_style" or key == "blacklist_enabled" or key == "balanced_lanes" then
        return type(value) == "boolean"
    end
    if key == "bold_mode" then
        return type(value) == "string" and (value:lower() == "auto" or value:lower() == "big")
    end
    if key == "fontname" then
        return type(value) == "string" and #value > 0 and #value <= 256 and not value:match("[%z\r\n]")
    end
    if key == "live_fps_mode" then
        return type(value) == "string" and LIVE_FPS_MODES[value] == true
    end
    if not is_finite_number(value) then
        return false
    end
    local ranges = {
        fontsize = { 1, 500 },
        outline = { 0, 20 },
        shadow = { 0, 20 },
        scrolltime = { 1, 120 },
        opacity = { 0, 1 },
        displayarea = { 0, 1 },
        density = { 0, 100 },
        row_spacing = { 1, 2 },
        merge_tolerance = { -1, 30 },
        max_screen_danmaku = { 0, 500 },
    }
    local range = ranges[key]
    if not range or value < range[1] or value > range[2] then
        return false
    end
    if (key == "density" or key == "max_screen_danmaku") and value ~= math.floor(value) then
        return false
    end
    return true
end

local function normalized_style_value(key, value)
    -- Big uses a runtime sentinel so render.lua's signature detects a weight-mode change.
    -- Save it as a boolean to keep old style files and validation compatible.
    if key == "bold" then
        return value == true or value == "Big"
    end
    if key == "bold_mode" then return tostring(value or "auto"):lower() end
    if key == "fontname" or key == "live_fps_mode"
        or key == "merge_without_style" or key == "blacklist_enabled" or key == "balanced_lanes" then
        return value
    end
    return tonumber(value)
end

function load_danmaku_style_defaults()
    local path = style_path()
    local file = io.open(path, "r")
    if not file then
        publish_style_state("missing")
        return false
    end
    local content = file:read("*a")
    file:close()
    local decoded = utils.parse_json(content)
    if type(decoded) ~= "table" then
        msg.warn("danmaku style defaults ignored: invalid JSON")
        publish_style_state("invalid")
        return false
    end

    for _, key in ipairs(STYLE_KEYS) do
        local value = decoded[key]
        if value ~= nil and valid_style_value(key, value) then
            options[key] = normalized_style_value(key, value)
        end
    end
    -- Old style JSON files only have bold=true/false; keep their original behavior.
    if decoded.bold_mode == nil and decoded.bold ~= nil then
        options.bold_mode = "auto"
    end
    publish_style_state("loaded")
    return true
end

function save_danmaku_style_defaults()
    local defaults = {
        bold = false,
        bold_mode = "auto",
        fontname = "sans-serif",
        fontsize = 50,
        outline = 1,
        shadow = 0,
        scrolltime = 15,
        opacity = 0.7,
        displayarea = 0.85,
        density = 100,
        row_spacing = 1.2,
        balanced_lanes = true,
        merge_tolerance = -1,
        max_screen_danmaku = 0,
        merge_without_style = false,
        blacklist_enabled = true,
        live_fps_mode = "auto",
    }
    local values = {}
    for _, key in ipairs(STYLE_KEYS) do
        local source_value = options[key]
        -- Allow mixed plugin versions to save defaults even if a newer option
        -- such as bold_mode has not yet been added to the loaded options table.
        if source_value == nil then source_value = defaults[key] end
        local value = normalized_style_value(key, source_value)
        if not valid_style_value(key, value) then
            local err = "跨进程默认保存失败：字段 " .. key .. " 的值无效（" .. tostring(source_value) .. "）"
            msg.error("danmaku style defaults not saved: " .. err)
            publish_style_state("save-error")
            return false, err
        end
        values[key] = value
    end

    local encoded = utils.format_json(values)
    if type(encoded) ~= "string" or encoded == "" then
        local err = "跨进程默认保存失败：无法生成 JSON"
        msg.error("danmaku style defaults not saved: " .. err)
        publish_style_state("save-error")
        return false, err
    end

    local path = style_path()
    if type(path) ~= "string" or path == "" then
        local err = "跨进程默认保存失败：无法解析 JSON 路径"
        msg.error("danmaku style defaults not saved: " .. err)
        publish_style_state("save-error")
        return false, err
    end

    local file, open_err = io.open(path, "w")
    if not file then
        local err = "跨进程默认保存失败，无法写入：" .. path .. "（" .. tostring(open_err) .. "）"
        msg.error("danmaku style defaults not saved: " .. err)
        publish_style_state("save-error")
        return false, err
    end

    local write_ok, write_err = file:write(encoded, "\n")
    local close_ok, close_err = file:close()
    if not write_ok or not close_ok then
        local err = "跨进程默认保存失败，写入 JSON 出错：" .. tostring(write_err or close_err or "未知错误")
        msg.error("danmaku style defaults not saved: " .. err)
        publish_style_state("save-error")
        return false, err
    end

    publish_style_state("saved")
    msg.info("danmaku style defaults saved to " .. path)
    return true, path
end

function clear_danmaku_style_defaults()
    local path = style_path()
    if type(path) ~= "string" or path == "" then
        local err = "无法解析跨进程默认 JSON 路径"
        msg.error("danmaku style defaults not cleared: " .. err)
        publish_style_state("clear-error")
        return false, err
    end
    local exists = io.open(path, "r")
    if exists then
        exists:close()
        local ok, err = os.remove(path)
        if not ok then
            local message = "无法删除默认配置：" .. path .. "（" .. tostring(err or "未知错误") .. "）"
            msg.error("danmaku style defaults not cleared: " .. message)
            publish_style_state("clear-error")
            return false, message
        end
    end
    publish_style_state("cleared")
    return true, path
end

function set_live_fps_mode(mode)
    mode = tostring(mode or "")
    if not LIVE_FPS_MODES[mode] then
        return false
    end
    options.live_fps_mode = mode
    publish_style_state("changed")
    if refresh_live_danmaku_style then
        refresh_live_danmaku_style()
    end
    if sync_smooth_fps_filter then
        sync_smooth_fps_filter()
    end
    return true
end

function get_live_fps_modes()
    return LIVE_FPS_MODES
end

mp.register_script_message("save-danmaku-style-default", function()
    local ok, detail = save_danmaku_style_defaults()
    if show_message then
        show_message(ok and "已保存跨进程默认配置" or tostring(detail), ok and 2 or 4)
    end
end)
mp.register_script_message("clear-danmaku-style-default", function()
    local ok, detail = clear_danmaku_style_defaults()
    if show_message then
        show_message(ok and "已清除跨进程默认配置" or tostring(detail), ok and 2 or 4)
    end
end)
mp.register_script_message("set-live-fps-mode", set_live_fps_mode)

load_danmaku_style_defaults()
