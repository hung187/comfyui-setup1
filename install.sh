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

# ─── Kiểm tra thông tin chi tiết máy chủ ────────────────────────────────────
show_server_info() {
    echo -e "\n${MAGENTA}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║         🖥️  THÔNG TIN MÁY CHỦ / SERVER INFO                 ║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════╝${NC}"

    # OS & Kernel
    local os_name kernel_ver
    os_name=$(cat /etc/os-release 2>/dev/null | grep '^PRETTY_NAME' | cut -d= -f2 | tr -d '"' || uname -s)
    kernel_ver=$(uname -r 2>/dev/null || echo "N/A")
    echo -e "  ${CYAN}🐧 OS         :${NC} $os_name (Kernel $kernel_ver)"

    # CPU
    local cpu_model cpu_cores
    cpu_model=$(grep 'model name' /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | xargs || echo "N/A")
    cpu_cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "N/A")
    echo -e "  ${CYAN}⚡ CPU         :${NC} $cpu_model ($cpu_cores cores)"

    # RAM
    local total_ram free_ram
    if [ -f /proc/meminfo ]; then
        total_ram=$(awk '/MemTotal/{printf "%.1f GB", $2/1024/1024}' /proc/meminfo)
        free_ram=$(awk '/MemAvailable/{printf "%.1f GB", $2/1024/1024}' /proc/meminfo)
        echo -e "  ${CYAN}🧠 RAM         :${NC} Tổng ${total_ram} | Trống ${free_ram}"
    fi

    # GPU
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

    # Disk
    local disk_total disk_used disk_free
    disk_total=$(df -P -BG / 2>/dev/null | awk 'NR==2 {print $2}' | tr -dc '0-9' || echo "N/A")
    disk_used=$(df -P -BG / 2>/dev/null | awk 'NR==2 {print $3}' | tr -dc '0-9' || echo "N/A")
    disk_free=$(df -P -BG / 2>/dev/null | awk 'NR==2 {print $4}' | tr -dc '0-9' || echo "N/A")
    if [ "$disk_free" != "N/A" ] && [ "$disk_free" -lt 20 ]; then
        echo -e "  ${CYAN}💾 Đĩa (/)     :${NC} ${RED}⚠️  Tổng ${disk_total}GB | Đã dùng ${disk_used}GB | TRỐNG CÒN ${disk_free}GB (NGUY HIỂM!)${NC}"
    else
        echo -e "  ${CYAN}💾 Đĩa (/)     :${NC} Tổng ${disk_total}GB | Đã dùng ${disk_used}GB | Trống ${disk_free}GB"
    fi

    # Network / IP
    local pub_ip
    pub_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "Không lấy được")
    echo -e "  ${CYAN}🌐 IP Công khai:${NC} $pub_ip"

    # Python & pip
    local py_ver pip_ver
    py_ver=$(python3 --version 2>/dev/null || echo "N/A")
    pip_ver=$(pip3 --version 2>/dev/null | awk '{print $1,$2}' || echo "N/A")
    echo -e "  ${CYAN}🐍 Python      :${NC} $py_ver | pip: $pip_ver"

    echo -e "${MAGENTA}══════════════════════════════════════════════════════════════${NC}\n"
}

# ─── Nhập Civitai Token với khung đẹp & timeout 5 phút ─────────────────────
prompt_civitai_token() {
    if [ -n "${CIVITAI_TOKEN:-}" ]; then
        echo -e "  ${GREEN}✅ Civitai Token đã được truyền qua tham số CLI. Tiếp tục...${NC}"
        return 0
    fi

    echo -e "${YELLOW}"
    echo -e "╔══════════════════════════════════════════════════════════════╗"
    echo -e "║              🔑  NHẬP CIVITAI API TOKEN                     ║"
    echo -e "╠══════════════════════════════════════════════════════════════╣"
    echo -e "║  Token cần thiết để tải model từ Civitai.com                ║"
    echo -e "║  Tìm token tại: civitai.com/user/account  → API Keys        ║"
    echo -e "║                                                              ║"
    echo -e "║  ⏳ Tự động đóng script sau 5 phút nếu không nhập token     ║"
    echo -e "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    local token_input=""
    local timeout_secs=300  # 5 phút

    if read -r -t "$timeout_secs" -p "$(echo -e "  ${CYAN}👉 Nhập token: ${NC}")" token_input; then
        token_input="$(echo -n "$token_input" | xargs)"  # trim spaces
        if [ -z "$token_input" ]; then
            echo -e "\n  ${RED}❌ Token rỗng! Script sẽ tải model mà không có Civitai token.${NC}"
            echo -e "  ${YELLOW}   (Các model từ HuggingFace vẫn tải được, Civitai sẽ bị bỏ qua)${NC}\n"
            return 0
        fi
        export CIVITAI_TOKEN="$token_input"
        echo -e "  ${GREEN}✅ Token đã lưu thành công! Bắt đầu chạy script...${NC}\n"
    else
        echo -e "\n\n  ${RED}⏰ ĐÃ HẾT 5 PHÚT KHÔNG NHẬP TOKEN!${NC}"
        echo -e "  ${RED}   Script tự động đóng. Hãy chạy lại và nhập token kịp thời.${NC}\n"
        exit 1
    fi
}

