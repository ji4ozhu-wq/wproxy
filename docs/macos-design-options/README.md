# macOS UI 设计候选稿（2026-11-22）

用户反馈：连接页"很丑"、文字偏小、多个页面空白很多。这里给出 **3 套 macOS 原生语言/原生控件**的
设计稿供选择。**页面骨架与信息顺序不变**（侧边栏 连接/节点/设置 + 详情页），只改视觉语言、控件尺寸、
字号与间距；iPhone/iPad 不受影响（实现时全部放 `#if os(macOS)`）。

## 三套设计

| 方案 | 语言 | 关键特征 | 连接按钮位置 |
|---|---|---|---|
| **A · macOS 系统设置风** | 浅灰窗口 + 白色分组卡片 + 系统蓝，最接近系统设置 | 大标题 30–32pt、正文 15.5–16.5pt、行高 52–56pt、卡片圆角 12、按钮 54pt | 页面内大按钮 |
| **B · Liquid Glass 仪表盘** | macOS 26 液态玻璃：渐变底、通透卡片、蓝色主控 | 标题 38pt、正文 16.5pt、行高 60pt、卡片圆角 18、按钮 62pt 带蓝光；本次会话 = 4 个指标格（数字 32pt） | 页面内大按钮 |
| **C · 原生工具栏风** | 类 Proxyman/Surge 工具 App：白色内容区 + 窗口工具栏 | 标题 32pt、正文 15.5pt、行高 50pt、卡片 1px 描边；本次会话 2×2 数据格（数字 19pt）；工具栏内置状态胶囊 + 连接按钮 | 窗口工具栏（唯一结构变化） |

三套都把首页内容改为**垂直居中**，减少底部大片空白；设置页字号/行高同步放大。
所有 mockup 均以 1320×840 窗口（截图 1400×900）渲染。

## 文件

- 首页设计稿：`style-a-system-settings.png`、`style-b-liquid-glass.png`、`style-c-toolbar.png`
- 设置页设计稿：`style-a-system-settings-settings.png`、`style-b-liquid-glass-settings.png`、`style-c-toolbar-settings.png`
- 设置页对比：`settings-comparison.png`

## 选定后的实现映射（macOS-only）

1. `Theme` 增加 macOS 字体/间距档位：body 15.5、footnote 12.5、title 30–32、行高 52–56、卡片圆角 12–18。
2. 首页：内容限宽居中（A/B：760–880pt）+ 垂直居中；B 的指标格用 4 列等分；
   C 需要 macOS 专用 `ToolbarItem`（连接按钮 + 状态胶囊），并移除页面内大按钮。
3. 设置/节点/订阅/表单复用 `WujiSettingsList`，按选定风格调卡片/描边/配色。
4. 不变：iOS 分支、隧道/路由逻辑、全部 sheet 尺寸与底部操作栏规则。
