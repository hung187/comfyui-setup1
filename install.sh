#!/bin/bash
set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export START_TIME="${START_TIME:-$(date +%s)}"

# Help / Usage menu
show_help() {
    echo "Sử dụng: bash install.sh [tùy chọn]"
    echo ""
    echo "Tùy chọn:"
    echo "  --comfy-dir <PATH>    Chỉ định trực tiếp thư mục cài đặt ComfyUI"
    echo "  --civitai-token <TOK> Nhập API Token của Civitai"
    echo "  --dry-run             Chế độ kiểm tra nhanh (không tải file nặng/torch)"
    echo "  --no-ssl-verify       Bỏ qua kiểm tra chứng chỉ SSL"
    echo "  --help                Hiển thị hướng dẫn này"
    echo ""
}

# Parse CLI arguments
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
source "$SCRIPT_DIR/scripts/02_comfy_core.sh"
source "$SCRIPT_DIR/scripts/03_nodes_setup.sh"
source "$SCRIPT_DIR/scripts/04_models_dl.sh"
source "$SCRIPT_DIR/scripts/05_manifest.sh"

main() {
    run_stage_01 "$@" || return 1
    run_stage_02 "$@" || return 1
    run_stage_03 "$@" || return 1
    run_stage_04 "$@" || return 1
    run_stage_05 "$@" || return 1
}

main "$@"
