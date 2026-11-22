# macOS 连接页 + 设置页 · 三种参考风格设计稿

每条风格各一套：**连接页 + 设置页**（`*-set.png` 是两页拼图；也可单独看 `*-home.png` / `*-settings.png`）。
三种风格采用同一套扁平布局骨架（单列、分区面板、无阴影、无渐变），只替换视觉语言。
窗口统一按 1200×760 渲染（截图含桌面背景 1400×900）。

## 1 · DeepSeek Harness 风格
参考本机 DeepSeek Harness GUI：浅色界面、极浅灰侧栏、白色内容、蓝色强调、12pt 圆角面板、细边框、悬浮淡色选中。
- 侧栏 `#F7F7F8` / 主区 `#FFFFFF` / 边框 `#E9E9ED` / 强调 `#4D6BFE`
- 选中行：`#EBEDFB` 底 + 蓝色文字
- 主按钮：蓝底白字 8pt 圆角；文本 14.5；标题 23
- 文件：`dsh-set.png`、`dsh-home.png`、`dsh-settings.png`

## 2 · ChatGPT 风格
参考 ChatGPT 浅色界面：白底、极浅灰侧栏、几乎无蓝，黑色主按钮、绿色状态点、12pt 圆角、极细边框。
- 侧栏 `#F9F9F9` / 主区 `#FFFFFF` / 边框 `#E5E5E5` / 主按钮 `#0D0D0D`
- 状态点 `#10A37F`，开关绿 `#10A37F`
- 行高 48；文本 14.5；标题 23
- 文件：`gpt-set.png`、`gpt-home.png`、`gpt-settings.png`

## 3 · macOS 设置界面风格
参考 macOS 系统设置：系统灰窗口、白色分组卡片、0.5px 细分割线、8pt 圆角、系统蓝。
- 窗口 `#ECECEC` / 卡片 `#FFFFFF` / 边框 `rgba(0,0,0,.16)` / 强调 `#0A6FF5`
- 选中行：系统蓝填充白字；开关 `#34C759`
- 行高 46；文本 14.5；标题 23
- 文件：`mac-set.png`、`mac-home.png`、`mac-settings.png`

## 说明
- 当前 App 的 UI **未做修改**（设计稿阶段；直接改动的代码已回滚）。
- 选定一套（或混搭，例如「Harness 配色 + macOS 灰底卡片」）后，只改 macOS 分支实现，iPhone/iPad 不变。
