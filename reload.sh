#!/bin/bash
# Helper script to fast-reload ComfyUI custom nodes without killing GPU / Docker container

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

find_comfy_dir() {
    if [ -n "${COMFY_BASE:-}" ] && [ -f "$COMFY_BASE/main.py" ]; then
        echo "$COMFY_BASE"
        return 0
    fi

    local candidates=(
        "/app/ComfyUI"
        "/app/comfyUI"
        "/workspace/ComfyUI"
        "/workspace/comfyui"
        "/content/ComfyUI"
        "/content/drive/MyDrive/ComfyUI"
        "$HOME/ComfyUI"
        "/root/ComfyUI"
        "$PWD/ComfyUI"
        "$(dirname "$SCRIPT_DIR")/ComfyUI"
        "$PWD"
    )

    for path in "${candidates[@]}"; do
        if [ -d "$path" ] && [ -f "$path/main.py" ]; then
            echo "$path"
            return 0
        fi
    done

    local found_path
    found_path=$(find /app /workspace /content /root /opt "$HOME" -maxdepth 3 -name "main.py" 2>/dev/null | grep -i "ComfyUI" | head -n 1)
    if [ -n "$found_path" ]; then
        echo "$(dirname "$found_path")"
        return 0
    fi

    echo "$HOME/ComfyUI"
}

COMFY_DIR="$(find_comfy_dir)"

echo -e "\033[0;36m🔍 Phát hiện thư mục ComfyUI tại:\033[0m $COMFY_DIR"

if [ ! -f "$COMFY_DIR/main.py" ]; then
    echo -e "\033[0;33m💡 Đang tự động tìm kiếm vị trí main.py trên toàn bộ đĩa...\033[0m"
    SEARCH_RESULT=$(find / -name "main.py" 2>/dev/null | grep -i "ComfyUI" | head -n 1)
    if [ -n "$SEARCH_RESULT" ]; then
        COMFY_DIR="$(dirname "$SEARCH_RESULT")"
        echo -e "\033[0;32m✅ Đã tìm thấy ComfyUI tại:\033[0m $COMFY_DIR"
    fi
fi

if [ -d "$COMFY_DIR" ] && [ -f "$COMFY_DIR/main.py" ]; then
    echo -e "\033[0;34m⚡ Đang dọn dẹp tiến trình cũ và giải phóng Cổng 8188...\033[0m"

    # 1. Kill old process safely and free port 8188
    fuser -k -9 8188/tcp 2>/dev/null || true
    pkill -9 -f "main.py" 2>/dev/null || true
    sleep 2

    cd "$COMFY_DIR"
    PYTHON_BIN="python3"
    command -v python3 &>/dev/null || PYTHON_BIN="python"

    LOG_FILE="/tmp/comfyui.log"
    rm -f "$LOG_FILE"

    echo -e "\033[0;34m🚀 Đang khởi động lại ComfyUI & Nạp toàn bộ Custom Nodes...\033[0m"
    $PYTHON_BIN main.py --listen 0.0.0.0 --port 8188 --enable-cors-header > "$LOG_FILE" 2>&1 &
    
    # 2. Wait and verify readiness at port 8188
    READY=0
    for i in {1..30}; do
        if command -v curl &>/dev/null; then
            if curl -s http://127.0.0.1:8188/ >/dev/null 2>&1; then
                READY=1
                break
            fi
        fi
        sleep 1
    done

    if [ $READY -eq 1 ]; then
        echo -e "\033[0;32m✅ THÀNH CÔNG! ComfyUI đã nạp xong tất cả Custom Nodes và sẵn sàng tại cổng 8188.\033[0m"
    else
        echo -e "\033[0;33m⚠️ ComfyUI vẫn đang nạp các Custom Node nặng trong background...\033[0m"
        echo -e "\033[0;36m📋 15 Dòng log khởi động gần nhất:\033[0m"
        tail -n 15 "$LOG_FILE" 2>/dev/null || true
    fi
else
    echo -e "\033[0;31m❌ Không tìm thấy thư mục ComfyUI hợp lệ trên máy chủ này.\033[0m"
fi
