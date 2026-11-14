"""电脑 / 云端控制代理：接收 AI 的指令，真实操作鼠标键盘、截屏、开程序。

Windows 双击 exe 启动；Linux 用 python agent.py 启动。
环境变量：
    AGENT_TOKEN  与手机 App 里填的密钥一致
    AGENT_PORT   默认 8765
"""
import base64
import io
import os
import platform
import subprocess
import sys
import webbrowser

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

try:
    import pyautogui
    import pyperclip
    from PIL import Image
    pyautogui.FAILSAFE = False
    pyautogui.PAUSE = 0.05
    GUI_OK = True
except Exception:
    GUI_OK = False

TOKEN = os.environ.get("AGENT_TOKEN", "").strip()
PORT = int(os.environ.get("AGENT_PORT", "8765"))

app = FastAPI(title="AI Device Agent")
app.add_middleware(
    CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"]
)


def check(request: Request, body: dict) -> bool:
    if not TOKEN:
        return True
    got = body.get("token") or request.headers.get("X-Token") or ""
    return got == TOKEN


@app.get("/health")
async def health():
    return {
        "ok": True,
        "os": platform.system(),
        "gui": GUI_OK,
        "token_required": bool(TOKEN),
    }


@app.get("/api/shot")
async def shot():
    if not GUI_OK:
        return JSONResponse({"message": "这台机器没有图形界面"}, status_code=503)
    img = pyautogui.screenshot()
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    data = base64.b64encode(buf.getvalue()).decode()
    return JSONResponse({"message": "已截屏", "width": img.width, "height": img.height,
                         "image": "data:image/png;base64," + data})


@app.post("/api/action")
async def action(request: Request):
    body = await request.json()
    if not check(request, body):
        return JSONResponse({"message": "密钥不对"}, status_code=401)

    t = (body.get("type") or "").lower()
    v = body.get("value") or ""
    x = body.get("x")
    y = body.get("y")
    x2 = body.get("x2")
    y2 = body.get("y2")

    if not GUI_OK:
        return JSONResponse({"message": "这台机器没有图形界面，装不上鼠标键盘组件"}, status_code=503)

    try:
        if t == "screenshot":
            img = pyautogui.screenshot()
            img.save(os.path.expanduser("~/agent-shot.png"))
            return {"message": f"已截屏，保存在 ~/agent-shot.png（{img.width}x{img.height}）"}

        if t in ("click", "tap"):
            pyautogui.click(int(x or 0), int(y or 0))
            return {"message": f"已点击 ({int(x or 0)}, {int(y or 0)})"}

        if t == "swipe":
            pyautogui.moveTo(int(x or 0), int(y or 0))
            pyautogui.dragTo(int(x2 or 0), int(y2 or 0), duration=0.5, button="left")
            return {"message": "已拖动"}

        if t == "type":
            try:
                pyperclip.copy(v)
                mod = "command" if platform.system() == "Darwin" else "ctrl"
                pyautogui.hotkey(mod, "v")
            except Exception:
                pyautogui.write(v, interval=0.01)
            return {"message": "已输入文字"}

        if t == "key":
            key = v.lower() or "enter"
            if key in ("win", "cmd", "command"):
                key = "win" if platform.system() == "Windows" else "command"
            pyautogui.press(key)
            return {"message": f"已按键 {key}"}

        if t == "launch":
            if platform.system() == "Windows":
                os.startfile(v)  # noqa: S606
            else:
                subprocess.Popen(v, shell=True)
            return {"message": f"已启动 {v}"}

        if t == "shell":
            r = subprocess.run(v, shell=True, capture_output=True, text=True, timeout=120)
            out = (r.stdout or r.stderr or "").strip()
            return {"message": f"退出码 {r.returncode}\n{out[:1500]}"}

        if t == "open_url":
            webbrowser.open(v)
            return {"message": f"已打开 {v}"}

        return JSONResponse({"message": f"不支持的动作 {t}"}, status_code=400)
    except Exception as e:
        return JSONResponse({"message": f"执行失败：{e}"}, status_code=500)


def main():
    import uvicorn
    print("=" * 46)
    print(" AI 设备代理已启动")
    print(f" 端口: {PORT}")
    print(f" 密钥: {'已设置' if TOKEN else '未设置（任何设备都能连）'}")
    print(" 在手机 App 的设置里填 http://这台机器的IP:%d" % PORT)
    print("=" * 46)
    uvicorn.run(app, host="0.0.0.0", port=PORT, log_level="warning")


if __name__ == "__main__":
    main()
