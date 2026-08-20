#!/bin/bash
# ================================================================================================================================
# SCRIPT TỰ ĐỘNG CẬP NHẬT DANH SÁCH MIRROR HÀNG NGÀY VÀ CHẠY TẢI FILE THIẾU
# ================================================================================================================================

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -euo pipefail
fi
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source validation module
if [ -f "$SCRIPT_DIR/validation.sh" ]; then
    source "$SCRIPT_DIR/validation.sh"
elif [ -f "$BASE_DIR/scripts/validation.sh" ]; then
    source "$BASE_DIR/scripts/validation.sh"
fi

# Main execution loop
run_mirror_updater() {
    # Internal Non-blocking flock
    local LOCK_FILE="/tmp/update_mirror_internal.lock"
    exec 200>"$LOCK_FILE"
    if ! flock -n 200; then
        echo "⚠️ Một tiến trình update_mirror_list khác đang chạy. Huỷ bỏ để tránh xung đột." >&2
        return 0
    fi

    # Load .env configuration if present
    if [ -f "$BASE_DIR/.env" ]; then
        set -a
        source "$BASE_DIR/.env"
        set +a
    fi

    local LOG_DIR="$BASE_DIR/logs"
    mkdir -p "$LOG_DIR"
    local TIMESTAMP_STR
    TIMESTAMP_STR="$(date +%Y%m%d_%H%M%S)"
    local LOG_FILE="$LOG_DIR/update_mirror_${TIMESTAMP_STR}.log"

    exec 1> >(tee -a "$LOG_FILE") 2>&1

    echo "=================================================================="
    echo "🕒 [$(date '+%Y-%m-%d %H:%M:%S')] BẮT ĐẦU CẬP NHẬT MIRROR LIST & DỮ LIỆU MODEL"
    echo "=================================================================="

    local MIRROR_URL="${MIRROR_MANIFEST_URL:-https://raw.githubusercontent.com/hung187/comfyui-setup1/main/config/models_backup_list.csv}"
    local TARGET_CSV="$BASE_DIR/config/models_backup_list.csv"
    local PRIMARY_CSV="$BASE_DIR/config/models_list.csv"
    local TMP_CSV
    TMP_CSV=$(mktemp "$BASE_DIR/config/models_backup_list.tmp.XXXXXX")
    local USER_AGENT="${USER_AGENT:-Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36}"

    echo "🌐 Tải danh sách mirror từ: $MIRROR_URL"

    # Download mirror list
    local DOWNLOAD_OK=0
    if command -v curl &>/dev/null; then
        if curl -sSL -A "$USER_AGENT" --connect-timeout 20 --max-filesize 5242880 -o "$TMP_CSV" "$MIRROR_URL"; then
            DOWNLOAD_OK=1
        fi
    elif command -v wget &>/dev/null; then
        if wget -q -U "$USER_AGENT" --timeout=20 -O "$TMP_CSV" "$MIRROR_URL"; then
            DOWNLOAD_OK=1
        fi
    fi

    if [ $DOWNLOAD_OK -eq 1 ] && [ -s "$TMP_CSV" ]; then
        # Check size limit
        local file_sz
        file_sz=$(stat -c%s "$TMP_CSV" 2>/dev/null || echo 0)
        if [ "$file_sz" -gt 5242880 ]; then
            echo "❌ File mirror tải về vượt quá giới hạn an toàn 5MB ($file_sz bytes). Hủy bỏ."
            rm -f "$TMP_CSV"
            return 1
        fi

        # Run production validator from validation.sh
        if validate_backup_config "$TMP_CSV" "$PRIMARY_CSV" "${MODELS:-}" 2>/dev/null; then
            local BACKUP_FILE="${TARGET_CSV}.bak_${TIMESTAMP_STR}_$$"
            if [ -f "$TARGET_CSV" ]; then
                cp "$TARGET_CSV" "$BACKUP_FILE"
                echo "📦 Đã sao lưu file cũ tại: $BACKUP_FILE"
            fi
            mv "$TMP_CSV" "$TARGET_CSV"
            echo "✅ Đã kiểm tra & cập nhật tệp models_backup_list.csv thành công!"
        else
            echo "⚠️  CẢNH BÁO: Tệp mirror mới không vượt qua validation. Giữ nguyên tệp hiện tại."
            rm -f "$TMP_CSV"
        fi
    else
        echo "❌ Không thể tải file mirror mới từ URL. Giữ nguyên file hiện tại."
        rm -f "$TMP_CSV"
    fi

    # Tự động gọi script tải model để tự động bổ sung file còn thiếu
    echo "🚀 Chạy lại script tải model để tự động bổ sung file chưa hoàn tất..."
    cd "$BASE_DIR"
    if [ -f "install_models.sh" ]; then
        bash install_models.sh
    fi

    echo "=================================================================="
    echo "🎉 CHƯƠNG TRÌNH CẬP NHẬT HOÀN TẤT VÀO LÚC $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=================================================================="
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_mirror_updater "$@"
fi
