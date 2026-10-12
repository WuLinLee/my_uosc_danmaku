local msg   = require 'mp.msg'
local utils = require 'mp.utils'
local s2t   = require("dicts/s2t_chars")
local t2s   = require("dicts/t2s_chars")

local function ass_escape(text)
    return text:gsub("\\", "\\\\")
               :gsub("{", "\\{")
               :gsub("}", "\\}")
               :gsub("\n", "\\N")
end

-- 构建 per-source 的延迟查询函数
local function make_delay_lookup(source)
    local segments = nil
    local prefix = nil
    if source and source.delay_segments and #source.delay_segments > 0 then
        segments = {}
        for i, v in ipairs(source.delay_segments) do segments[i] = v end
        table.sort(segments, function(a, b) return (a.start or 0) < (b.start or 0) end)
        prefix = {}
        local s = 0
        for i, v in ipairs(segments) do
            s = s + (v.delay or 0)
            prefix[i] = s
        end
    end

    return function(t)
        local segs = segments or {}
        local pre = prefix or {}
        if #segs == 0 then return 0 end
        local idx = binary_search(segs, t, function(s) return (s and s.start) or 0 end)
        local target = idx - 1
        if target < 1 then return 0 end
        return pre[target] or 0
    end
end

local function xml_unescape(str)
    return str:gsub("&quot;", "\"")
              :gsub("&apos;", "'")
              :gsub("&gt;", ">")
              :gsub("&lt;", "<")
              :gsub("&amp;", "&")
end

local function decode_html_entities(text)
    return text:gsub("&#x([%x]+);", function(hex)
        local codepoint = tonumber(hex, 16)
        return unicode_to_utf8(codepoint)
    end):gsub("&#(%d+);", function(dec)
        local codepoint = tonumber(dec, 10)
        return unicode_to_utf8(codepoint)
    end)
end

-- 加载黑名单模式
local function load_blacklist_patterns(filepath)
    local patterns = {}
    if not file_exists(filepath) then
        return patterns
    end
    local file = io.open(filepath, "r")
    if not file then
        msg.error("无法打开黑名单文件: " .. filepath)
        return patterns
    end

    if string.match(filepath, "%.xml$") then
        -- xml文件格式示例
        --<?xml version="1.0" encoding="utf-8"?>
        --<filters>
        --  <item enabled="true">t=卡在</item>
        --  <item enabled="true">t=进度条</item>
        --</filters>
        print("加载黑名单文件: " .. filepath)
        for line in file:lines() do
            local pattern = line:match('<item%s+enabled="true">t=(.-)</item>')
            if pattern then
                print("加载黑名单模式: " .. pattern)
                table.insert(patterns, pattern)
            end
        end
    end

    if string.match(filepath, "%.json$") then
        -- json文件格式示例
        -- [{"type":0,"filter":"开门","opened":true,"id":15628936}
        -- ,{"type":0,"filter":"tony","opened":true,"id":15628939}
        -- ,{"type":1,"filter":"0+.1","opened":true,"id":15628951}]
        local content = read_file(filepath)
        if content then
            local json = utils.parse_json(content)
            if json and type(json) == "table" then
                for _, entry in ipairs(json) do
                    if entry.opened and entry.filter and entry.type == 0 then
                        table.insert(patterns, entry.filter)
                    end
                end
            end
        end
    end

    if string.match(filepath, "%.txt$") then
        -- 文本文件格式示例
        -- 卡在
        -- 进度条
        for line in file:lines() do
            line = line:match("^%s*(.-)%s*$")
            if line ~= "" then
                table.insert(patterns, line)
            end
        end
    end

    file:close()
    return patterns
end

local black_patterns = {}

local function expand_configured_path(path)
    path = tostring(path or "")
    if path == "" then return nil end
    local ok, expanded = pcall(mp.command_native, { "expand-path", path })
    if ok and type(expanded) == "string" and expanded ~= "" then return expanded end
    return path
end

