#!/bin/bash
# ==============================================================================
# SCRIPT TẢI MODELS COMFYUI DỰ PHÒNG & TÙY CHỌN
# Chạy script này bất kỳ lúc nào để tải bổ sung các Models nặng
# ==============================================================================

set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export START_TIME="${START_TIME:-$(date +%s)}"

show_help() {
    echo "Sử dụng: bash install_models.sh [tùy chọn]"
    echo ""
    echo "Tùy chọn:"
    echo "  --comfy-dir <PATH>    Chỉ định trực tiếp thư mục cài đặt ComfyUI"
    echo "  --civitai-token <TOK> Nhập API Token của Civitai"
    echo "  --dry-run             Chế độ kiểm tra nhanh"
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
        --civitai-token)
            export CIVITAI_TOKEN="$2"
            shift 2
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

source "$SCRIPT_DIR/scripts/common.sh"
source "$SCRIPT_DIR/scripts/01_env_setup.sh"
source "$SCRIPT_DIR/scripts/04_models_dl.sh"
source "$SCRIPT_DIR/scripts/05_manifest.sh"

main_models() {
    echo -e "${MAGENTA}====================================================${NC}"
    echo -e "${MAGENTA}🚀 TẢI MODELS CHO COMFYUI (MULTI-MIRROR FALLBACK)   ${NC}"
    echo -e "${MAGENTA}====================================================${NC}"

    run_stage_01 "$@" || return 1
    run_stage_04 "$@" || return 1
    run_stage_05 "$@" || return 1

    echo -e "\n${GREEN}====================================================${NC}"
    echo -e "${GREEN}✅ ĐÃ TẢI XONG TẤT CẢ MODELS!                        ${NC}"
    echo -e "${GREEN}====================================================${NC}\n"
}

main_models "$@"
