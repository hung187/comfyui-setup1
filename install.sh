#!/bin/bash
set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export START_TIME="${START_TIME:-$(date +%s)}"

# ─── Màu sắc CLI ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

# Source validation & common modules early
source "$SCRIPT_DIR/scripts/validation.sh"
source "$SCRIPT_DIR/scripts/common.sh"

show_server_info() {
    echo -e "\n${MAGENTA}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║         🖥️  THÔNG TIN MÁY CHỦ / SERVER INFO                 ║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════╝${NC}"

    local os_name kernel_ver
    os_name=$(cat /etc/os-release 2>/dev/null | grep '^PRETTY_NAME' | cut -d= -f2 | tr -d '"' || uname -s)
    kernel_ver=$(uname -r 2>/dev/null || echo "N/A")
    echo -e "  ${CYAN}🐧 OS         :${NC} $os_name (Kernel $kernel_ver)"

    local cpu_model cpu_cores
    cpu_model=$(grep 'model name' /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | xargs || echo "N/A")
    cpu_cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "N/A")
    echo -e "  ${CYAN}⚡ CPU         :${NC} $cpu_model ($cpu_cores cores)"

    local total_ram free_ram
    if [ -f /proc/meminfo ]; then
        total_ram=$(awk '/MemTotal/{printf "%.1f GB", $2/1024/1024}' /proc/meminfo)
        free_ram=$(awk '/MemAvailable/{printf "%.1f GB", $2/1024/1024}' /proc/meminfo)
        echo -e "  ${CYAN}🧠 RAM         :${NC} Tổng ${total_ram} | Trống ${free_ram}"
    fi

    if command -v nvidia-smi &>/dev/null; then
        local gpu_name gpu_vram gpu_vram_used
        gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "N/A")
        gpu_vram=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "0")
        gpu_vram_used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "0")
        local gpu_vram_gb gpu_used_gb
        gpu_vram_gb=$(awk "BEGIN{printf \"%.1f\", $gpu_vram/1024}")
        gpu_used_gb=$(awk "BEGIN{printf \"%.1f\", $gpu_vram_used/1024}")
        echo -e "  ${CYAN}🎮 GPU         :${NC} ${gpu_name} | VRAM ${gpu_vram_gb}GB (đang dùng ${gpu_used_gb}GB)"
    else
        echo -e "  ${CYAN}🎮 GPU         :${NC} ${YELLOW}Không tìm thấy NVIDIA GPU hoặc nvidia-smi${NC}"
    fi

    local disk_total disk_used disk_free
    disk_total=$(df -P -BG / 2>/dev/null | awk 'NR==2 {print $2}' | tr -dc '0-9' || echo "N/A")
    disk_used=$(df -P -BG / 2>/dev/null | awk 'NR==2 {print $3}' | tr -dc '0-9' || echo "N/A")
    disk_free=$(df -P -BG / 2>/dev/null | awk 'NR==2 {print $4}' | tr -dc '0-9' || echo "N/A")
    if [ "$disk_free" != "N/A" ] && [ "$disk_free" -lt 20 ]; then
        echo -e "  ${CYAN}💾 Đĩa (/)     :${NC} ${RED}⚠️  Tổng ${disk_total}GB | Đã dùng ${disk_used}GB | TRỐNG CÒN ${disk_free}GB (NGUY HIỂM!)${NC}"
    else
        echo -e "  ${CYAN}💾 Đĩa (/)     :${NC} Tổng ${disk_total}GB | Đã dùng ${disk_used}GB | Trống ${disk_free}GB"
    fi

    local pub_ip
    pub_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "Không lấy được")
    echo -e "  ${CYAN}🌐 IP Công khai:${NC} $pub_ip"

    local py_ver pip_ver
    py_ver=$(python3 --version 2>/dev/null || echo "N/A")
    pip_ver=$(pip3 --version 2>/dev/null | awk '{print $1,$2}' || echo "N/A")
    echo -e "  ${CYAN}🐍 Python      :${NC} $py_ver | pip: $pip_ver"

    echo -e "${MAGENTA}══════════════════════════════════════════════════════════════${NC}\n"
}

show_help() {
    echo "Sử dụng: bash install.sh [tùy chọn]"
    echo ""
    echo "Tùy chọn:"
    echo "  --validate / --preflight Chế độ kiểm tra toàn diện cấu hình & môi trường (READ-ONLY, không tải/cài)"
    echo "  --comfy-dir <PATH>       Chỉ định trực tiếp thư mục cài đặt ComfyUI"
    echo "  --civitai-token <TOK>    Nhập API Token của Civitai"
    echo "  --gdrive-3d              Tự động lưu 3D output vào Google Drive (thư mục ComfyUI_3D_Output)"
    echo "  --gdrive                 Tự động lưu output từ ComfyUI vào Google Drive"
    echo "  --gdrive-folder <DIR>    Tên thư mục trên Google Drive (mặc định: ComfyUI_3D_Output)"
    echo "  --gdrive-remote <NAME>   Tên remote rclone (mặc định: gdrive)"
    echo "  --stop-gdrive-3d         Dừng 3D output sync watcher đang chạy"
    echo "  --status-gdrive-3d       Kiểm tra trạng thái 3D output sync watcher"
    echo "  --only-nodes             Chỉ cài đặt ComfyUI + Custom Nodes (bỏ qua tải Models)"
    echo "  --only-models            Chỉ tải Models (bỏ qua cài đặt Custom Nodes)"
    echo "  --reload                 Nạp nhanh Custom Nodes mới mà không đụng đến GPU"
    echo "  --dry-run                Chế độ kiểm tra nhanh (không tải file nặng/torch)"
    echo "  --no-ssl-verify          Bỏ qua kiểm tra chứng chỉ SSL"
    echo "  --allow-partial          Không dừng tiến trình nếu một số node phụ bị lỗi"
    echo "  --update-existing        Cho phép git pull cập nhật các repo đã tồn tại"
    echo "  --help                   Hiển thị hướng dẫn này"
    echo ""
}