-- 支持运行中从菜单重新加载规则。既有外部文件与菜单维护的 TXT 文件会合并，
-- 不会覆盖用户已有的 blacklist_path 配置。
function reload_danmaku_blacklist()
    local combined, seen_paths = {}, {}
    local paths = {
        expand_configured_path(options.blacklist_path),
        expand_configured_path(options.blacklist_menu_path),
    }
    for _, path in ipairs(paths) do
        if path and not seen_paths[path] then
            seen_paths[path] = true
            local loaded = load_blacklist_patterns(path)
            for _, pattern in ipairs(loaded) do
                combined[#combined + 1] = pattern
            end
        end
    end
    black_patterns = combined
    msg.info("弹幕屏蔽规则已加载：" .. tostring(#black_patterns) .. " 条")
    return #black_patterns
end

function get_danmaku_blacklist_patterns()
    local result = {}
    for i, pattern in ipairs(black_patterns) do result[i] = pattern end
    return result
end

reload_danmaku_blacklist()

-- 检查字符串是否在黑名单中
function is_blacklisted(str, patterns)
    if options.blacklist_enabled == false then return false end
    for _, pattern in ipairs(patterns or black_patterns) do
        local ok, result = pcall(function()
            return str:match(pattern)
        end)

        if ok and result then
            return true, pattern
        elseif not ok then
            -- msg.debug("黑名单规则错误，跳过: " .. pattern .. "，错误信息：" .. result)
        end
    end
    return false
end

-- 简繁转换
local function convert(text, dict)
    return text:gsub("[%z\1-\127\194-\244][\128-\191]*", function(c)
        return dict[c] or c
    end)
end

local function ch_convert(str)
    if options.chConvert == 1 then
        return convert(str, t2s)
    elseif options.chConvert == 2 then
        return convert(str, s2t)
    end
    return str
end

local ch_convert_cache = {}
local ch_cache_keys = {}
local ch_cache_max = 5000

local function ch_convert_cached(text)
    if type(text) ~= "string" or text == "" then return text end
    local cached = ch_convert_cache[text]
    if cached ~= nil then return cached end

    local converted = ch_convert(text)
    ch_convert_cache[text] = converted
    ch_cache_keys[#ch_cache_keys+1] = text

    if #ch_cache_keys > ch_cache_max then
        local old_key = table.remove(ch_cache_keys, 1)
        ch_convert_cache[old_key] = nil
    end

    return converted
end

-- 合并重复弹幕的高亮颜色。单条弹幕保留原颜色；群体响应越大，高亮越醒目。
-- 这些值使用 RGB，后续 ASS 输出会统一转换为 BGR。
local function duplicate_burst_color(count)
    count = tonumber(count) or 1
    if count >= 11 then return 0xFF5A36 end -- 11+: 橙红
    if count >= 7 then return 0xFFCC33 end  -- 7-10: 金黄
    if count >= 4 then return 0x29B6F6 end  -- 4-6: 鲜蓝
    if count >= 2 then return 0x4DD0E1 end  -- 2-3: 青绿
    return nil
end

-- 合并重复弹幕
local function merge_duplicate_danmaku(danmakus, threshold)
    if not threshold or tonumber(threshold) < 0 then return danmakus end

    local groups = {}
    local untouched = {}

    for _, d in ipairs(danmakus) do
        local kind = tonumber(d.type)
        if kind and kind >= 1 and kind <= 3 then
            local tkey = options.merge_without_style and "any" or tostring(d.type or "")
            local text = d.text or ""

            groups[text] = groups[text] or {}
            groups[text][tkey] = groups[text][tkey] or {}
            table.insert(groups[text][tkey], d)
        else
            -- Fixed top/bottom comments keep their native type, text, color and lane behavior.
            table.insert(untouched, d)
        end
    end

    local final_groups = {}

    -- 颜色合并
    for _, type_groups in pairs(groups) do
        for _, list in pairs(type_groups) do
            if options.merge_without_style then
                table.insert(final_groups, list)
            else
                local color_groups = {}
                -- 利用弹幕同色大量重复的特征，缓存 颜色值 -> color_groups 索引
                local exact_color_cache = {}

                for _, d in ipairs(list) do
                    local c = d.color or 16777215
                    local g_idx = exact_color_cache[c]

                    if g_idx then
                        -- 命中缓存，直接插入
                        table.insert(color_groups[g_idx], d)
                    else
                        -- 未命中的颜色值，计算它是否落入已有代表颜色的 15 容差范围内
                        local found = false
                        for i, cg in ipairs(color_groups) do
                            if color_dist(cg[1].color or 16777215, c) <= 15 then
                                table.insert(cg, d)
                                -- 将该颜色值缓存为这个代表颜色的索引，后续遇到完全相同的颜色值可以直接命中
                                exact_color_cache[c] = i
                                found = true
                                break
                            end
                        end

                        -- 超出容差范围的全新颜色代表，开辟新组
                        if not found then
                            table.insert(color_groups, {d})
                            exact_color_cache[c] = #color_groups
                        end
                    end
                end
                
                for _, cg in ipairs(color_groups) do
                    table.insert(final_groups, cg)
                end
            end
        end
    end

    local merged = untouched
    local abs = math.abs

    for _, group in ipairs(final_groups) do
        table.sort(group, function(a, b) return a.time < b.time end)

        local i = 1
        while i <= #group do
            local base = group[i]
            local count = 1
            local j = i + 1

            -- Anchor this burst to its first timestamp instead of chaining nearby
            -- comments indefinitely. Every later member stays within threshold
            -- of the group's first event.
            while j <= #group and abs(group[j].time - base.time) <= threshold do
                count = count + 1
                j = j + 1
            end

            local danmaku = {
                time = base.time,
                type = base.type,
                size = base.size,
                color = base.color,
                text = base.text,
                source = base.source,
                orig_time = base.orig_time,
                merge_count = count > 1 and count or nil,
            }

            table.insert(merged, danmaku)
            i = j
        end
    end

    table.sort(merged, function(a, b) return a.time < b.time end)
    return merged
end

-- 限制每屏弹幕条数
local function limit_danmaku(danmakus, limit)
    if not limit or limit <= 0 then
        return danmakus
    end

    local window = {}
    for _, d in ipairs(danmakus) do
        for i = #window, 1, -1 do
            if window[i].end_time <= d.start_time then
                table.remove(window, i)
            end
        end

        if #window < limit then
            table.insert(window, d)
        else
            local max_idx = 1
            for i = 2, #window do
                if window[i].end_time > window[max_idx].end_time then
                    max_idx = i
                end
            end
            if window[max_idx].end_time > d.end_time then
                window[max_idx].drop = true
                window[max_idx] = d
            else
                d.drop = true
            end
        end
    end

    local result = {}
    for _, d in ipairs(danmakus) do
        if not d.drop then
            table.insert(result, d)
        end
    end
    return result
end

-- 智能密度过滤（移植 Danmaku Anywhere 的软预算/信息量优先思路）
-- 密度 100 完全不筛选；低密度会优先丢弃局部拥挤区域中信息量较低的弹幕。
local function density_clamp(value, lower, upper)
    return math.max(lower, math.min(upper, value))
end

local function density_chars(text)
    local chars = {}
    -- LuaJIT 没有统一可用的 Unicode 字符迭代器；按 UTF-8 首字节拆分，兼容中日韩文字。
    for char in tostring(text or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        chars[#chars + 1] = char
    end
    return chars
end

local function density_visual_cost(text, font_size, mode)
    local trimmed = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local count = #density_chars(trimmed)
    local width_cost = 0.7 + math.min(48, count) * 0.032
    local font_scale = density_clamp((tonumber(font_size) or 25) / 25, 0.65, 1.75)
    local mode_scale = (mode == "top" or mode == "bottom") and 1.3 or 1.0
    return width_cost * font_scale * mode_scale
end

local DENSITY_SYMBOLS = {
    ["。"] = true, ["，"] = true, ["、"] = true, ["！"] = true, ["？"] = true,
    ["："] = true, ["；"] = true, ["……"] = true, ["…"] = true, ["—"] = true,
    ["～"] = true, ["〜"] = true, ["·"] = true, ["「"] = true, ["」"] = true,
    ["『"] = true, ["』"] = true, ["（"] = true, ["）"] = true, ["【"] = true,
    ["】"] = true, ["《"] = true, ["》"] = true, ["〈"] = true, ["〉"] = true,
    ["★"] = true, ["☆"] = true, ["❤"] = true, ["♥"] = true, ["♡"] = true,
    ["♪"] = true, ["♫"] = true, ["→"] = true, ["←"] = true, ["↑"] = true,
    ["↓"] = true, ["●"] = true, ["○"] = true, ["◎"] = true, ["※"] = true,
}

local function density_information_score(text)
    local original = density_chars(tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower())
    if #original == 0 then return 0.2 end

    -- 将连续 3 个及以上相同字符压缩为最多 2 个，降低刷屏重复字符的优先级。
    local compact, previous, run = {}, nil, 0
    for _, char in ipairs(original) do
        if char == previous then run = run + 1 else previous, run = char, 1 end
        if run <= 2 then compact[#compact + 1] = char end
    end

    local unique = {}
    local has_meaningful = false
    for _, char in ipairs(compact) do
        unique[char] = true
        if not char:match("^[%p%s]+$") and not DENSITY_SYMBOLS[char] then
            has_meaningful = true
        end
    end
    local unique_count = 0
    for _ in pairs(unique) do unique_count = unique_count + 1 end
    local diversity = unique_count / math.max(1, #compact)
    local variety = math.min(1, unique_count / 8)
    local repeat_penalty = 1 - math.min(1, #compact / #original)
    local symbol_penalty = has_meaningful and 0 or 0.15
    return density_clamp(0.2 + diversity * 0.4 + variety * 0.35 - repeat_penalty * 0.3 - symbol_penalty, 0.05, 1)
end

local function density_stable_unit_hash(text)
    -- 稳定、无随机种子的 32 位滚动哈希；同一时间轴和弹幕内容会得到同一结果。
    local hash = 5381
    text = tostring(text or "")
    for i = 1, #text do
        hash = (hash * 33 + text:byte(i)) % 4294967296
    end
    return hash / 4294967296
end

local function density_mode(danmaku)
    local kind = tonumber(danmaku and danmaku.type) or 1
    if kind == 5 then return "top" end
    if kind == 4 then return "bottom" end
    return "rtl"
end

local function apply_smart_density(items, font_size, scroll_time, area_ratio)
    local density = density_clamp(tonumber(options.density) or 100, 0, 100)
    if density >= 100 or #items < 2 then return items end

    local candidates = {}
    for index, item in ipairs(items) do
        local danmaku = item.danmaku or item
        local time = tonumber(item.start_time) or tonumber(danmaku.time)
        if time then
            local text = item.clean_text or danmaku.text or ""
            local mode = density_mode(danmaku)
            candidates[#candidates + 1] = {
                index = index,
                time = time,
                text = tostring(text),
                mode = mode,
                protected = item.protected == true or danmaku.protected == true,
                cost = density_visual_cost(text, font_size, mode),
            }
        end
    end
    if #candidates < 2 then return items end

    table.sort(candidates, function(a, b)
        if a.time == b.time then return a.index < b.index end
        return a.time < b.time
    end)

    local prefix = { [0] = 0 }
    for i, candidate in ipairs(candidates) do
        prefix[i] = prefix[i - 1] + candidate.cost
    end

    local half_window = math.max(0.75, (tonumber(scroll_time) or 15) / 2)
    local area_factor = density_clamp((tonumber(area_ratio) or 0.8) / 0.8, 0.4, 1.3)
    local density_ratio = density / 100
    local base_budget = (8 + math.pow(density_ratio, 1.4) * 42) * area_factor
    local budget = base_budget * (0.5 + 0.5 * density_ratio)
    local dropped = {}
    local left, right = 1, 1

    for i, candidate in ipairs(candidates) do
        while left < i and candidate.time - candidates[left].time > half_window do
            left = left + 1
        end
        if right < i then right = i end
        while right < #candidates and candidates[right + 1].time <= candidate.time + half_window do
            right = right + 1
        end

        local local_load = prefix[right] - prefix[left - 1]
        if not candidate.protected and local_load > budget then
            local overload = local_load / math.max(0.001, budget) - 1
            local pressure = 1 - math.exp(-1.05 * math.pow(overload, 1.25))
            local priority = density_information_score(candidate.text)
            local low_density_boost = 1 + 0.3 * math.pow(1 - density_ratio, 1.5)
            local drop_chance = density_clamp(pressure * (1.08 - priority * 0.5) * low_density_boost, 0, 0.98)
            local hash_key = string.format("%.0f|%s|%s|%d", math.floor(candidate.time * 1000 + 0.5), candidate.mode, candidate.text, candidate.index)
            if density_stable_unit_hash(hash_key) < drop_chance then
                dropped[candidate.index] = true
            end
        end
    end

    if next(dropped) == nil then return items end
    local filtered = {}
    for index, item in ipairs(items) do
        if not dropped[index] then filtered[#filtered + 1] = item end
    end
    return filtered
end

-- 解析 XML 弹幕
function parse_xml_danmaku(xml_string)
    local danmakus = {}
    if not xml_string then
        return danmakus
    end
    -- [^>]* 匹配其他 attributes
    -- %f[^%s] 确保 p= 前面是空白字符
    for p_attr, text in xml_string:gmatch('<d%s+[^>]*%f[^%s]p="([^"]+)"[^>]*>([^<]+)</d>') do
        local params = {}
        local i = 1
        for val in p_attr:gmatch("([^,]+)") do
            params[i] = tonumber(val)
            i = i + 1
        end

        if params[1] and params[2]  and params[3] and params[4] then
            table.insert(danmakus, {
                time = params[1],
                type = params[2] or 1,
                size = params[3] or 25,
                color = params[4] or 0xFFFFFF,
                text = xml_unescape(text)
            })
        end
    end

    table.sort(danmakus, function(a, b) return a.time < b.time end)
    return danmakus
end

-- 解析 JSON 弹幕
function parse_json_danmaku(json_string)
    local danmakus = {}
    if json_string:sub(1, 3) == "\239\187\191" then
        json_string = json_string:sub(4)
    end

    local json = utils.parse_json(json_string)
    if not json or type(json) ~= "table" then
        msg.info("JSON 解析失败")
        return danmakus
    end

    for _, entry in ipairs(json) do
        local c = entry.c
        local text = entry.m or ""
        if type(c) == "string" then
            local params = {}
            local i = 1
            for val in c:gmatch("([^,]+)") do
                params[i] = tonumber(val)
                i = i + 1
            end

            if params[1] and params[2] and params[3] and params[4] then
                table.insert(danmakus, {
                    time = params[1],
                    color = params[2] or 0xFFFFFF,
                    type = params[3] or 1,
                    size = params[4] or 25,
                    text = text
                })
            end
        end
    end

    table.sort(danmakus, function(a, b) return a.time < b.time end)
    return danmakus
end

-- 解析弹幕文件
function parse_danmaku_file(danmaku_input)
    local danmakus = {}

    if file_exists(danmaku_input) then
        local content = read_file(danmaku_input)
        if content then
            local parsed = {}
            if danmaku_input:match("%.xml$") then
                parsed = parse_xml_danmaku(content)
            elseif danmaku_input:match("%.json$") then
                parsed = parse_json_danmaku(content)
            end

            for _, d in ipairs(parsed) do
                table.insert(danmakus, d)
            end
        else
            msg.info("无法读取文件内容: " .. danmaku_input)
        end
    else
        msg.info("文件不存在: " .. danmaku_input)
    end

    for _, d in ipairs(danmakus) do
        if d.orig_time == nil then d.orig_time = d.time end
    end

    if #danmakus == 0 then
        msg.info("未能解析任何弹幕")
        return nil
    end

    return danmakus
end

--# 弹幕数组与布局算法 (Danmaku Array & Layout Algorithms)
local DanmakuArray = {}
DanmakuArray.__index = DanmakuArray

function DanmakuArray:new(res_x, res_y, font_size, row_spacing)
    local safe_font_size = math.max(1, tonumber(font_size) or 1)
    local spacing = tonumber(row_spacing) or tonumber(options.row_spacing) or 1.2
    spacing = math.max(1.0, math.min(2.0, spacing))
    local row_height = math.max(1, math.floor(safe_font_size * spacing + 0.5))
    local obj = {
        solution_y = res_y,
        font_size = safe_font_size,
        row_height = row_height,
        rows = math.max(1, math.floor((tonumber(res_y) or row_height) / row_height)),
        time_length_array = {},
        -- 平衡分配时用于打破对称轨道的平局，避免持续偏向上侧。
        next_side = -1,
    }
    for i = 1, obj.rows do
        obj.time_length_array[i] = { time = 0, length = 0, empty = true }
    end
    setmetatable(obj, self)
    return obj
end

function DanmakuArray:set_time_length(row, time, length)
    if row > 0 and row <= self.rows then
        self.time_length_array[row] = { time = time, length = length, empty = false }
    end
end

function DanmakuArray:get_time(row)
    if row > 0 and row <= self.rows then
        return self.time_length_array[row].time
    end
    return -1
end

function DanmakuArray:get_length(row)
    if row > 0 and row <= self.rows then
        return self.time_length_array[row].length
    end
    return 0
end

function DanmakuArray:is_empty(row)
    if row > 0 and row <= self.rows then
        return self.time_length_array[row].empty
    end
    return false
end

local function can_use_scrolling_row(row, appear_time, text_length, resolution_x, roll_time, array)
    if array:is_empty(row) then return true end

    local previous_appear_time = array:get_time(row)
    local previous_length = array:get_length(row)
    local velocity = (text_length + resolution_x) / roll_time
    local previous_velocity = (previous_length + resolution_x) / roll_time
    local delta_velocity = velocity - previous_velocity
    local delta_x = (appear_time - previous_appear_time) * previous_velocity - previous_length

    if delta_x >= 0 then
        if delta_velocity <= 0 then return true end
        local delta_time = delta_x / delta_velocity
        if delta_time >= roll_time then return true end
    end
    return false
end

-- 滚动弹幕 Y 坐标算法。
-- 旧模式保持从上到下的 first-fit。均匀模式先做碰撞检查，再优先选择
-- 与已用轨道距离较远的空轨道，避免弹幕只集中在画面中心附近；
-- 空轨道用完后，优先复用最久未使用的可用轨道。
function get_position_y(font_size, appear_time, text_length, resolution_x, roll_time, array)
    if not options.balanced_lanes then
        for i = 1, array.rows do
            if can_use_scrolling_row(i, appear_time, text_length, resolution_x, roll_time, array) then
                array:set_time_length(i, appear_time, text_length)
                return 1 + (i - 1) * array.row_height
            end
        end
        return nil
    end

    local best_row = nil
    local best_empty = false
    local best_time = math.huge
    local best_spread = -1
    local preferred_side = array.next_side or -1
    local center = (array.rows + 1) / 2

    for i = 1, array.rows do
        if can_use_scrolling_row(i, appear_time, text_length, resolution_x, roll_time, array) then
            local empty = array:is_empty(i)
            local previous_time = array:get_time(i)
            local spread = math.huge

            if empty then
                -- 以离最近已用轨道的距离衡量分散程度；首条弹幕放在中心。
                local has_used_row = false
                for j = 1, array.rows do
                    if not array:is_empty(j) then
                        has_used_row = true
                        spread = math.min(spread, math.abs(i - j))
                    end
                end
                if not has_used_row then
                    spread = -math.abs(i - center)
                end
            else
                -- 已使用轨道之间优先回收最久未用的轨道，减少连续弹幕挤在同一行。
                spread = -math.abs(i - center) * 0.001
            end

            local choose = false
            if best_row == nil then
                choose = true
            elseif empty and not best_empty then
                choose = true
            elseif not empty and best_empty then
                choose = false
            elseif empty and best_empty then
                if spread > best_spread then
                    choose = true
                elseif spread == best_spread then
                    local side = i - center
                    local best_side = best_row - center
                    local matches_preferred = side ~= 0 and ((side > 0 and preferred_side > 0) or (side < 0 and preferred_side < 0))
                    local best_matches_preferred = best_side ~= 0 and ((best_side > 0 and preferred_side > 0) or (best_side < 0 and preferred_side < 0))
                    if matches_preferred and not best_matches_preferred then choose = true end
                end
            else
                if previous_time < best_time then
                    choose = true
                elseif previous_time == best_time and spread > best_spread then
                    choose = true
                end
            end

            if choose then
                best_row = i
                best_empty = empty
                best_time = previous_time
                best_spread = spread
            end
        end
    end

    if best_row then
        array:set_time_length(best_row, appear_time, text_length)
        array.next_side = -preferred_side
        return 1 + (best_row - 1) * array.row_height
    end
    return nil
end

-- 固定弹幕 Y 坐标算法
function get_fixed_y(font_size, appear_time, fixtime, array, from_top)
    local row_start, row_end, row_step
    if from_top then
        row_start, row_end, row_step = 1, array.rows, 1
    else
        row_start, row_end, row_step = array.rows, 1, -1
    end

    for i = row_start, row_end, row_step do
        local previous_appear_time = array:get_time(i)
        if array:is_empty(i) then
            array:set_time_length(i, appear_time, 0)
            return (i - 1) * array.row_height + 1
        else
            local delta_time = appear_time - previous_appear_time
            if delta_time > fixtime then
                array:set_time_length(i, appear_time, 0)
                return (i - 1) * array.row_height + 1
            end
        end
    end
    -- 所有行都被占用，放弃渲染
    return nil
end

-- 将弹幕转换为 XML 格式
function convert_danmaku_to_xml(danmaku_out)
    local danmakus = {}
    for url, source in pairs(DANMAKU.sources) do
        if not source.blocked and source.data then
            local get_cached_delay = make_delay_lookup(source)

            for _, d in ipairs(source.data) do
                local base_time = d.orig_time or d.time
                local adjusted_time = base_time + get_cached_delay(base_time)
                table.insert(danmakus, {
                    orig_time = d.orig_time,
                    time = adjusted_time,
                    type = d.type,
                    size = d.size,
                    color = d.color,
                    text = d.text,
                    source = url,
                })
            end
        end
    end

    if #danmakus == 0 then
        show_message("弹幕内容为空，无法保存", 3)
        msg.verbose("弹幕内容为空，无法保存")
        COMMENTS = {}
        return false
    end

    -- 拼接为 XML 内容
    local xml = { '<?xml version="1.0" encoding="UTF-8"?><i>\n' }
    for _, d in ipairs(danmakus) do
       local time = d.time
       local type = d.type or 1
       local size = d.size or 25
       local color = d.color or 0xFFFFFF
       local text = d.text or ""

       text = text:gsub("&", "&amp;")
                  :gsub("<", "&lt;")
                  :gsub(">", "&gt;")
                  :gsub("\"", "&quot;")
                  :gsub("'", "&apos;")

       table.insert(xml, string.format('<d p="%s,%s,%s,%s">%s</d>\n', time, type, size, color, text))
    end
    table.insert(xml, '</i>')

    -- 写入 XML 文件
    local file = io.open(danmaku_out, "w")
    if not file then
       show_message("无法写入目标 XML 文件", 3)
       msg.info("无法写入目标 XML 文件: " .. danmaku_out)
       return false
    end
    file:write(table.concat(xml))
    file:close()
    show_message("转换 XML 弹幕成功： " .. danmaku_out, 3)
    msg.info("转换 XML 弹幕成功： " .. danmaku_out)
    return true
end

function convert_danmaku_to_ass_events(force)
    local per_source_lists = {}
    for url, source in pairs(DANMAKU.sources) do
        if not source.blocked and source.data then
            local get_cached_delay = make_delay_lookup(source)

            local list = {}
            for _, d in ipairs(source.data) do
                local base_time = d.orig_time or d.time
                if d.orig_time == nil then d.orig_time = base_time end
                local adjusted_time = base_time + get_cached_delay(base_time)
                local entry = {
                    orig_time = d.orig_time,
                    time = adjusted_time,
                    type = d.type,
                    size = d.size,
                    color = d.color,
                    text = d.text,
                    source = url,
                }
                if not is_blacklisted(d.text, black_patterns) then
                    table.insert(list, entry)
                end
            end

            if #list > 0 then
                table.sort(list, function(a, b) return a.time < b.time end)
                per_source_lists[#per_source_lists + 1] = list
            end
        end
    end

    local danmakus = {}

    local heap = new_min_heap()
    for li = 1, #per_source_lists do
        local lst = per_source_lists[li]
        if lst and #lst > 0 then
            heap.push({ time = lst[1].time, list_idx = li, pos = 1, entry = lst[1] })
        end
    end

    while true do
        local node = heap.pop()
        if not node then break end
        table.insert(danmakus, node.entry)
        local li = node.list_idx
        local next_pos = node.pos + 1
        local lst = per_source_lists[li]
        if lst and lst[next_pos] then
            heap.push({ time = lst[next_pos].time, list_idx = li, pos = next_pos, entry = lst[next_pos] })
        end
    end

    -- Repetition aggregation and the simultaneous-screen cap are independent controls.
    -- Never silently replace the user's merge interval with scrolltime when the cap is enabled.
    local merge_tolerance = tonumber(options.merge_tolerance) or 0
    danmakus = merge_duplicate_danmaku(danmakus, merge_tolerance)

    if #danmakus == 0 then
        if not force then
            show_message("该集弹幕内容为空，结束加载", 3)
            msg.verbose("该集弹幕内容为空，结束加载")
        end
        COMMENTS = {}
        return
    end

    if not force then
        msg.info("已解析 " .. #danmakus .. " 条弹幕")
    end

    local fontsize = tonumber(options.fontsize) or 55
    local scrolltime = tonumber(options.scrolltime) or 15
    local fixtime = tonumber(options.fixtime) or 5

    local res_x = 1920
    local res_y = 1080
    local layout_res_y = math.floor(res_y * (tonumber(options.displayarea) or 1.0))
    layout_res_y = math.max(fontsize, math.min(res_y, layout_res_y))

    local row_spacing = tonumber(options.row_spacing) or 1.2
    local roll_array = DanmakuArray:new(res_x, layout_res_y, fontsize, row_spacing)
    local top_array = DanmakuArray:new(res_x, layout_res_y, fontsize, row_spacing)

    -- 预处理弹幕，先计算时间段以便进行数量限制
    local pre_events = {}
    for _, d in ipairs(danmakus) do
        local time = d.type == 1 and math.floor(d.time + 0.5) or d.time
        local orig_time = d.type == 1 and math.floor(d.orig_time + 0.5) or d.orig_time
        local appear_time = time
        local danmaku_type = d.type

        local end_time = nil
        if danmaku_type >= 1 and danmaku_type <= 3 then
            end_time = appear_time + scrolltime
        elseif danmaku_type == 5 or danmaku_type == 4 then
            end_time = appear_time + fixtime
        end

        if end_time then
            table.insert(pre_events, {orig_time = orig_time, start_time = appear_time, end_time = end_time, danmaku = d})
        end
    end

    pre_events = apply_smart_density(pre_events, fontsize, scrolltime, tonumber(options.displayarea) or 1.0)

    if options.max_screen_danmaku > 0 then
        pre_events = limit_danmaku(pre_events, options.max_screen_danmaku)
    end

    local ass_events = {}
    for _, ev in ipairs(pre_events) do
        local d = ev.danmaku
        local appear_time = ev.start_time
        local danmaku_type = d.type
        local clean_text = ch_convert_cached(decode_html_entities(d.text))
        local merge_count = tonumber(d.merge_count) or 1
        local is_merged = merge_count > 1
        local font_scale = 1.0
        if merge_count >= 11 then
            font_scale = 1.3
        elseif merge_count >= 7 then
            font_scale = 1.2
        elseif merge_count >= 4 then
            font_scale = 1.1
        end
        local event_fontsize = is_merged and math.max(1, math.floor(fontsize * font_scale + 0.5)) or fontsize
        local text = ass_escape(clean_text)
        -- ASS 字幕模式直接使用内联字号；叠加层模式由 event.font_size 处理，避免双重放大。
        local font_size_tag = (is_merged and options.render_mode == "ass")
            and string.format("{\\fs%d}", event_fontsize) or ""

        -- 颜色从十进制转为 BGR Hex
        local color = math.max(0, math.min(d.color or 0xFFFFFF, 0xFFFFFF))
        local burst_color = duplicate_burst_color(d.merge_count)
        if burst_color then color = burst_color end
        local color_hex = string.format("%06X", color)
        local r = string.sub(color_hex, 1, 2)
        local g = string.sub(color_hex, 3, 4)
        local b = string.sub(color_hex, 5, 6)
        local color_text = string.format("{\\c&H%s%s%s&}", b, g, r)

        local style, effect
        local pos, move = nil, nil

        -- 滚动弹幕 (类型 1, 2, 3)
        if danmaku_type >= 1 and danmaku_type <= 3 then
            style = "R2L"
            local text_length = get_str_width(text, event_fontsize)
            local x1 = res_x + text_length / 2
            local x2 = -text_length / 2
            local y = get_position_y(fontsize, appear_time, text_length, res_x, scrolltime, roll_array)
            if y then
                effect = string.format("{\\move(%d, %d, %d, %d)}", x1, y, x2, y)
                move = {x1, y, x2, y}
            end

        -- 顶部弹幕 (类型 5)
        elseif danmaku_type == 5 then
            style = "TOP"
            local x = res_x / 2
            local y = get_fixed_y(fontsize, appear_time, fixtime, top_array, true)
            if y then
                effect = string.format("{\\pos(%d, %d)}", x, y)
                pos = {x, y}
            end

        -- 底部弹幕 (类型 4)
        elseif danmaku_type == 4 then
            style = "BTM"
            local x = res_x / 2
            local y = get_fixed_y(fontsize, appear_time, fixtime, top_array, false)
            if y then
                effect = string.format("{\\pos(%d, %d)}", x, y)
                pos = {x, y}
            end
        end

        if style and effect then
            text = effect .. color_text .. font_size_tag .. text
            local event = {
                orig_time = ev.orig_time,
                start_time = ev.start_time,
                end_time = ev.end_time,
                delay = ev.start_time - (ev.orig_time or ev.start_time),
                style = style,
                text = text,
                clean_text = clean_text,
                pos = pos,
                move = move,
                layer = (style == "R2L") and 0 or 1,
                source = d.source,
                font_size = is_merged and event_fontsize or nil,
            }
            table.insert(ass_events, event)
            COMMENTS = ass_events
        end
    end
end

-- Build a transient live stream from already validated input.  It deliberately
-- shares the static parser's conversion, blacklist, font measurement and lane
-- selection code, but never touches COMMENTS or DANMAKU.sources.
function build_live_ass_events(danmakus)
    local fontsize = tonumber(options.fontsize) or 55
    local scrolltime = tonumber(options.scrolltime) or 15
    local res_x, res_y = 1920, 1080
    local layout_res_y = math.floor(res_y * (tonumber(options.displayarea) or 1.0))
    layout_res_y = math.max(fontsize, math.min(res_y, layout_res_y))
    local row_spacing = tonumber(options.row_spacing) or 1.2
    local roll_array = DanmakuArray:new(res_x, layout_res_y, fontsize, row_spacing)
    local events = {}
    local density_input = {}
    for _, d in ipairs(danmakus or {}) do
        if type(d.time) == "number" and type(d.text) == "string" and not is_blacklisted(d.text, black_patterns) then
            density_input[#density_input + 1] = d
        end
    end
    density_input = apply_smart_density(density_input, fontsize, scrolltime, tonumber(options.displayarea) or 1.0)

    for _, d in ipairs(density_input) do
        if type(d.time) == "number" and type(d.text) == "string" then
            local clean_text = ch_convert_cached(decode_html_entities(d.text))
            local text = ass_escape(clean_text)
                local color = math.max(0, math.min(d.color or 0xFFFFFF, 0xFFFFFF))
            local color_hex = string.format("%06X", color)
            local color_text = string.format("{\\c&H%s%s%s&}", color_hex:sub(5, 6), color_hex:sub(3, 4), color_hex:sub(1, 2))
            local text_length = get_str_width(text, fontsize)
            local x1, x2 = res_x + text_length / 2, -text_length / 2
            local y = get_position_y(fontsize, d.time, text_length, res_x, scrolltime, roll_array)
            if y then
                local event = {
                    orig_time = d.orig_time or d.time,
                    start_time = d.time,
                    end_time = d.time + scrolltime,
                    delay = 0,
                    style = "R2L",
                    text = string.format("{\\move(%d,%d,%d,%d)}%s%s", x1, y, x2, y, color_text, text),
                    clean_text = clean_text,
                    move = {x1, y, x2, y},
                    layer = 0,
                    source = "live",
                }
                events[#events + 1] = event
            end
        end
    end
    return events
end
