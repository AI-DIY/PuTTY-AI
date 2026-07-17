<div align="center">

# PuTTY AI

### 让 SSH 终端听懂自然语言

基于 [PuTTY](https://www.chiark.greenend.org.uk/~sgtatham/putty/) 的 AI 增强型 SSH 客户端，  
把终端上下文、故障分析、命令生成与执行确认集中在同一个窗口中。

![Platform](https://img.shields.io/badge/platform-Windows-0078D4?style=flat-square)
![PuTTY](https://img.shields.io/badge/PuTTY-0.84-5C2D91?style=flat-square)
![Language](https://img.shields.io/badge/language-C-A8B9CC?style=flat-square)
![Status](https://img.shields.io/badge/status-preview-blue?style=flat-square)

</div>

> [!IMPORTANT]
> 项目目前处于预览阶段。Windows 客户端已经集成 AI 侧边栏、终端上下文、兼容模型接口、命令确认与安全控制。AI 输出仍可能出错，执行任何生成命令前必须人工复核，暂不建议直接用于无人值守生产操作。

## 项目简介

开发、运维和技术支持人员经常需要在 SSH 终端、搜索引擎与 AI 工具之间反复切换：复制报错、补充上下文、生成命令，再粘贴回终端执行。这个过程不仅影响效率，还容易遗漏关键信息或误执行命令。

PuTTY AI 希望在保留 PuTTY 原有使用习惯的基础上，为终端增加一个可感知当前会话上下文的 AI 助手。用户可以直接用自然语言描述问题，由 AI 辅助分析日志、解释命令、定位故障并生成操作建议。

## 目标能力

- **终端上下文感知**：按需读取当前 SSH 会话内容，减少手动复制和补充背景信息。
- **自然语言交互**：直接询问报错原因、系统状态、排查思路或 Linux 命令用法。
- **故障与日志分析**：结合终端输出总结异常信息，并给出可验证的排查步骤。
- **命令生成与解释**：生成候选命令，同时说明用途、参数和潜在影响。
- **确认后回填终端**：命令先展示、后确认，再发送到 SSH 终端，降低误操作风险。
- **兼容自定义模型**：计划支持 OpenAI Chat Completions 兼容接口，方便接入不同模型服务。

## 目标交互流程

```mermaid
flowchart LR
    A["SSH 终端输出"] --> B["提取必要上下文"]
    C["用户自然语言提问"] --> D["AI 分析与生成建议"]
    B --> D
    D --> E{"是否包含命令？"}
    E -- 否 --> F["展示分析结果"]
    E -- 是 --> G["解释命令与风险提示"]
    G --> H{"用户确认"}
    H -- 确认 --> I["回填到终端"]
    H -- 取消 --> F
```

## 适用场景

| 场景 | 示例问题 |
| --- | --- |
| 故障排查 | “这个服务为什么启动失败？” |
| 日志分析 | “帮我总结这段日志里的关键异常。” |
| 系统检查 | “找出占用磁盘空间最大的目录。” |
| 命令学习 | “解释这条命令每个参数的作用。” |
| 日常运维 | “给出安全重启该服务的步骤。” |

主要面向开发工程师、运维工程师、测试人员、技术支持人员，以及正在学习 Linux 和 SSH 的用户。

## 从源码构建

仓库中的 Windows `putty` 目标会生成带原生 AI 侧边栏的 `putty-ai.exe`。实现仅依赖 Windows 自带的 WinHTTP 和 Rich Edit，不需要额外运行时或浏览器组件。

### 环境要求

- Windows 10/11
- CMake 3.7 或更高版本
- Visual Studio 2022，并安装“使用 C++ 的桌面开发”工作负载

### 构建步骤

```powershell
cmake -S putty-src -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release --target putty
```

构建完成后，可执行文件通常位于：

```text
build\Release\putty-ai.exe
```

仓库也提供了会自动定位 Visual Studio 2022 Build Tools 的构建脚本：

```powershell
scripts\build-windows.cmd
```

## AI 面板使用

建立 SSH 会话后，右侧会显示 PuTTY AI 面板：

1. 点击 **Settings**，填写 OpenAI Chat Completions 兼容端点、模型名和 API Key。
2. API Key 只保存在当前进程内，不会写入注册表；端点、模型、上下文长度和知识文件路径会保存到当前用户配置。
3. 输入问题，可选择是否附带最近终端上下文。默认最多读取 12,000 个字符，可配置范围为 1,000～64,000。
4. 上下文和可选知识文件发送前会进行尽力而为的密码、令牌、授权头和私钥脱敏。
5. 回复中的 Markdown 标题、列表和代码块会显示在会话区。识别到命令后可点击 **Fill command**；程序只把命令回填到终端，不会自动发送 Enter。
6. 删除、格式化、停服、改权限等高风险命令需要两次确认。

也可以通过环境变量提供当前会话的默认值：

```powershell
$env:OPENAI_BASE_URL = "https://example.com/v1"
$env:OPENAI_MODEL = "your-model"
$env:OPENAI_API_KEY = "your-session-only-key"
```

`OPENAI_BASE_URL` 可以是服务根地址或完整的 `/chat/completions` 地址。环境变量中的 API Key 同样不会持久化。

### 本地知识与审计

- Settings 中可选择一个不超过 256 KiB 的 UTF-8/UTF-16 `.md` 或 `.txt` 文件作为本地知识参考；内容同样会先经过敏感字段脱敏。
- 程序默认记录不含问题、回复、上下文、命令正文和 API Key 的元数据审计日志，位置为 `%LOCALAPPDATA%\PuTTY AI\audit.log`。日志只包含时间、事件类型、模型端点主机和风险级别等信息。

## 测试与验证

```powershell
# PuTTY 终端与行编辑回归测试
build\Release\test_terminal.exe
build\Release\test_lineedit.exe

# 本地兼容模型 + 远程终端端到端测试
powershell -ExecutionPolicy Bypass -File tests\run-integration.ps1

# 危险命令二次确认测试
powershell -ExecutionPolicy Bypass -File tests\run-integration.ps1 -Dangerous

# 公开 SSH 服务握手测试（不使用本机凭据）
powershell -ExecutionPolicy Bypass -File tests\run-remote-ssh.ps1
```

远程验证默认连接 `ssh.github.com:443`，禁用 Pageant 和连接共享，只验证主机密钥协商及服务端进入 `publickey` 认证阶段。未提供凭据时出现 `No supported authentication methods available (server sent: publickey)` 是预期结果，表示 SSH 连接和握手已经成功到达认证阶段。

打包产物位于 `package/PuTTY-AI-windows-x64.zip`，包含 `putty-ai.exe`、应用本地 VC Runtime、许可证和测试报告。

## 开发计划

- [x] 导入 PuTTY 0.84 源码
- [x] 明确产品定位与核心交互流程
- [x] 实现终端右侧 AI 交互面板
- [x] 实现会话上下文提取与长度控制
- [x] 接入 OpenAI Chat Completions 兼容接口
- [x] 支持 Markdown、代码块与命令展示
- [x] 支持命令确认和一键回填
- [x] 增加危险命令识别与二次确认
- [x] 增加敏感信息脱敏与隐私控制
- [x] 增加本地知识文件、元数据操作审计等扩展能力

## 项目结构

```text
putty-ai/
├── putty-src/              # PuTTY 0.84 与 PuTTY AI 源代码
│   └── windows/ai.c        # AI 面板、模型调用、安全与审计实现
├── package/                # 构建后生成的 Windows 发布包
└── readme.md               # 项目说明
```

## 安全与隐私

AI 生成的命令可能不准确，也可能不适合当前环境。执行任何命令前，请确认目标主机、权限范围和命令影响，尤其要谨慎处理删除文件、修改权限、停止服务等高风险操作。

在模型接入功能完成后，项目将优先提供上下文范围控制、敏感信息脱敏和危险命令确认机制。即使如此，也不应向不受信任的模型服务发送密码、私钥、令牌或其他机密信息。

## 参与贡献

欢迎通过 Issue 提交使用场景、功能建议和问题反馈，也欢迎参与 AI 面板、模型接入、安全策略与文档等方向的开发。

提交代码前，请尽量确保改动范围清晰，并附上必要的构建或测试说明。

## 致谢与许可证

本项目基于 [PuTTY](https://www.chiark.greenend.org.uk/~sgtatham/putty/) 0.84 源码进行探索和开发，并非 PuTTY 官方项目。

仓库中的 PuTTY 源代码遵循其原始许可条款，详情请查看 [putty-src/LICENCE](putty-src/LICENCE)。

---

<div align="center">

如果这个方向对你有帮助，欢迎 Star 项目并参与讨论。

</div>
