# AI 设备助手（iOS + Windows + 云端）

一个能聊天、能看到思考过程、能操控设备的三端应用。

## 三个产物

| 产物 | 从哪来 | 用来做什么 |
|---|---|---|
| `AIAgent-unsigned.ipa` | Actions → `build-ipa` | 装到 iPad / iPhone，全能签签名安装 |
| `AI-Agent.exe` | Actions → `build-windows-agent` | 装到 Windows 电脑，让 AI 操控鼠标键盘 |
| 云端镜像 `server/cloud/Dockerfile` | 任意 Linux 服务器 | 一台一直开机的云端电脑 |
| 免费模型服务 `server/free-server` | 任意有 GPU/大内存的服务器 | App 里「不想花钱」按钮背后的小模型 |

## 手机端功能

- 首次进入取名 → 按名字生成图标 → 图标 + 名字的启动页 → 自动进主界面
- 新建对话；第一次对话里填 AI 密钥，自动校验，之后一直复用
- 聊天带 **思考块**：正在思考时自动展开，标「思考中…」，结束后折叠成「思考」，点一下展开看它怎么想
- 输入框左边一个按钮：选操控设备（本地手机 / 本地电脑 / 云端电脑），选择会记住
- 输入框上方一个按钮：**操控通道**（自动 / WDA / 巨魔 / 越狱 / 本机代理 / 引导），点一下循环切换，选择会记住
- 一个 **「不想花钱？点这里」** 按钮：进免费模型区，列出服务器上的所有小模型，选一个直接用
- 涉及敏感动作（执行命令、输入文字、打开链接、读剪贴板）会弹授权页，必须点「允许」

## 手机端真实点击的三条路

| 通道 | 真实能力 | 条件 |
|---|---|---|
| WDA | 真点击、真输入、真滑动、截屏、按 bundleId 启动 App | 装 WDA 包 + 设置里打开「开发者模式」和「启用 UI 自动化」 |
| 巨魔 | 全局触摸注入 | 系统 ≤ 17.0（你的 26.5 用不了） |
| 越狱 | 全局触摸注入 | 已越狱，root 权限 |
| 本机代理 | 蓝牙 HID 外设 / 辅助外设转发 | 本机 8765 端口有代理，外设当手 |
| 引导模式 | 不越狱兜底：屏幕高亮 + 一步步带你点 | 无需任何条件 |

通道是**真执行**的：WDA 走 `:8100` 的 XCUITest 接口，巨魔/越狱/外设都打到 `:8765` 的本机代理，代理不可用时自动降级到跳转或引导，不会假装成功。

## 电脑端

```bash
# Windows：双击 AI-Agent.exe
# 或源码运行
set AGENT_TOKEN=你的密钥
python agent/agent.py
```

启动后控制台会打印地址，在 App 设置里填 `http://电脑IP:8765`，密钥填同一个，就认上了。

支持动作：`screenshot` `click` `tap` `swipe` `type` `key` `launch` `shell` `open_url`。

## 云端电脑

```bash
docker build -f server/cloud/Dockerfile -t ai-agent-cloud .
docker run -d -p 8765:8765 -e AGENT_TOKEN=你的密钥 ai-agent-cloud
```

容器里带 Xvfb 虚拟屏幕，没有显示器也能点鼠标键盘。

## 免费小模型服务器（10TB 用户空间）

```bash
# 1. 装 Ollama，模型放用户空间
export OLLAMA_MODELS=/home/user/models
ollama serve &

# 2. 拉小模型
ollama pull qwen2.5:0.5b
ollama pull qwen2.5:1.5b
ollama pull llama3.2:1b
ollama pull deepseek-r1:1.5b

# 3. 起免费网关
cd server/free-server
pip install -r requirements.txt
uvicorn app:app --host 0.0.0.0 --port 8080
```

网关对外提供：

- `GET /api/models` — 模型清单（App 的「不想花钱」页读这个）
- `POST /v1/chat/completions` — OpenAI 兼容，不需要密钥，支持流式
- `GET /health` — 健康检查

App 里在「不想花钱」页填 `http://服务器IP:8080`，点「连接」就会列出所有模型，选一个立刻生效。

## 同密钥识别

手机 App 的密钥、电脑 exe 的 `AGENT_TOKEN`、云端容器的 `AGENT_TOKEN` 填同一个字符串，三边就互认；密钥不一致时电脑端返回 401，App 会提示「密钥对不上」。

## 自己打包

推送到 GitHub 后两个 workflow 自动跑：

- `build-ipa`：macOS 上 xcodegen + xcodebuild，产出未签名 IPA
- `build-windows-agent`：Windows 上 PyInstaller，产出单文件 exe

产物都在 Actions 页面里下载。
