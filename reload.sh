#!/bin/bash
# Helper script to fast-reload ComfyUI custom nodes without killing GPU / Docker container

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to auto-detect ComfyUI base path with actual main.py
find_comfy_dir() {
    # 1. Direct environment variable override if valid
    if [ -n "${COMFY_BASE:-}" ] && [ -f "$COMFY_BASE/main.py" ]; then
        echo "$COMFY_BASE"
        return 0
    fi

    # 2. Priority candidate search requiring main.py
    local candidates=(
        "/workspace/ComfyUI"
        "/workspace/comfyui"
        "/workspace/ComfyUI_windows_portable/ComfyUI"
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

    # 3. Dynamic search across common root locations if candidates fail
    local found_path
    found_path=$(find /workspace /content /root /opt "$HOME" -maxdepth 3 -name "main.py" 2>/dev/null | grep -i "ComfyUI" | head -n 1)
    if [ -n "$found_path" ]; then
        echo "$(dirname "$found_path")"
        return 0
    fi

    echo "$HOME/ComfyUI"
}

COMFY_DIR="$(find_comfy_dir)"

echo -e "\033[0;36m🔍 Phát hiện thư mục ComfyUI tại:\033[0m $COMFY_DIR"

if [ ! -f "$COMFY_DIR/main.py" ]; then
    echo -e "\033[0;31m❌ Không tìm thấy file main.py tại $COMFY_DIR.\033[0m"
    echo -e "\033[0;33m💡 Đang tự động tìm kiếm vị trí main.py trên toàn bộ đĩa...\033[0m"
    SEARCH_RESULT=$(find / -name "main.py" 2>/dev/null | grep -i "ComfyUI" | head -n 1)
    if [ -n "$SEARCH_RESULT" ]; then
        COMFY_DIR="$(dirname "$SEARCH_RESULT")"
        echo -e "\033[0;32m✅ Đã tìm thấy ComfyUI tại:\033[0m $COMFY_DIR"
    fi
fi

if [ -d "$COMFY_DIR" ] && [ -f "$COMFY_DIR/main.py" ]; then
    echo -e "\033[0;34m⚡ Đang nạp lại toàn bộ Custom Nodes mới (mất 2-3 giây)... \033[0m"

    # Terminate running ComfyUI python process safely
    pkill -f "python main.py" 2>/dev/null || pkill -f "python3 main.py" 2>/dev/null || true
    sleep 1

    cd "$COMFY_DIR"
    PYTHON_BIN="python3"
    command -v python3 &>/dev/null || PYTHON_BIN="python"
    
    $PYTHON_BIN main.py --listen 0.0.0.0 --port 8188 --enable-cors-header > /tmp/comfyui.log 2>&1 &
    echo -e "\033[0;32m✅ ĐÃ NẠP XONG! Tất cả Custom Nodes mới đã được áp dụng mà KHÔNG làm ngắt GPU/Docker.\033[0m"
else
    echo -e "\033[0;31m❌ Không tìm thấy thư mục ComfyUI hợp lệ trên máy chủ này.\033[0m"
    echo -e "\033[0;33m👉 Bạn có thể chạy lệnh: bash install.sh để tự động cài đặt ComfyUI.\033[0m"
fi