DO_RELOAD=0
DO_VALIDATE=0
DO_STOP_GDRIVE=0
DO_STATUS_GDRIVE=0
ONLY_NODES=0
ONLY_MODELS=0

while [[ $# -gt 0 ]]; do
    case $1 in
        --validate|--preflight)
            DO_VALIDATE=1
            shift
            ;;
        --comfy-dir)
            if [ -z "${2:-}" ]; then
                echo -e "${RED}❌ Lỗi: --comfy-dir yêu cầu đường dẫn thư mục.${NC}" >&2
                exit 1
            fi
            export COMFY_BASE="$2"
            shift 2
            ;;
        --civitai-token)
            if [ -z "${2:-}" ]; then
                echo -e "${RED}❌ Lỗi: --civitai-token yêu cầu giá trị token.${NC}" >&2
                exit 1
            fi
            export CIVITAI_TOKEN="$2"
            shift 2
            ;;
        --gdrive-3d)
            export ENABLE_GDRIVE=1
            export ENABLE_GDRIVE_3D=1
            if [ -z "${GDRIVE_FOLDER:-}" ]; then
                export GDRIVE_FOLDER="ComfyUI_3D_Output"
            fi
            shift
            ;;
        --gdrive)
            export ENABLE_GDRIVE=1
            if [ -z "${GDRIVE_FOLDER:-}" ]; then
                export GDRIVE_FOLDER="ComfyUI_Output"
            fi
            shift
            ;;
        --gdrive-folder)
            if [ -z "${2:-}" ]; then
                echo -e "${RED}❌ Lỗi: --gdrive-folder yêu cầu tên thư mục.${NC}" >&2
                exit 1
            fi
            export GDRIVE_FOLDER="$2"
            shift 2
            ;;
        --gdrive-remote)
            if [ -z "${2:-}" ]; then
                echo -e "${RED}❌ Lỗi: --gdrive-remote yêu cầu tên remote.${NC}" >&2
                exit 1
            fi
            export GDRIVE_REMOTE="$2"
            shift 2
            ;;
        --stop-gdrive-3d|--stop-gdrive)
            DO_STOP_GDRIVE=1
            shift
            ;;
        --status-gdrive-3d|--status-gdrive)
            DO_STATUS_GDRIVE=1
            shift
            ;;
        --only-nodes|--nodes-only)
            ONLY_NODES=1
            shift
            ;;
        --only-models|--models-only)
            ONLY_MODELS=1
            shift
            ;;
        --reload)
            DO_RELOAD=1
            shift
            ;;
        --dry-run)
            export DRY_RUN=1
            shift
            ;;
        --no-ssl-verify)
            export DISABLE_SSL_VERIFY=1
            shift
            ;;
        --allow-partial)
            export ALLOW_PARTIAL=1
            shift
            ;;
        --update-existing)
            export UPDATE_EXISTING=1
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Tùy chọn không hợp lệ: $1${NC}" >&2
            show_help
            exit 1
            ;;
    esac
done

if [ "$DO_STOP_GDRIVE" -eq 1 ]; then
    source "$SCRIPT_DIR/scripts/06_gdrive_sync.sh"
    stop_gdrive_3d_watcher "${COMFY_BASE:-}"
    exit $?
fi

if [ "$DO_STATUS_GDRIVE" -eq 1 ]; then
    source "$SCRIPT_DIR/scripts/06_gdrive_sync.sh"
    status_gdrive_3d_watcher "${COMFY_BASE:-}"
    exit $?
fi

if [ "$DO_VALIDATE" -eq 1 ]; then
    run_preflight "full" 1
    exit $?
fi

if [ "$DO_RELOAD" -eq 1 ]; then
    chmod +x "$SCRIPT_DIR/reload.sh" 2>/dev/null || true
    exec "$SCRIPT_DIR/reload.sh"
fi

source "$SCRIPT_DIR/scripts/01_env_setup.sh"
source "$SCRIPT_DIR/scripts/02_comfy_core.sh"
source "$SCRIPT_DIR/scripts/03_nodes_setup.sh"
source "$SCRIPT_DIR/scripts/04_models_dl.sh"
source "$SCRIPT_DIR/scripts/05_manifest.sh"
source "$SCRIPT_DIR/scripts/06_gdrive_sync.sh"

main() {
    show_server_info

    if ! run_preflight "full" 0; then
        echo -e "${RED}❌ Preflight Safety Gate phát hiện lỗi cấu hình. Dừng cài đặt để bảo vệ hệ thống.${NC}"
        return 1
    fi

    prepare_civitai_credentials

    run_stage_01 "$@" || return 1

    if [ "$ONLY_MODELS" -eq 1 ]; then
        run_stage_04 "$@" || return 1
        run_stage_05 "$@" || return 1
        return 0
    fi

    run_stage_02 "$@" || return 1
    run_stage_03 "$@" || return 1

    if [ "$ONLY_NODES" -eq 0 ]; then
        run_stage_04 "$@" || return 1
    fi

    run_stage_05 "$@" || return 1
    # Starts only when explicitly requested or when a previously verified,
    # non-secret Drive marker exists.
    auto_start_gdrive_watcher_if_enabled "${COMFY_BASE:-}" || return 1
}

main "$@"
