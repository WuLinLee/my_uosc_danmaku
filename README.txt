# uosc_danmaku 弹幕密度与过滤菜单扩展

## 安装位置
将 ZIP 内的 portable_config 文件夹解压覆盖到：
E:\mpv-lazy\mpv-lazy\

保留目录结构；不要把 portable_config 再解压进另一个 portable_config 目录。
本包覆盖以下 5 个弹幕相关文件，并新增一个独立的 uosc 控制栏配置文件；不修改 mpv.conf、input_uosc.conf、字体、快捷键或其他脚本：
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

「弹幕样式」仍用于字体、透明度、描边、显示范围等视觉项目。密度和过滤项目集中放入独立菜单，避免与视觉样式混在一起。


## 布局说明
- 用户原配置中的 `displayarea=0.05` 代表只使用画面高度的 5%，并不是 50% 或“自动分散”。为符合本次希望接近浏览器端的宽区域布局，本包将该配置默认调整为 `displayarea=0.85`（使用约 85% 的画面高度）；如需更大区域，可在「弹幕样式」菜单调到 `1.0`。如果以前保存过 `uosc_danmaku_style.json` 且其中仍有 `displayarea=0.05`，已保存值会覆盖 conf 默认值，需要在菜单中把显示范围设为 `0.85` 后重新保存。
- 旧版滚动弹幕布局采用从上到下的 first-fit 轨道选择：只要顶部某行能够放下，就不会主动选择其他空行，因此可用区域很大时也可能看起来偏上。新版的“均匀分布弹幕轨道”会在碰撞检查后进行平衡选择。
- “弹幕行间距”只控制轨道垂直间隔，不改变字幕字号；默认 `1.2` 约在每行字号基础上增加 20% 的轨道高度。行间距越大，可用轨道数量越少，密度过高时仍可能有弹幕因无安全轨道而不显示。

## 黑名单兼容
旧的 options.blacklist_path 规则文件仍会读取，不会被菜单管理覆盖。新增菜单独立维护：
~~/script-opts/uosc_danmaku_blacklist.txt

文件每行一条规则。它使用插件原有的 Lua pattern 匹配规则，而不是 PCRE 正则表达式；普通词语可直接输入。菜单添加/删除规则后会重载规则并重新生成弹幕。新增的「屏蔽词过滤」开关会整体启用或暂停这两类规则。

已有的「从源添加弹幕」菜单仍负责屏蔽或解除屏蔽整条弹幕源。这与按文字匹配的屏蔽词不是同一个功能。

## 关于“折叠”
当前插件已有的轮子是“重复弹幕合并”：将相同文字、并符合类型/颜色分组和时间间隔条件的弹幕合并，并可能显示 xN 计数。新菜单只是开放这些既有能力的设置。此包没有伪装成支持任意相似评论的通用折叠、白名单优先、或可展开/收起的评论组；这些能力在本次提供的源代码中没有现成实现。

## 保留与兼容说明
- 用户提供的其余原有配置值均保留；为改善浏览器式全屏分布，本包有意将 `displayarea=0.05` 调整为 `displayarea=0.85`。另外添加 `density=100`、`row_spacing=1.2`、`balanced_lanes=yes`、`blacklist_enabled=yes`、`blacklist_menu_path`、`merge_without_style=no`。
- 已保存的 uosc_danmaku_style.json 现在可一并保存密度、行间距、均匀轨道开关、重复合并、同屏上限、跨样式合并和屏蔽词开关。
- 为保留原代码行为：当同屏上限大于 0 且合并间隔小于等于 0 时，排版阶段仍会以滚动时间作为“有效合并窗口”；现在不会因此偷偷改写菜单中显示的合并间隔数值。
- 智能密度算法是对浏览器版思路的 LuaJIT 兼容适配，不是完整 Unicode NFKC 的逐字节等价移植。

## 验证边界
本次文件已通过本地 Lua 语法加载检查（使用系统 Lua 5.4 做静态语法检查），但当前环境不能启动用户的实际 mpv/uosc，因此仍需在用户机器上验证真实菜单事件、播放时过滤效果和直播刷新行为。

## 控制栏快捷按钮
新增 `portable_config/script-opts/uosc.conf`，将 `button:danmaku_menu` 放在 `<has_chapter>chapters` 后面。uosc 会显示一个图标按钮，悬停提示为「弹幕设置」；点击后打开插件原有的「弹幕设置」总菜单，再进入「弹幕密度与过滤」或「弹幕样式」即可。按钮使用 uosc 官方的 `set-button` + `button:<name>` 扩展方式；插件中已有 `danmaku_menu` 注册，无需新增独立 Lua 脚本。

本包没有覆盖 `portable_config/script-opts.conf`，以免丢失用户集中配置的其他脚本选项。新文件 `script-opts/uosc.conf` 是 uosc 的标准独立选项文件。如果用户已有个人定制的同名 `uosc.conf`（目录树中原本没有），应先备份并把本包的 `controls=` 这一行合并进去。
