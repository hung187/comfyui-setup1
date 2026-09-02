#!/bin/bash
# ==============================================================================
# SCRIPT TẢI MODELS COMFYUI DỰ PHÒNG & TÙY CHỌN
# Chạy script này bất kỳ lúc nào để tải bổ sung các Models nặng
# ==============================================================================

set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export START_TIME="${START_TIME:-$(date +%s)}"

source "$SCRIPT_DIR/scripts/validation.sh"
source "$SCRIPT_DIR/scripts/common.sh"

show_help() {
    echo "Sử dụng: bash install_models.sh [tùy chọn]"
    echo ""
    echo "Tùy chọn:"
    echo "  --validate / --preflight Chế độ kiểm tra toàn diện cấu hình (READ-ONLY)"
    echo "  --comfy-dir <PATH>       Chỉ định trực tiếp thư mục cài đặt ComfyUI"
    echo "  --civitai-token <TOK>    Nhập API Token của Civitai"
    echo "  --gdrive-3d              Tự động lưu 3D output vào Google Drive (thư mục ComfyUI_3D_Output)"
    echo "  --gdrive                 Tự động lưu output từ ComfyUI vào Google Drive (thư mục ComfyUI_Output)"
    echo "  --gdrive-folder <DIR>    Tùy chỉnh tên thư mục đích trên Google Drive"
    echo "  --gdrive-remote <NAME>   Tùy chỉnh tên remote rclone (mặc định: gdrive)"
    echo "  --stop-gdrive-3d         Dừng 3D output sync watcher đang chạy"
    echo "  --status-gdrive-3d       Kiểm tra trạng thái 3D output sync watcher"
    echo "  --dry-run                Chế độ kiểm tra nhanh"
    echo "  --no-ssl-verify          Bỏ qua kiểm tra chứng chỉ SSL"
    echo "  --help                   Hiển thị hướng dẫn này"
    echo ""
}

DO_VALIDATE=0
DO_STOP_GDRIVE=0
DO_STATUS_GDRIVE=0

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
    run_preflight "models" 1
    exit $?
fi

source "$SCRIPT_DIR/scripts/04_models_dl.sh"
source "$SCRIPT_DIR/scripts/05_manifest.sh"
source "$SCRIPT_DIR/scripts/06_gdrive_sync.sh"

main_models() {
    echo -e "${MAGENTA}====================================================${NC}"
    echo -e "${MAGENTA}🚀 TẢI MODELS CHO COMFYUI (MULTI-MIRROR FALLBACK)   ${NC}"
    echo -e "${MAGENTA}====================================================${NC}"

    # Require existing ComfyUI installation (Never creates new directory in model-only mode)
    if ! init_runtime_env "require-existing"; then
        echo -e "${RED}❌ Không tìm thấy thư mục cài đặt ComfyUI có sẵn. Vui lòng chạy install_nodes.sh trước.${NC}"
        return 1
    fi

    if ! run_preflight "models" 0; then
        echo -e "${RED}❌ Preflight Safety Gate phát hiện lỗi cấu hình models.${NC}"
        return 1
    fi

    prepare_civitai_credentials

    # Lightweight model download: executes Stage 04 & Stage 05 directly without heavy system reinstall
    if ! run_stage_04 "$@"; then
        echo -e "${RED}❌ Stage 04 gặp lỗi khi tải models.${NC}"
        run_stage_05 "$@" || true
        return 1
    fi

    run_stage_05 "$@" || return 1
    # Do not claim the stage completed if a previously enabled Drive watcher
    # cannot be restored after the Pod restart.
    auto_start_gdrive_watcher_if_enabled "${COMFY_BASE:-}" || return 1

    echo -e "\n${GREEN}====================================================${NC}"
    echo -e "${GREEN}✅ ĐÃ TẢI XONG TẤT CẢ MODELS!                        ${NC}"
    echo -e "${GREEN}====================================================${NC}\n"
    return 0
}

main_models "$@"
