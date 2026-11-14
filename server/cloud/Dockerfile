FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb x11vnc fluxbox xdotool scrot curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir fastapi "uvicorn[standard]" pyautogui pyperclip pillow mss

COPY agent/agent.py /app/agent.py
WORKDIR /app

ENV AGENT_PORT=8765
EXPOSE 8765

# 虚拟屏幕 1280x800，没有显示器也能跑鼠标键盘
CMD ["xvfb-run", "-s", "-screen 0 1280x800x24", "python", "agent.py"]
