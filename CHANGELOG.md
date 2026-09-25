# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [1.0.0] — 2026-09-25

首个正式发布。目标环境：**Windows 10/11 + Docker Desktop + agent-swarm v1.154.0**。

### 新增

- **桌面控制台** `gui/AgentSwarm.ps1`
  - WPF 深色主题，琥珀色强调，五个状态灯（宿主代理 / Docker / API / AI 员工 / 仪表盘）
  - 主按钮「开始对话」，另有打开工作台、启动/修复服务、停止全部、刷新状态、打开文件夹
  - 单实例守卫：命名 Mutex + `FindWindow`/`SetForegroundWindow`，重复点图标只顶到前台
  - 「停止全部」二次确认 MessageBox 防误触
  - 后台任务经 `Start-Job` + `DispatcherTimer` 流式输出到日志区，不卡界面
- **对话窗口** `web/chat.html`
  - 零依赖单页，Vite `public/` 同源伺服，`/api` 走代理，无 CORS
  - 连续记忆：每条消息用 `parentTaskId` 串成会话链
  - 运行中插话：`POST /api/tasks/{id}/steer`（`mode: steer`）
  - `output` 为空时从 `session-logs` 提取最后一段文本作为兜底
  - 等待 steering 消息 `handled` 后重新取结果，避免读到被覆盖前的旧值
  - `localStorage` 持久化 + 刷新后自动恢复未完成任务轮询
  - 轻量 Markdown（代码块 / 行内代码 / 粗体 / 链接 / 列表）
  - API Key 运行时注入（`/swarm-config.js`），页面本身零密钥
- **安装向导** `setup.ps1`
  - 自动定位 agent-swarm 源码、Python、Edge
  - 四种 harness：复用本机 OpenCode 凭据 / OpenRouter / Anthropic / OpenAI
  - 自动生成本地 API Key（随机 64 位十六进制）、`encryption_key`、`config.json`、`.env`
  - 把对话页装进 `apps/ui/public/`，生成图标，创建两个桌面快捷方式
  - 支持 `-NonInteractive` 与参数化
- **控制脚本** `gui/swarm-ctl.ps1`
  - `start` / `stop` / `status` / `open` / `open-chat` / `verify`
  - 全路径来自 `config.json`，无硬编码
  - 输出以 `READY` / `FAILED` / `STOPPED` / `VERIFY_OK` 结尾，便于脚本判断
- **端到端自检** `verify.ps1`
  - 五项服务探测 + 真的发一个任务并校验回复
  - 示范了 PowerShell 5.1 正确发送 UTF-8 的写法
- **镜像源补丁版 Dockerfile** `deploy/dockerfiles/`
  - `FROM` 加镜像源前缀
  - worker：带 bun CLI、`npm i -g opencode-ai`、去掉不可达 stage、skills 走免费源、装 `build-essential`
  - 覆盖时自动备份原件为 `.agent-swarm-orig`
- 文档：部署手册、对话原理、排障手册

### 已验证

- 连续记忆：记「紫色老虎」→ 下一轮准确答出
- 运行中插话：数 1–40，中途补「只保留奇数」→ 结果 1,3,5,…,39
- 中文输入输出全链路正常
- 控制台与对话页均以 Edge `--app` 无边框窗口打开
- 重复启动保持单实例
- 密钥未进入版本库（`config.json` / `.env` / `auth.json` / `swarm-config.js` 均已忽略）
