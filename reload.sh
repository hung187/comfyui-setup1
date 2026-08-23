#!/bin/bash
# ==============================================================================
# SCRIPT KHỞI ĐỘNG LẠI COMFYUI CỤC BỘ (0.0.0.0:8188)
# An toàn, không tự ý mở tunnel công khai trừ khi có cờ --tunnel
# ==============================================================================

set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/scripts/validation.sh" ]; then
    source "$SCRIPT_DIR/scripts/validation.sh"
fi
if [ -f "$SCRIPT_DIR/scripts/common.sh" ]; then
    source "$SCRIPT_DIR/scripts/common.sh"
fi

CLI_COMFY_DIR=""
ENABLE_TUNNEL=0

while [[ $# -gt 0 ]]; do
    case $1 in
        --comfy-dir)
            if [ -z "${2:-}" ]; then
                echo -e "\033[0;31m❌ Lỗi: --comfy-dir yêu cầu đường dẫn thư mục.\033[0m" >&2
                exit 1
            fi
            CLI_COMFY_DIR="$2"
            shift 2
            ;;
        --tunnel)
            ENABLE_TUNNEL=1
            shift
            ;;
        --help|-h)
            echo "Sử dụng: bash reload.sh [--comfy-dir <PATH>] [--tunnel]"
            exit 0
            ;;
        *)
            echo -e "\033[0;31m❌ Tùy chọn không hợp lệ: $1\033[0m" >&2
            exit 1
            ;;
    esac
done

if declare -f resolve_comfy_base >/dev/null 2>&1; then
    if ! COMFY_DIR="$(resolve_comfy_base "${CLI_COMFY_DIR:-${COMFY_BASE:-}}" 0)"; then
        echo -e "\033[0;31m❌ Không tìm thấy thư mục ComfyUI có sẵn. Dừng lại.\033[0m" >&2
        exit 1
    fi
else
    COMFY_DIR="${CLI_COMFY_DIR:-${COMFY_BASE:-}}"
fi

if [ -z "$COMFY_DIR" ] || [ ! -d "$COMFY_DIR" ] || [ ! -f "$COMFY_DIR/main.py" ]; then
    echo -e "\033[0;31m❌ Thư mục ComfyUI không hợp lệ: $COMFY_DIR\033[0m" >&2
    exit 1
fi

echo -e "\033[0;36m🔍 Sử dụng thư mục ComfyUI tại:\033[0m $COMFY_DIR"

cd "$COMFY_DIR" || exit 1
PYTHON_BIN="python3"
if [ -x "$COMFY_DIR/venv/bin/python" ]; then
    PYTHON_BIN="$COMFY_DIR/venv/bin/python"
elif [ -x "$COMFY_DIR/.venv/bin/python" ]; then
    PYTHON_BIN="$COMFY_DIR/.venv/bin/python"
elif command -v python3 &>/dev/null; then
    PYTHON_BIN="$(command -v python3)"
fi

LOG_FILE="/tmp/comfyui.log"
rm -f "$LOG_FILE"

echo -e "\033[0;34m🚀 Đang khởi động ComfyUI trên 0.0.0.0:8188...\033[0m"
$PYTHON_BIN main.py --listen 0.0.0.0 --port 8188 --enable-cors-header > "$LOG_FILE" 2>&1 &

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
    echo -e "\033[0;32m✅ ComfyUI đã sẵn sàng tại http://0.0.0.0:8188\033[0m"
else
    echo -e "\033[0;33m⚠️ ComfyUI đang khởi động trong background (xem /tmp/comfyui.log)...\033[0m"
fi

if [ "$ENABLE_TUNNEL" -eq 1 ]; then
    if command -v cloudflared &>/dev/null; then
        TUNNEL_LOG="/tmp/cloudflared.log"
        rm -f "$TUNNEL_LOG"
        cloudflared tunnel --url http://127.0.0.1:8188 > "$TUNNEL_LOG" 2>&1 &
        PUBLIC_URL=""
        for t in {1..15}; do
            if [ -f "$TUNNEL_LOG" ]; then
                PUBLIC_URL=$(grep -oE 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' "$TUNNEL_LOG" | head -n 1)
                [ -n "$PUBLIC_URL" ] && break
            fi
            sleep 1
        done
        if [ -n "$PUBLIC_URL" ]; then
            echo -e "\033[1;36m🔗 Public Cloudflare URL: $PUBLIC_URL\033[0m"
        fi
    else
        echo -e "\033[0;33m⚠️ Không tìm thấy công cụ cloudflared để tạo tunnel công khai.\033[0m"
    fi
fi
