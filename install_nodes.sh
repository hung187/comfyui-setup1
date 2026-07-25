#!/bin/bash
# ==============================================================================
# SCRIPT CHỈ CÀI ĐẶT COMFYUI + TOÀN BỘ CUSTOM NODES (KHÔNG TẢI MODELS NẶNG)
# Giúp tiết kiệm dung lượng đĩa (<10GB), tránh tràn 100GB Docker Disk
# ==============================================================================

set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export START_TIME="${START_TIME:-$(date +%s)}"

show_help() {
    echo "Sử dụng: bash install_nodes.sh [tùy chọn]"
    echo ""
    echo "Tùy chọn:"
    echo "  --comfy-dir <PATH>    Chỉ định trực tiếp thư mục cài đặt ComfyUI"
    echo "  --gdrive              Tự động lưu ảnh từ ComfyUI vào Google Drive"
    echo "  --no-ssl-verify       Bỏ qua kiểm tra chứng chỉ SSL"
    echo "  --help                Hiển thị hướng dẫn này"
    echo ""
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --comfy-dir)
            export COMFY_BASE="$2"
            shift 2
            ;;
        --gdrive)
            export ENABLE_GDRIVE=1
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

source "$SCRIPT_DIR/scripts/common.sh"
source "$SCRIPT_DIR/scripts/01_env_setup.sh"
source "$SCRIPT_DIR/scripts/02_comfy_core.sh"
source "$SCRIPT_DIR/scripts/03_nodes_setup.sh"
source "$SCRIPT_DIR/scripts/05_manifest.sh"
source "$SCRIPT_DIR/scripts/06_gdrive_sync.sh"

main_nodes() {
    echo -e "${GREEN}====================================================${NC}"
    echo -e "${GREEN}🚀 CÀI ĐẶT COMFYUI + CÁC CUSTOM NODES (AN TOÀN ĐĨA) ${NC}"
    echo -e "${GREEN}====================================================${NC}"

    run_stage_01 "$@" || return 1
    run_stage_02 "$@" || return 1
    run_stage_03 "$@" || return 1
    run_stage_05 "$@" || return 1
    run_stage_06 "$@" || return 1

    echo -e "\n${GREEN}====================================================${NC}"
    echo -e "${GREEN}✅ ĐÃ CÀI XONG COMFYUI & TOÀN BỘ CUSTOM NODES!      ${NC}"
    echo -e "${YELLOW}💡 Đang tự động bật ComfyUI qua reload.sh...         ${NC}"
    echo -e "${GREEN}====================================================${NC}\n"

    chmod +x "$SCRIPT_DIR/reload.sh" 2>/dev/null || true
    exec "$SCRIPT_DIR/reload.sh"
}

main_nodes "$@"
