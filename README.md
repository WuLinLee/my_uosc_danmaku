## uosc_danmaku 弹幕增强扩展 2026.10.12

## 安装位置

将 [WuLinLee/my_uosc_danmaku](https://github.com/WuLinLee/my_uosc_danmaku) 中的 `portable_config` 文件夹解压并覆盖到：
E:\mpv-lazy\mpv-lazy\\

保留目录结构；不要把 portable_config 再解压进另一个 portable_config 目录。
这次更新涉及以下 5 个弹幕脚本和配置文件，另新增一个 uosc 控制栏配置文件。`mpv.conf`、`input_uosc.conf`、字体、快捷键及其他脚本均未改动：

- portable_config/scripts/uosc_danmaku/modules/menu.lua
- portable_config/scripts/uosc_danmaku/modules/parse.lua
- portable_config/scripts/uosc_danmaku/modules/options.lua
- portable_config/scripts/uosc_danmaku/modules/style.lua
- portable_config/script-opts/uosc_danmaku.conf
- portable_config/script-opts/uosc.conf（新增：仅控制 uosc 控制栏排列）

## 菜单入口
重启 mpv 后打开原有「弹幕设置」总菜单，进入新增的「弹幕密度与过滤」：

1. 智能弹幕密度：0–100。100 不进行智能密度筛选；数值越低，在局部弹幕拥挤时筛选越积极。
2. 弹幕行间距：1.0–2.0 倍字号，默认 1.2；数值越高，轨道之间留出的垂直间隔越大。
3. 均匀分布弹幕轨道：默认开启。排版先检查碰撞，再优先使用未使用过且靠近画面中心的轨道，随后复用最久未使用的可用轨道，避免旧版 first-fit 总是从上到下堆叠。
4. 重复弹幕合并间隔：-1 到 30 秒。-1 表示关闭合并；0 只合并时间相同的重复内容；正数按该秒数合并重复内容。
5. 同屏弹幕上限：0–500。0 表示不限；大于 0 时沿用原有的同屏数量限制算法。
6. 跨颜色/类型合并重复弹幕：开启后，同一内容即使类型或颜色不同也可进入同一重复合并组。
7. 屏蔽词过滤：启用或暂停屏蔽词规则。
8. 管理屏蔽词规则：在菜单顶部搜索栏输入规则并回车添加；每条规则右侧的删除动作可移除该规则。
9. 保存当前样式和过滤设置 / 清除已保存的样式和过滤设置。

字体、透明度、描边和显示范围等外观选项仍在「弹幕样式」中；弹幕密度、合并和屏蔽词设置位于「弹幕密度与过滤」菜单。「粗体」有 `false`、`true` 和 `Big` 三档，`Big` 会请求 ASS 的 900 字重；实际粗细取决于所选字体是否支持该字重。


## 布局说明
- `displayarea=0.05` 表示弹幕只使用画面高度的 5%。默认值现在是 `0.85`，即使用约 85% 的画面高度；想让弹幕覆盖整个画面，可在「弹幕样式」中设为 `1.0`。如果旧的 `uosc_danmaku_style.json` 里还保存着 `displayarea=0.05`，它会覆盖配置文件里的默认值。请在菜单中改成 `0.85` 并重新保存。
- 旧版滚动弹幕布局采用从上到下的 first-fit 轨道选择：只要顶部某行能够放下，就不会主动选择其他空行，因此可用区域很大时也可能看起来偏上。新版的“均匀分布弹幕轨道”会在碰撞检查后进行平衡选择。
- “弹幕行间距”只控制轨道垂直间隔，不改变字幕字号；默认 `1.2` 约在每行字号基础上增加 20% 的轨道高度。行间距越大，可用轨道数量越少，密度过高时仍可能有弹幕因无安全轨道而不显示。

## 黑名单兼容
旧配置中的 `blacklist_path` 规则文件仍会读取，也不会被菜单里的规则管理覆盖。菜单新增的规则单独保存在：
~~/script-opts/uosc_danmaku_blacklist.txt

文件每行一条规则。它使用插件原有的 Lua pattern 匹配规则，而不是 PCRE 正则表达式；普通词语可直接输入。菜单添加/删除规则后会重载规则并重新生成弹幕。新增的「屏蔽词过滤」开关会整体启用或暂停这两类规则。

已有的「从源添加弹幕」菜单仍负责屏蔽或解除屏蔽整条弹幕源。这与按文字匹配的屏蔽词不是同一个功能。

## 关于“折叠”
插件目前支持的是“重复弹幕合并”：相同文字的弹幕在符合类型、颜色和时间间隔条件时会被合并，并可能显示 xN 计数。任意相似评论自动折叠、白名单优先，以及评论组展开/收起目前都未实现。

## 保留与兼容说明
- 其他原有配置值保持不变。默认显示范围从 `displayarea=0.05` 调整为 `displayarea=0.85`；新增的配置项包括 `density=100`、`row_spacing=1.2`、`balanced_lanes=yes`、`blacklist_enabled=yes`、`blacklist_menu_path` 和 `merge_without_style=no`。
- 已保存的 uosc_danmaku_style.json 现在可一并保存密度、行间距、均匀轨道开关、重复合并、同屏上限、跨样式合并和屏蔽词开关。
- 当同屏上限大于 0、合并间隔小于或等于 0 时，排版阶段仍按原有逻辑使用滚动时长作为实际合并窗口；菜单里显示的合并间隔不会因此被改写。
- 智能密度算法是对浏览器版思路的 LuaJIT 兼容适配，不是完整 Unicode NFKC 的逐字节等价移植。

## 验证边界
使用系统 Lua 5.4 做过静态语法检查。由于无法在这里启动 mpv/uosc，菜单交互、播放时的过滤效果和直播刷新仍需在实际环境中测试。

## 控制栏快捷按钮
新增 `portable_config/script-opts/uosc.conf`，将 `button:danmaku_menu` 放在 `<has_chapter>chapters` 后面。uosc 会显示一个图标按钮，悬停提示为「弹幕设置」；点击后打开插件原有的「弹幕设置」总菜单，再进入「弹幕密度与过滤」或「弹幕样式」即可。按钮使用 uosc 官方的 `set-button` + `button:<name>` 扩展方式；插件中已有 `danmaku_menu` 注册，无需新增独立 Lua 脚本。

没有改动 `portable_config/script-opts.conf`，以免覆盖其中的其他脚本配置。`portable_config/script-opts/uosc.conf` 是 uosc 单独使用的配置文件；如果本机已经有同名 `uosc.conf`，先备份，再把这里的 `controls=` 行合并进去。
