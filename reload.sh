#!/bin/bash
# Helper script to fast-reload ComfyUI custom nodes without killing GPU / Docker container

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to auto-detect ComfyUI base path
find_comfy_dir() {
    if [ -n "${COMFY_BASE:-}" ] && [ -d "$COMFY_BASE" ]; then
        echo "$COMFY_BASE"
        return 0
    fi

    local candidates=(
        "/workspace/ComfyUI"
        "/workspace/comfyui"
        "/content/ComfyUI"
        "$HOME/ComfyUI"
        "/root/ComfyUI"
        "$PWD/ComfyUI"
        "$(dirname "$SCRIPT_DIR")/ComfyUI"
    )

    for path in "${candidates[@]}"; do
        if [ -d "$path" ] && { [ -f "$path/main.py" ] || [ -f "$path/folder_paths.py" ]; }; then
            echo "$path"
            return 0
        fi
    done

    # Fallback if folder exists
    for path in "${candidates[@]}"; do
        if [ -d "$path" ]; then
            echo "$path"
            return 0
        fi
    done

    echo "$HOME/ComfyUI"
}

COMFY_DIR="$(find_comfy_dir)"

echo -e "\033[0;36m🔍 Phát hiện thư mục ComfyUI tại:\033[0m $COMFY_DIR"
echo -e "\033[0;34m⚡ Đang nạp lại toàn bộ Custom Nodes mới (mất 2-3 giây)... \033[0m"

# Terminate running ComfyUI python process safely
pkill -f "python main.py" 2>/dev/null || pkill -f "python3 main.py" 2>/dev/null || true
sleep 1

if [ -d "$COMFY_DIR" ] && [ -f "$COMFY_DIR/main.py" ]; then
    cd "$COMFY_DIR"
    PYTHON_BIN="python3"
    command -v python3 &>/dev/null || PYTHON_BIN="python"
    
    $PYTHON_BIN main.py --listen 0.0.0.0 --port 8188 --enable-cors-header > /tmp/comfyui.log 2>&1 &
    echo -e "\033[0;32m✅ ĐÃ NẠP XONG! Tất cả Custom Nodes mới đã được áp dụng mà KHÔNG làm ngắt GPU/Docker.\033[0m"
else
    echo -e "\033[0;31m❌ Không tìm thấy file main.py tại $COMFY_DIR. Vui lòng kiểm tra lại đường dẫn cài đặt!\033[0m"
fi
