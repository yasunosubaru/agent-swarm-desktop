# Agent Swarm Desktop

> 把 [agent-swarm](https://github.com/desplega-ai/agent-swarm) 变成一个**双击就能用的桌面应用**：
> 一个漂亮的深色控制台 + 一个能连续对话、随时插话补充的聊天窗口。

面向 **Windows 10/11 + Docker Desktop**，实测版本 **agent-swarm v1.154.0**。

---

## 为什么需要它

agent-swarm 自带一个侧边栏 `Chat` 页面，但**在 v1.154.0 里是半成品**：

```
GET /api/channels  →  404
```

后端源码里甚至留着官方注释：

```ts
// Re-add when /api/channels routes are created.
```

所以点进去永远只有一句 “Select a channel”。本项目用 agent-swarm **真实存在**的任务/会话 API
重新做了一个对话界面，并把它和启动、停止、状态查看整合成一个桌面应用。

---

## 效果

| | |
|---|---|
| 🖥️ **桌面控制台** | 五个状态灯（宿主代理 / Docker / API / AI 员工 / 仪表盘）、一键启动、停止、实时日志。深色主题、琥珀色强调。 |
| 💬 **对话窗口** | 像聊天软件一样说话。**连续记忆**、**运行中可插话**、回车发送、点击复制。 |
| 🔇 **无浏览器边框** | 用 Edge `--app` 模式打开，看起来就是原生应用。 |
| 🔌 **接入 OpenCode** | 一条命令接上 OpenCode 的 MCP，之后**直接在 OpenCode 对话里派活**，6 个工具（发任务/查任务/中途插话/取消）。 |
| 🔒 **单实例** | 重复点图标不会开出第二个窗口，只会把已有窗口切到前台。 |
| 🛡️ **防误触** | “停止全部”有二次确认；关闭窗口不会停服务。 |

### 连续记忆（实测）

```
你  → 请记住一个暗号：紫色老虎。只回复 OK。
AI  → OK
你  → 刚才的暗号是什么？只回复那四个字。
AI  → 紫色老虎
```

### 运行中插话（实测）

```
你  → 请从 1 数到 40，每个数字单独一行。      ← AI 正在干活
你  → 补充要求：只保留奇数，去掉所有偶数。      ← 中途插话
AI  → 1 3 5 7 9 … 39                        ← 采纳了补充
```

---

## 快速开始

### 前置条件

- Windows 10/11
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) 已安装
- agent-swarm 源码（[Releases](https://github.com/desplega-ai/agent-swarm/releases) 下载解压）
- Node.js 20+ / npm（用于跑仪表盘开发服务器）
- Python 3（只用于那个很小的宿主代理，可选但推荐）

### 三步

**1. 运行安装向导**

```powershell
git clone https://github.com/yasunosubaru/agent-swarm-desktop.git
cd agent-swarm-desktop
powershell -ExecutionPolicy Bypass -File .\setup.ps1
```

向导会问你三件事：源码目录在哪、用哪个 harness（凭据）、要不要用镜像源版 Dockerfile。
其余的（本地 API Key、加密密钥、config.json、对话页、图标、桌面快捷方式）它自己搞定。

**2. 构建镜像（只需一次，10–30 分钟）**

```powershell
docker build -f "<源码目录>\Dockerfile"        -t agent-swarm:local       "<源码目录>"
docker build -f "<源码目录>\Dockerfile.worker" -t agent-swarm-worker:local --target worker-slim "<源码目录>"
```

> 容器还要用 `ghcr.dockerproxy.net` / `quay.nju.edu.cn` / `dockerproxy.net` 拉取几个基础镜像。
> 如果你所在网络直连这些仓库没问题，setup 时对 Dockerfile 补丁选 `n` 即可。

**3. 双击桌面图标**

| 图标 | 行为 |
|---|---|
| **Agent Swarm 对话** | 拉起全部服务 → 直接进聊天窗口（日常用这个） |
| **Agent Swarm** | 拉起全部服务 → 打开控制台窗口 |

### 自检

```powershell
powershell -ExecutionPolicy Bypass -File .\verify.ps1
```

会检查 5 项服务，并**真的发一个任务**给 AI 团队，确认端到端可用（退出码 0 = 全通过）。

---

## 接入 OpenCode（可选，但很好用）

```powershell
powershell -ExecutionPolicy Bypass -File .\mcp\connect-opencode.ps1
```

重启 OpenCode 之后，工具栏里会多出 6 个工具：

```
agent-swarm__send-task          派活
agent-swarm__get-tasks          查任务
agent-swarm__get-task-details   任务详情
agent-swarm__steer-task         干活时插话
agent-swarm__cancel-task        取消
agent-swarm__task-action        挪 backlog
```

然后直接说人话就行：

> 用 agent-swarm 派个活：把这个需求实现掉

实测链路：`OpenCode → MCP(/mcp-user) → 任务池 → Coder 容器 → opencode → 结果回传`。

> ⚠️ 新装后**第一次**派活大概率失败（`opencode session create timed out`），
> 这是冷容器首次建会话要装插件拉模型、30 秒预算不够导致的，再发一次就好了。
> 细节见 [OPENCODE-MCP.md](docs/OPENCODE-MCP.md)。

---

## 目录结构

```
agent-swarm-desktop/
├── setup.ps1                 首次运行安装向导
├── verify.ps1                端到端自检（含真实任务往返）
├── config.example.json       config.json 的格式参考
├── config.json               ← 本地生成，已 gitignore
├── gui/
│   ├── AgentSwarm.ps1        WPF 深色控制台（桌面应用本体）
│   ├── swarm-ctl.ps1         start / stop / status / open / open-chat / verify
│   ├── proxy_supervisor.ps1  守护宿主 CONNECT 代理
│   ├── host_proxy.py         极简 HTTP CONNECT 代理（给 Docker VM 用）
│   ├── make-icon.ps1         从 PNG 生成多尺寸 .ico
│   └── create-shortcuts.ps1  创建两个桌面快捷方式
├── mcp/
│   └── connect-opencode.ps1  把 AI 团队接进 OpenCode（MCP 用户端点）
├── web/
│   ├── chat.html             对话页（会被复制进 apps/ui/public/）
│   └── swarm-config.example.js
├── deploy/
│   ├── docker-compose.swarm.yml
│   ├── .env.example
│   ├── dockerfiles/          打过镜像源补丁的 Dockerfile / Dockerfile.worker
│   └── opencode-config/      凭据挂载目录（auth.json 已 gitignore）
├── assets/                   logo.png + agent-swarm.ico
└── docs/
    ├── DEPLOYMENT.md         完整部署手册
    ├── CHAT.md               对话页原理（parentTaskId / steer / session-logs）
    ├── OPENCODE-MCP.md       接入 OpenCode（含冷启动与属主两个坑）
    └── TROUBLESHOOTING.md    排障手册
```

---

## 安全说明

仓库里**不含任何真实凭据**，`.gitignore` 已排除：

| 文件 | 内容 |
|---|---|
| `config.json` | 本机绝对路径 |
| `deploy/.env` | 本地 API Key、provider Key |
| `deploy/encryption_key` | 数据库加密密钥 |
| `deploy/opencode-config/auth.json` | 你的 OpenCode 登录凭据 |
| `apps/ui/public/swarm-config.js` | 注入给对话页的 API Key |

> 对话页 `chat.html` 本身是**零密钥**的：它在运行时读取 `/swarm-config.js`。
> 这就是它可以被公开提交的原因。

如果你曾经把 Key 提交过，**先去 GitHub 吊销并轮换**——删文件不等于作废密钥。

---

## 文档

- [完整部署手册](docs/DEPLOYMENT.md)
- [对话页是怎么工作的](docs/CHAT.md)
- [接入 OpenCode（用户 MCP）](docs/OPENCODE-MCP.md)
- [排障手册](docs/TROUBLESHOOTING.md)
- 上游项目：[desplega-ai/agent-swarm](https://github.com/desplega-ai/agent-swarm)

## License

MIT，见 [LICENSE](LICENSE)。

本项目是 agent-swarm 的**周边工具**，不包含 agent-swarm 本身；
`deploy/dockerfiles/` 里是针对受限网络的本地补丁副本，上游文件版权归原作者所有。
