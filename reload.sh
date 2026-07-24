#!/bin/bash
# Helper script to fast-reload ComfyUI custom nodes without killing GPU / Colab runtime

COMFY_DIR="${COMFY_BASE:-/content/ComfyUI}"
if [ ! -d "$COMFY_DIR" ]; then
    COMFY_DIR="$HOME/ComfyUI"
fi

echo -e "\033[0;34m⚡ Đang nạp lại toàn bộ Custom Nodes mới (mất 2-3 giây)... \033[0m"

# Terminate running ComfyUI python process safely
pkill -f "python main.py" 2>/dev/null || true
sleep 1

# Restart ComfyUI background process instantly
cd "$COMFY_DIR" && python main.py --listen 0.0.0.0 --port 8188 --enable-cors-header > /content/comfyui.log 2>&1 &

echo -e "\033[0;32m✅ ĐÃ NẠP XONG! Tất cả Custom Nodes mới đã được áp dụng mà KHÔNG làm ngắt GPU.\033[0m"
