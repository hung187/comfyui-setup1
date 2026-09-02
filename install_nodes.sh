#!/bin/bash
# ==============================================================================
# SCRIPT CHỈ CÀI ĐẶT COMFYUI + TOÀN BỘ CUSTOM NODES (KHÔNG TẢI MODELS NẶNG)
# Giúp tiết kiệm dung lượng đĩa (<10GB), tránh tràn 100GB Docker Disk
# ==============================================================================

set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export START_TIME="${START_TIME:-$(date +%s)}"

source "$SCRIPT_DIR/scripts/validation.sh"
source "$SCRIPT_DIR/scripts/common.sh"

show_help() {
    echo "Sử dụng: bash install_nodes.sh [tùy chọn]"
    echo ""
    echo "Tùy chọn:"
    echo "  --validate / --preflight Chế độ kiểm tra toàn diện cấu hình (READ-ONLY)"
    echo "  --comfy-dir <PATH>       Chỉ định trực tiếp thư mục cài đặt ComfyUI"
    echo "  --gdrive-3d              Tự động lưu 3D output vào Google Drive (thư mục ComfyUI_3D_Output)"
    echo "  --gdrive                 Tự động lưu output từ ComfyUI vào Google Drive"
    echo "  --gdrive-folder <DIR>    Tùy chỉnh tên thư mục đích trên Google Drive"
    echo "  --gdrive-remote <NAME>   Tùy chỉnh tên remote rclone (mặc định: gdrive)"
    echo "  --stop-gdrive-3d         Dừng 3D output sync watcher đang chạy"
    echo "  --status-gdrive-3d       Kiểm tra trạng thái 3D output sync watcher"
    echo "  --no-ssl-verify          Bỏ qua kiểm tra chứng chỉ SSL"
    echo "  --allow-partial          Không dừng tiến trình nếu một số node phụ bị lỗi"
    echo "  --update-existing        Cho phép git pull cập nhật các repo đã tồn tại"
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
    run_preflight "nodes" 1
    exit $?
fi

source "$SCRIPT_DIR/scripts/01_env_setup.sh"
source "$SCRIPT_DIR/scripts/02_comfy_core.sh"
source "$SCRIPT_DIR/scripts/03_nodes_setup.sh"
source "$SCRIPT_DIR/scripts/05_manifest.sh"
source "$SCRIPT_DIR/scripts/06_gdrive_sync.sh"

main_nodes() {
    echo -e "${GREEN}====================================================${NC}"
    echo -e "${GREEN}🚀 CÀI ĐẶT COMFYUI + CÁC CUSTOM NODES (AN TOÀN ĐĨA) ${NC}"
    echo -e "${GREEN}====================================================${NC}"

    if ! run_preflight "nodes" 0; then
        echo -e "${RED}❌ Preflight Safety Gate phát hiện lỗi cấu hình nodes.${NC}"
        return 1
    fi

    run_stage_01 "$@" || return 1
    run_stage_02 "$@" || return 1
    run_stage_03 "$@" || return 1
    run_stage_05 "$@" || return 1
    # Starts only when explicitly requested or when a previously verified,
    # non-secret Drive marker exists.
    auto_start_gdrive_watcher_if_enabled "${COMFY_BASE:-}" || return 1

    echo -e "\n${GREEN}====================================================${NC}"
    echo -e "${GREEN}✅ Custom Nodes installed.                          ${NC}"
    echo -e "${YELLOW}🔄 Restart your GPU/POD once.                       ${NC}"
    echo -e "${CYAN}➡️  After restart run:                               ${NC}"
    echo -e "   ${GREEN}bash install_models.sh${NC}"
    echo -e "${GREEN}====================================================${NC}\n"
    return 0
}

main_nodes "$@"