# Help / Usage menu
show_help() {
    echo "Sử dụng: bash install.sh [tùy chọn]"
    echo ""
    echo "Tùy chọn:"
    echo "  --validate / --preflight Chế độ kiểm tra toàn diện cấu hình & môi trường (READ-ONLY, không tải/cài)"
    echo "  --comfy-dir <PATH>       Chỉ định trực tiếp thư mục cài đặt ComfyUI"
    echo "  --civitai-token <TOK>    Nhập API Token của Civitai"
    echo "  --gdrive                 Tự động lưu ảnh từ ComfyUI vào Google Drive"
    echo "  --gdrive-folder <DIR>    Tên thư mục trên Google Drive (mặc định: ComfyUI_Output)"
    echo "  --only-nodes             Chỉ cài đặt ComfyUI + Custom Nodes (bỏ qua tải Models)"
    echo "  --only-models            Chỉ tải Models (bỏ qua cài đặt Custom Nodes)"
    echo "  --reload                 Nạp nhanh Custom Nodes mới mà không đụng đến GPU"
    echo "  --dry-run                Chế độ kiểm tra nhanh (không tải file nặng/torch)"
    echo "  --no-ssl-verify          Bỏ qua kiểm tra chứng chỉ SSL"
    echo "  --help                   Hiển thị hướng dẫn này"
    echo ""
}

# Parse CLI arguments
DO_RELOAD=0
DO_VALIDATE=0
ONLY_NODES=0
ONLY_MODELS=0

while [[ $# -gt 0 ]]; do
    case $1 in
        --validate|--preflight)
            DO_VALIDATE=1
            shift
            ;;
        --comfy-dir)
            export COMFY_BASE="$2"
            shift 2
            ;;
        --civitai-token)
            export CIVITAI_TOKEN="$2"
            shift 2
            ;;
        --gdrive)
            export ENABLE_GDRIVE=1
            shift
            ;;
        --gdrive-folder)
            export GDRIVE_FOLDER="$2"
            shift 2
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
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

if [ "$DO_VALIDATE" -eq 1 ]; then
    # Read-only validate mode (Zero filesystem mutation)
    run_preflight "full" 1
    exit $?
fi

if [ "$DO_RELOAD" -eq 1 ]; then
    chmod +x "$SCRIPT_DIR/reload.sh" 2>/dev/null || true
    exec "$SCRIPT_DIR/reload.sh"
    exit 0
fi

source "$SCRIPT_DIR/scripts/01_env_setup.sh"
source "$SCRIPT_DIR/scripts/02_comfy_core.sh"
source "$SCRIPT_DIR/scripts/03_nodes_setup.sh"
source "$SCRIPT_DIR/scripts/04_models_dl.sh"
source "$SCRIPT_DIR/scripts/05_manifest.sh"
source "$SCRIPT_DIR/scripts/06_gdrive_sync.sh"

main() {
    show_server_info

    # Run Preflight Safety Gate before any operation
    if ! run_preflight "full" 0; then
        echo -e "${RED}❌ Preflight Safety Gate phát hiện lỗi cấu hình. Dừng cài đặt để bảo vệ hệ thống.${NC}"
        return 1
    fi

    prompt_civitai_token

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
    run_stage_06 "$@" || return 1
}

main "$@"
