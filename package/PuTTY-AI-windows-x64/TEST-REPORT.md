# PuTTY AI Windows x64 测试报告

测试日期：2026-07-17  
构建类型：MSVC x64 Release  
基础版本：PuTTY 0.84

## 结果

- `putty` Release 目标：通过，输出 `putty-ai.exe`。
- `test_terminal.exe`：通过；包含新增的最近终端上下文提取与尾部裁剪回归测试。
- `test_lineedit.exe`：通过。
- AI 端到端测试：通过；验证 OpenAI Chat Completions 兼容请求、响应 JSON、Markdown、代码块、命令识别和终端回填状态。
- 正常命令确认：通过；单次确认。
- 危险命令确认：通过；`rm -rf` 模式触发第二次确认。
- 自动执行保护：通过；回填不附带 CR/LF，不自动发送 Enter。
- 元数据审计：通过；日志未包含测试问题、回复、命令正文、Bearer/API Key。
- GUI：原生 AI 子控件全部创建，真实 `WM_KEYDOWN` 可转换为编辑框输入，DPI 缩放下布局正常；附带 `putty-ai-ui.png`。
- 测试隔离：集成测试结束后恢复原有 AI 注册表配置，不向发布版遗留本地 mock 端点或模型名。
- 公开 SSH 服务：通过；`putty-ai.exe` 连接 `ssh.github.com:443`，观察到主机密钥协商并到达 `publickey` 认证阶段。测试禁用了 Pageant 和连接共享，未使用用户凭据；最终的认证失败是预期结果。

AI HTTP 链路使用本地兼容模拟服务完成端到端验证，因为测试环境未提供第三方模型 API Key。自定义公网模型服务可在程序 Settings 中配置。

## 运行依赖

发布目录包含应用本地 `vcruntime140.dll`。其余依赖均为 Windows 10/11 系统组件，包括 WinHTTP、UCRT、User32、GDI32、Comdlg32 和 Advapi32。

## SHA-256

```text
E4038E8C7713E2E887C3ADBFBFF2E6FFE15B7E78F70493894D6307F2DCCCC6CC  putty-ai.exe
D5E4D9A3E835FA679450145D6A7D94E36573A509317111904D9B3712C30D9066  vcruntime140.dll
```
