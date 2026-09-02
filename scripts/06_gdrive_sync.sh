#!/bin/bash
# ==============================================================================
# STAGE 06: AUTOMATIC 3D OUTPUT SYNC TO GOOGLE DRIVE (comfyui-setup1)
# Đồng bộ tự động sản phẩm 3D (.glb, .gltf, .obj, .mtl), texture (.png, .jpg,
# .jpeg, .webp) và workflow (.json) từ $COMFY_BASE/output lên Google Drive.
# ==============================================================================

if [ "${COMFY_GDRIVE_SYNC_SH_LOADED:-}" = "1" ]; then
    return 0 2>/dev/null || exit 0
fi
export COMFY_GDRIVE_SYNC_SH_LOADED=1

# Source common utilities if available
_CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$_CURRENT_DIR/common.sh" ]; then
    source "$_CURRENT_DIR/common.sh"
elif [ -f "$_CURRENT_DIR/scripts/common.sh" ]; then
    source "$_CURRENT_DIR/scripts/common.sh"
fi

# Fallback color definitions
RED="${RED:-\033[0;31m}"
GREEN="${GREEN:-\033[0;32m}"
YELLOW="${YELLOW:-\033[0;33m}"
BLUE="${BLUE:-\033[0;34m}"
MAGENTA="${MAGENTA:-\033[0;35m}"
CYAN="${CYAN:-\033[0;36m}"
WHITE="${WHITE:-\033[1;37m}"
NC="${NC:-\033[0m}"

GDRIVE_MARKER_FILENAME=".gdrive_sync_marker.json"
GDRIVE_SYNCED_STATE_FILENAME=".gdrive_synced_state.json"

# ==============================================================================
# 1. NON-SECRET MARKER & STATE MANAGEMENT
# ==============================================================================

get_gdrive_marker_path() {
    local base="${1:-${COMFY_BASE:-}}"
    if [ -n "$base" ]; then
        echo "$base/$GDRIVE_MARKER_FILENAME"
    else
        echo "$HOME/.config/comfyui/$GDRIVE_MARKER_FILENAME"
    fi
}

get_gdrive_synced_state_path() {
    local base="${1:-${COMFY_BASE:-}}"
    if [ -n "$base" ]; then
        echo "$base/$GDRIVE_SYNCED_STATE_FILENAME"
    else
        echo "/tmp/$GDRIVE_SYNCED_STATE_FILENAME"
    fi
}

save_gdrive_marker() {
    local base="$1"
    local remote="$2"
    local folder="$3"
    local marker_path
    marker_path="$(get_gdrive_marker_path "$base")"

    mkdir -p "$(dirname "$marker_path")" 2>/dev/null || true
    cat > "$marker_path" << EOF
{
  "enabled": true,
  "remote": "$remote",
  "folder": "$folder",
  "updated_at": $(date +%s)
}
EOF
    chmod 600 "$marker_path" 2>/dev/null || true
}

read_gdrive_marker() {
    local base="$1"
    local marker_path
    marker_path="$(get_gdrive_marker_path "$base")"

    if [ ! -f "$marker_path" ]; then
        return 1
    fi

    python3 - "$marker_path" <<'PY_READ'
import sys, json

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    if data.get("enabled"):
        remote = str(data.get("remote", "gdrive")).strip()
        folder = str(data.get("folder", "ComfyUI_3D_Output")).strip()
        if any(c in remote for c in [';', '&', '|', '`', '$', '\n']) or any(c in folder for c in [';', '&', '|', '`', '$', '\n']):
            sys.exit(1)
        print(f"{remote}|{folder}")
        sys.exit(0)
except Exception:
    pass
sys.exit(1)
PY_READ
}

remove_gdrive_marker() {
    local base="$1"
    local marker_path
    marker_path="$(get_gdrive_marker_path "$base")"
    rm -f "$marker_path" 2>/dev/null || true
}

is_file_already_synced() {
    local state_file="$1"
    local rel_path="$2"
    local local_file="$3"

    if [ ! -f "$state_file" ] || [ ! -f "$local_file" ]; then
        return 1
    fi

    local current_size
    current_size="$(stat -c%s "$local_file" 2>/dev/null || wc -c < "$local_file" 2>/dev/null | tr -dc '0-9' || echo "0")"
    local current_mtime
    current_mtime="$(stat -c%Y "$local_file" 2>/dev/null || echo "0")"

    python3 - "$state_file" "$rel_path" "$current_size" "$current_mtime" <<'PY_STATE'
import sys, json

state_file = sys.argv[1]
rel_path = sys.argv[2]
curr_size = int(sys.argv[3]) if sys.argv[3].isdigit() else 0
curr_mtime = int(sys.argv[4]) if sys.argv[4].isdigit() else 0

try:
    with open(state_file, "r", encoding="utf-8") as f:
        data = json.load(f)
    entry = data.get(rel_path)
    if entry and isinstance(entry, dict):
        if entry.get("size") == curr_size and entry.get("mtime") == curr_mtime:
            sys.exit(0)
except Exception:
    pass
sys.exit(1)
PY_STATE
}

mark_file_as_synced() {
    local state_file="$1"
    local rel_path="$2"
    local local_file="$3"

    if [ ! -f "$local_file" ]; then
        return 1
    fi

    local current_size
    current_size="$(stat -c%s "$local_file" 2>/dev/null || wc -c < "$local_file" 2>/dev/null | tr -dc '0-9' || echo "0")"
    local current_mtime
    current_mtime="$(stat -c%Y "$local_file" 2>/dev/null || echo "0")"

    python3 - "$state_file" "$rel_path" "$current_size" "$current_mtime" <<'PY_MARK'
import sys, json, os

state_file = sys.argv[1]
rel_path = sys.argv[2]
curr_size = int(sys.argv[3]) if sys.argv[3].isdigit() else 0
curr_mtime = int(sys.argv[4]) if sys.argv[4].isdigit() else 0

data = {}
if os.path.exists(state_file):
    try:
        with open(state_file, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        data = {}

data[rel_path] = {
    "size": curr_size,
    "mtime": curr_mtime,
    "synced_at": int(os.environ.get("SYNC_TIME", 0)) or 1
}

dir_name = os.path.dirname(os.path.abspath(state_file))
os.makedirs(dir_name, exist_ok=True)
tmp_file = state_file + f".tmp.{os.getpid()}"
with open(tmp_file, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
os.chmod(tmp_file, 0o600)
os.replace(tmp_file, state_file)
PY_MARK
}

# ==============================================================================
# 2. FILE VALIDATION & FILTERING ENGINE (WHITELIST / BLACKLIST)
# ==============================================================================

is_valid_3d_output_file() {
    local filepath="${1:-}"
    local output_base="${2:-${OUTPUT_DIR:-}}"

    if [ -z "$filepath" ]; then
        return 1
    fi

    # 1. Must be a regular file that exists
    if [ ! -f "$filepath" ]; then
        return 1
    fi

    # 2. Must not be empty (zero-byte files are rejected)
    if [ ! -s "$filepath" ]; then
        return 1
    fi

    local filename
    filename="$(basename "$filepath")"
    local lower_filename
    lower_filename="$(echo "$filename" | tr '[:upper:]' '[:lower:]')"

    # 3. Whitelist extensions:
    # 3D assets: .glb, .gltf, .obj, .mtl
    # Textures/Images: .png, .jpg, .jpeg, .webp
    # Workflow: .json
    local match_ext=0
    case "$lower_filename" in
        *.glb|*.gltf|*.obj|*.mtl)
            match_ext=1
            ;;
        *.png|*.jpg|*.jpeg|*.webp)
            match_ext=1
            ;;
        *.json)
            match_ext=1
            ;;
        *)
            return 1
            ;;
    esac

    if [ $match_ext -ne 1 ]; then
        return 1
    fi

    # 4. Strict Blacklist:
    # - Hidden files (starting with '.')
    # - Temporary and incomplete downloads (*.part*, *.tmp*, *.partial*, *.crdownload*)
    # - Lock/PID/Log files (*.lock, *.pid, *.log)
    # - Metadata and state files (*.meta.json, *download_state*, *setup_report*, *source_health*, *gdrive_sync*)
    # - System and credential files (*secret*, *credential*, *rclone.conf*)
    case "$lower_filename" in
        .*)
            return 1
            ;;
        *.part|*.part.*|*.tmp|*.tmp.*|*.partial|*.crdownload)
            return 1
            ;;
        *.lock|*.pid|*.log)
            return 1
            ;;
        *.meta.json|*download_state*|*setup_report*|*source_health*|*manifest*|*history*|*gdrive_sync*)
            return 1
            ;;
        *token*|*secret*|*credential*|*rclone.conf*)
            return 1
            ;;
    esac

    # 5. Path boundary containment check (must not be inside models/, custom_nodes/, .cache/)
    local normalized_path
    normalized_path="$(realpath "$filepath" 2>/dev/null || echo "$filepath")"

    case "$normalized_path" in
        */models/*|*/custom_nodes/*|*/.cache/*|*/.git/*|*/preserve_quarantine/*)
            return 1
            ;;
    esac

    # 6. If output_base is specified, ensure it resides inside output_base
    if [ -n "$output_base" ]; then
        local real_out_base
        real_out_base="$(realpath "$output_base" 2>/dev/null || echo "$output_base")"
        case "$normalized_path" in
            "$real_out_base"/*)
                ;;
            *)
                return 1
                ;;
        esac
    fi

    return 0
}

# ==============================================================================
# 3. FILE STABILIZATION CHECK (ANTI-PARTIAL WRITE GATE)
# ==============================================================================

wait_for_file_stable() {
    local filepath="${1:-}"
    local max_checks="${2:-5}"
    local delay_sec="${3:-0.5}"

    if [ ! -f "$filepath" ]; then
        return 1
    fi

    local size1
    size1="$(stat -c%s "$filepath" 2>/dev/null || wc -c < "$filepath" 2>/dev/null | tr -dc '0-9' || echo "0")"
    if [ "$size1" -le 0 ]; then
        return 1
    fi

    sleep "$delay_sec"

    local size2
    size2="$(stat -c%s "$filepath" 2>/dev/null || wc -c < "$filepath" 2>/dev/null | tr -dc '0-9' || echo "0")"

    if [ "$size1" -eq "$size2" ] && [ "$size2" -gt 0 ]; then
        return 0
    fi

    local checks=1
    local prev_size="$size2"
    while [ $checks -lt $max_checks ]; do
        sleep "$delay_sec"
        local curr_size
        curr_size="$(stat -c%s "$filepath" 2>/dev/null || wc -c < "$filepath" 2>/dev/null | tr -dc '0-9' || echo "0")"
        if [ "$curr_size" -eq "$prev_size" ] && [ "$curr_size" -gt 0 ]; then
            return 0
        fi
        prev_size="$curr_size"
        checks=$((checks + 1))
    done

    return 1
}

# ==============================================================================
# 4. ATOMIC REMOTE STAGING & VERIFIED UPLOAD PROTOCOL
# ==============================================================================

sync_single_file_safe() {
    local local_file="${1:-}"
    local output_dir="${2:-}"
    local gdrive_remote="${3:-gdrive}"
    local gdrive_folder="${4:-ComfyUI_3D_Output}"
    local max_retries="${5:-3}"
    local log_file="${6:-/tmp/gdrive_3d_watcher.log}"
    local state_file="${7:-}"

    if [ -z "$local_file" ] || [ -z "$output_dir" ]; then
        return 1
    fi

    # Pre-check filter
    if ! is_valid_3d_output_file "$local_file" "$output_dir"; then
        return 0
    fi

    # Compute relative path preserving subdirectory hierarchy
    local rel_path
    rel_path="${local_file#"$output_dir"/}"
    rel_path="${rel_path#/}"

    if [ -z "$rel_path" ]; then
        return 1
    fi

    # Deduplication check: if state_file exists, skip if already synced
    if [ -n "$state_file" ] && is_file_already_synced "$state_file" "$rel_path" "$local_file"; then
        return 0
    fi

    # Wait for file to finish writing
    if ! wait_for_file_stable "$local_file" 5 0.2; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️ File chưa ổn định hoặc 0-byte, bỏ qua: $local_file" >> "$log_file" 2>&1 || true
        return 1
    fi

    local local_size
    local_size="$(stat -c%s "$local_file" 2>/dev/null || wc -c < "$local_file" 2>/dev/null | tr -dc '0-9' || echo "0")"

    local staged_remote="${gdrive_remote}:${gdrive_folder}/${rel_path}.partial"
    local final_remote="${gdrive_remote}:${gdrive_folder}/${rel_path}"

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 📤 Bắt đầu tải lên: $rel_path (${local_size} bytes)" >> "$log_file" 2>&1 || true

    local attempt=1
    local upload_success=0

    while [ $attempt -le $max_retries ]; do
        # 1. Upload to staged .partial name
        if rclone copyto "$local_file" "$staged_remote" >> "$log_file" 2>&1; then
            # 2. Verify staging upload size
            local remote_size
            remote_size="$(rclone lsf --format "s" "$staged_remote" 2>/dev/null | tr -dc '0-9' || echo "")"

            if [ -n "$remote_size" ] && [ "$remote_size" -eq "$local_size" ]; then
                # 3. Atomic rename/move to final destination on Drive
                if rclone moveto "$staged_remote" "$final_remote" >> "$log_file" 2>&1; then
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ Đã đồng bộ an toàn: ${gdrive_folder}/${rel_path}" >> "$log_file" 2>&1 || true
                    upload_success=1
                    [ -n "$state_file" ] && mark_file_as_synced "$state_file" "$rel_path" "$local_file"
                    break
                else
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️ Lỗi moveto trên Drive (lần $attempt/$max_retries): $rel_path" >> "$log_file" 2>&1 || true
                fi
            else
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️ Kích thước remote (${remote_size:-0}) không khớp local ($local_size) (lần $attempt/$max_retries)" >> "$log_file" 2>&1 || true
                # Cleanup corrupted partial upload
                rclone deletefile "$staged_remote" >> "$log_file" 2>&1 || true
            fi
        else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️ Lỗi rclone copyto (lần $attempt/$max_retries): $rel_path" >> "$log_file" 2>&1 || true
        fi

        attempt=$((attempt + 1))
        [ $attempt -le $max_retries ] && sleep 1
    done

    if [ $upload_success -eq 1 ]; then
        return 0
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ Thất bại tải lên sau $max_retries lần. File local vẫn được giữ nguyên 100%: $local_file" >> "$log_file" 2>&1 || true
        return 1
    fi
}

# ==============================================================================
# 5. WATCHER DAEMON & FLOCK PROCESS GUARD
# ==============================================================================

gdrive_3d_watcher_daemon() {
    local output_dir="${1:-}"
    local gdrive_remote="${2:-gdrive}"
    local gdrive_folder="${3:-ComfyUI_3D_Output}"
    local lock_file="${4:-}"
    local pid_file="${5:-}"
    local log_file="${6:-}"
    local state_file="${7:-}"

    if [ -z "$output_dir" ] || [ -z "$lock_file" ] || [ -z "$pid_file" ]; then
        echo "Missing parameters for gdrive_3d_watcher_daemon" >&2
        exit 1
    fi

    mkdir -p "$(dirname "$lock_file")" "$(dirname "$pid_file")" "$(dirname "$log_file")" 2>/dev/null || true

    # Exclusive flock acquisition
    exec 200>"$lock_file"
    if ! flock -n 200; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ Watcher đã đang chạy (flock held on $lock_file). Daemon dừng." >> "$log_file" 2>&1 || true
        exit 1
    fi

    local my_pid="${BASHPID:-$$}"
    echo "$my_pid" > "$pid_file"

    local INOTIFY_PID=""

    # Trap clean exit
    cleanup_watcher() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🛑 Watcher nhận tín hiệu dừng. Đang dọn dẹp..." >> "$log_file" 2>&1 || true
        [ -n "$INOTIFY_PID" ] && kill "$INOTIFY_PID" 2>/dev/null || true
        if [ -f "$pid_file" ]; then
            local current_pid
            current_pid="$(cat "$pid_file" 2>/dev/null || echo "")"
            if [ "$current_pid" = "$my_pid" ]; then
                rm -f "$pid_file" 2>/dev/null || true
            fi
        fi
        flock -u 200 2>/dev/null || true
        rm -f "$lock_file" 2>/dev/null || true
        exit 0
    }
    trap cleanup_watcher SIGTERM SIGINT SIGHUP EXIT

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🚀 Watcher daemon khởi động (PID: $my_pid)" >> "$log_file" 2>&1
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 📂 Thư mục theo dõi: $output_dir" >> "$log_file" 2>&1
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ☁️ Đích Google Drive: ${gdrive_remote}:${gdrive_folder}" >> "$log_file" 2>&1

    # Initial scan: sync any existing valid 3D/texture/workflow files
    if [ -d "$output_dir" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🔍 Quét đồng bộ ban đầu..." >> "$log_file" 2>&1
        find "$output_dir" -type f 2>/dev/null | while read -r init_file; do
            if is_valid_3d_output_file "$init_file" "$output_dir"; then
                sync_single_file_safe "$init_file" "$output_dir" "$gdrive_remote" "$gdrive_folder" 3 "$log_file" "$state_file"
            fi
        done
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✨ Hoàn tất quét ban đầu. Chuyển sang chế độ theo dõi real-time." >> "$log_file" 2>&1
    fi

    # Event Loop
    if command -v inotifywait &>/dev/null; then
        while true; do
            # Watch recursively for close_write and moved_to events
            inotifywait -m -r -e close_write,moved_to --format '%w%f' "$output_dir" 2>>"$log_file" | while read -r triggered_file; do
                if [ -n "$triggered_file" ] && [ -f "$triggered_file" ]; then
                    if is_valid_3d_output_file "$triggered_file" "$output_dir"; then
                        sync_single_file_safe "$triggered_file" "$output_dir" "$gdrive_remote" "$gdrive_folder" 3 "$log_file" "$state_file"
                    fi
                fi
            done
            sleep 2
        done
    else
        # Polling fallback mode with deduplication
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ℹ️ inotifywait không khả dụng. Sử dụng chế độ polling an toàn (15s)." >> "$log_file" 2>&1
        while true; do
            if [ -d "$output_dir" ]; then
                find "$output_dir" -type f 2>/dev/null | while read -r poll_file; do
                    if is_valid_3d_output_file "$poll_file" "$output_dir"; then
                        sync_single_file_safe "$poll_file" "$output_dir" "$gdrive_remote" "$gdrive_folder" 3 "$log_file" "$state_file"
                    fi
                done
            fi
            sleep 15
        done
    fi
}

# ==============================================================================
# 6. LIFECYCLE MANAGEMENT API (START / STOP / STATUS)
# ==============================================================================

start_gdrive_3d_watcher() {
    local comfy_base="${1:-${COMFY_BASE:-}}"
    local gdrive_remote="${2:-${GDRIVE_REMOTE:-gdrive}}"
    local gdrive_folder="${3:-${GDRIVE_FOLDER:-ComfyUI_3D_Output}}"
    local rclone_conf="${RCLONE_CONFIG_PATH:-$HOME/.config/rclone/rclone.conf}"

    if [ -z "$comfy_base" ]; then
        echo -e "${RED}❌ Lỗi: Không xác định được COMFY_BASE để khởi động 3D output watcher.${NC}" >&2
        return 1
    fi

    local output_dir="$comfy_base/output"
    mkdir -p "$output_dir" 2>/dev/null || true

    local lock_file="$comfy_base/.gdrive_3d_watcher.lock"
    local pid_file="$comfy_base/.gdrive_3d_watcher.pid"
    local log_file="$comfy_base/.gdrive_3d_watcher.log"
    local state_file
    state_file="$(get_gdrive_synced_state_path "$comfy_base")"

    # 1. Check if watcher is already running
    if [ -f "$pid_file" ]; then
        local running_pid
        running_pid="$(cat "$pid_file" 2>/dev/null || echo "")"
        if [ -n "$running_pid" ] && kill -0 "$running_pid" 2>/dev/null; then
            echo -e "${GREEN}✅ 3D Output Sync Watcher đã đang chạy (PID: $running_pid).${NC}"
            echo -e "   📁 Theo dõi: ${WHITE}$output_dir${NC}"
            echo -e "   ☁️ Google Drive: ${CYAN}${gdrive_remote}:${gdrive_folder}${NC}"
            return 0
        fi
    fi

    # 2. Check rclone availability
    if ! command -v rclone &>/dev/null; then
        echo -e "${RED}❌ Lỗi: rclone chưa được cài đặt trên hệ thống. Vui lòng cài đặt rclone trước.${NC}" >&2
        return 1
    fi

    # 3. Verify rclone remote configuration & connectivity
    if ! rclone listremotes 2>/dev/null | grep -q "^${gdrive_remote}:"; then
        echo -e "${RED}❌ Lỗi: Google Drive remote '${gdrive_remote}:' chưa được cấu hình.${NC}" >&2
        return 1
    fi

    if ! rclone lsd "${gdrive_remote}:" --max-depth 1 &>/dev/null; then
        echo -e "${RED}❌ Lỗi: Không thể kết nối tới Google Drive remote '${gdrive_remote}:'. Vui lòng kiểm tra lại token.${NC}" >&2
        return 1
    fi

    # 4. Ensure target folder exists on Drive
    rclone mkdir "${gdrive_remote}:${gdrive_folder}" 2>/dev/null || true

    # 5. Launch daemon in background with flock guard
    echo -e "${CYAN}🚀 Đang khởi động 3D Output Sync Watcher...${NC}"
    (
        gdrive_3d_watcher_daemon "$output_dir" "$gdrive_remote" "$gdrive_folder" "$lock_file" "$pid_file" "$log_file" "$state_file"
    ) >/dev/null 2>&1 &

    local daemon_pid=$!
    echo "$daemon_pid" > "$pid_file"
    sleep 0.5

    # Verify daemon started and PID is active
    if kill -0 "$daemon_pid" 2>/dev/null; then
        echo -e "${GREEN}✅ 3D Output Sync Watcher đã khởi động thành công (PID: $daemon_pid)!${NC}"
        echo -e "   📁 Thư mục output: ${WHITE}$output_dir${NC}"
        echo -e "   ☁️ Thư mục Drive:  ${GREEN}${gdrive_remote}:${gdrive_folder}${NC}"
        echo -e "   📋 Xem nhật ký:    ${CYAN}tail -f $log_file${NC}"
        return 0
    fi

    echo -e "${RED}❌ Không thể khởi động 3D Output Sync Watcher. Kiểm tra log: $log_file${NC}" >&2
    return 1
}

stop_gdrive_3d_watcher() {
    local comfy_base="${1:-${COMFY_BASE:-}}"

    if [ -z "$comfy_base" ]; then
        for cand in "/workspace/ComfyUI" "/root/ComfyUI" "$HOME/ComfyUI" "$(pwd)"; do
            if [ -f "$cand/.gdrive_3d_watcher.pid" ] || [ -f "$cand/$GDRIVE_MARKER_FILENAME" ]; then
                comfy_base="$cand"
                break
            fi
        done
    fi

    local pid_file="${comfy_base:+$comfy_base/.gdrive_3d_watcher.pid}"
    local lock_file="${comfy_base:+$comfy_base/.gdrive_3d_watcher.lock}"

    # Remove marker when explicitly stopped so future runs don't auto-start without permission
    [ -n "$comfy_base" ] && remove_gdrive_marker "$comfy_base"

    if [ -z "$pid_file" ] || [ ! -f "$pid_file" ]; then
        if [ -f "/tmp/gdrive_watcher.pid" ]; then
            pid_file="/tmp/gdrive_watcher.pid"
        else
            echo -e "${YELLOW}ℹ️ Không tìm thấy tiến trình 3D Output Watcher nào đang chạy.${NC}"
            return 0
        fi
    fi

    local target_pid
    target_pid="$(cat "$pid_file" 2>/dev/null || echo "")"

    if [ -z "$target_pid" ]; then
        echo -e "${YELLOW}ℹ️ PID file rỗng. Xóa file trạng thái.${NC}"
        rm -f "$pid_file" "$lock_file" 2>/dev/null || true
        return 0
    fi

    # Safety check: do not signal ourselves
    if [ "$target_pid" = "$$" ] || [ "$target_pid" = "${BASHPID:-$$}" ]; then
        rm -f "$pid_file" "$lock_file" 2>/dev/null || true
        return 0
    fi

    if kill -0 "$target_pid" 2>/dev/null; then
        echo -e "${CYAN}🛑 Đang dừng 3D Output Watcher (PID: $target_pid)...${NC}"
        kill -TERM "$target_pid" 2>/dev/null || true

        local wait_count=0
        while kill -0 "$target_pid" 2>/dev/null && [ $wait_count -lt 6 ]; do
            sleep 0.5
            wait_count=$((wait_count + 1))
        done

        if kill -0 "$target_pid" 2>/dev/null; then
            echo -e "${YELLOW}⚠️ Tiến trình chưa dừng hẳn. Gửi SIGKILL...${NC}"
            kill -KILL "$target_pid" 2>/dev/null || true
            sleep 0.2
        fi

        echo -e "${GREEN}✅ Đã dừng 3D Output Watcher (PID: $target_pid).${NC}"
    else
        echo -e "${YELLOW}ℹ️ Tiến trình (PID: $target_pid) không còn hoạt động.${NC}"
    fi

    rm -f "$pid_file" "$lock_file" 2>/dev/null || true
    return 0
}

status_gdrive_3d_watcher() {
    local comfy_base="${1:-${COMFY_BASE:-}}"

    if [ -z "$comfy_base" ]; then
        for cand in "/workspace/ComfyUI" "/root/ComfyUI" "$HOME/ComfyUI" "$(pwd)"; do
            if [ -f "$cand/.gdrive_3d_watcher.pid" ]; then
                comfy_base="$cand"
                break
            fi
        done
    fi

    local pid_file="${comfy_base:+$comfy_base/.gdrive_3d_watcher.pid}"
    local log_file="${comfy_base:+$comfy_base/.gdrive_3d_watcher.log}"
    local marker_path
    marker_path="$(get_gdrive_marker_path "$comfy_base")"

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}📊 TRẠNG THÁI 3D OUTPUT GOOGLE DRIVE SYNC WATCHER${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if [ -n "$pid_file" ] && [ -f "$pid_file" ]; then
        local pid
        pid="$(cat "$pid_file" 2>/dev/null || echo "")"
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo -e "  • Trạng thái : ${GREEN}ĐANG CHẠY (ACTIVE)${NC}"
            echo -e "  • PID        : ${WHITE}$pid${NC}"
            echo -e "  • ComfyUI Base: ${WHITE}${comfy_base:-N/A}${NC}"
            echo -e "  • Output Dir : ${WHITE}${comfy_base:+$comfy_base/output}${NC}"
            echo -e "  • Log File   : ${CYAN}${log_file:-/tmp/gdrive_3d_watcher.log}${NC}"
            [ -f "$marker_path" ] && echo -e "  • Marker     : ${GREEN}ĐÃ LƯU CẤU HÌNH AUTO-START${NC}"
            return 0
        else
            echo -e "  • Trạng thái : ${YELLOW}STALE (PID $pid không còn tồn tại)${NC}"
            return 1
        fi
    else
        echo -e "  • Trạng thái : ${YELLOW}CHƯA BẬT (STOPPED)${NC}"
        [ -f "$marker_path" ] && echo -e "  • Marker     : ${CYAN}CÓ CẤU HÌNH SẴN (TỰ KHỞI ĐỘNG KHI CHẠY SETUP)${NC}"
        return 1
    fi
}

auto_start_gdrive_watcher_if_enabled() {
    local comfy_base="${1:-${COMFY_BASE:-}}"
    if [ -z "$comfy_base" ] && command -v resolve_comfy_base &>/dev/null; then
        comfy_base="$(resolve_comfy_base 2>/dev/null || echo "")"
    fi
    if [ -z "$comfy_base" ]; then
        return 0
    fi

    # 1. If explicitly enabled via environment or CLI flags
    if [ "${ENABLE_GDRIVE:-0}" = "1" ] || [ "${ENABLE_GDRIVE_3D:-0}" = "1" ]; then
        run_stage_06
        return $?
    fi

    # 2. If valid non-secret marker exists from previous authorization
    local marker_info
    marker_info="$(read_gdrive_marker "$comfy_base" 2>/dev/null || echo "")"
    if [ -n "$marker_info" ]; then
        local remote folder
        remote="${marker_info%%|*}"
        folder="${marker_info##*|}"
        if [ -n "$remote" ] && [ -n "$folder" ]; then
            echo -e "${CYAN}🔄 Phát hiện marker Google Drive Sync đã được cấp quyền trước đó (${remote}:${folder})...${NC}"
            start_gdrive_3d_watcher "$comfy_base" "$remote" "$folder"
            return $?
        fi
    fi

    return 0
}

# ==============================================================================
# 7. STAGE 06 PIPELINE ENTRYPOINT
# ==============================================================================

run_stage_06() {
    local comfy_base="${COMFY_BASE:-}"
    local gdrive_remote="${GDRIVE_REMOTE:-gdrive}"
    local gdrive_folder="${GDRIVE_FOLDER:-}"
    local rclone_conf="${RCLONE_CONFIG_PATH:-$HOME/.config/rclone/rclone.conf}"

    # Default folder distinction:
    # --gdrive-3d uses ComfyUI_3D_Output
    # --gdrive uses ComfyUI_Output
    if [ -z "$gdrive_folder" ]; then
        if [ "${ENABLE_GDRIVE_3D:-0}" = "1" ]; then
            gdrive_folder="ComfyUI_3D_Output"
        else
            gdrive_folder="ComfyUI_Output"
        fi
    fi

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}📤 Stage 06: Tự Động Lưu Output Vào Google Drive${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Resolve ComfyUI base directory if needed
    if [ -z "$comfy_base" ] && command -v resolve_comfy_base &>/dev/null; then
        comfy_base="$(resolve_comfy_base 2>/dev/null || echo "")"
        export COMFY_BASE="$comfy_base"
    fi

    # Skip if neither CLI flag is set AND no marker exists
    if [ "${ENABLE_GDRIVE:-0}" != "1" ] && [ "${ENABLE_GDRIVE_3D:-0}" != "1" ]; then
        local marker_info
        marker_info="$(read_gdrive_marker "$comfy_base" 2>/dev/null || echo "")"
        if [ -z "$marker_info" ]; then
            echo -e "${YELLOW}⏭️  Bỏ qua Google Drive Sync (thêm --gdrive-3d hoặc --gdrive để bật).${NC}"
            return 0
        else
            gdrive_remote="${marker_info%%|*}"
            gdrive_folder="${marker_info##*|}"
        fi
    fi

    local output_dir="$comfy_base/output"
    mkdir -p "$output_dir" 2>/dev/null || true

    # 1. Check rclone.  Never mutate a provider image behind the user's back.
    if ! command -v rclone &>/dev/null; then
        echo -e "${RED}❌ Lỗi: rclone chưa được cài đặt. Hãy cài rclone trước rồi chạy lại; installer sẽ không tự thay đổi provider image.${NC}" >&2
        return 1
    else
        echo -e "${GREEN}✅ rclone đã có sẵn ($(rclone --version 2>/dev/null | head -1))${NC}"
    fi

    # 2. Check and configure Google Drive remote
    if ! rclone listremotes 2>/dev/null | grep -q "^${gdrive_remote}:"; then
        if [ -n "${GDRIVE_TOKEN:-}" ] && [ -n "${GDRIVE_CLIENT_ID:-}" ] && [ -n "${GDRIVE_CLIENT_SECRET:-}" ]; then
            echo -e "${CYAN}🔑 Đang cấu hình Google Drive bằng token từ biến môi trường...${NC}"
            mkdir -p "$(dirname "$rclone_conf")"
            chmod 700 "$(dirname "$rclone_conf")" 2>/dev/null || true
            cat >> "$rclone_conf" << RCLONE_CONF
[${gdrive_remote}]
type = drive
client_id = ${GDRIVE_CLIENT_ID}
client_secret = ${GDRIVE_CLIENT_SECRET}
token = ${GDRIVE_TOKEN}
RCLONE_CONF
            chmod 600 "$rclone_conf" 2>/dev/null || true
            echo -e "${GREEN}✅ Đã cấu hình Google Drive tự động!${NC}"
        elif [ -t 0 ]; then
            # Interactive Authorization Prompt
            echo -e ""
            echo -e "${YELLOW}╔══════════════════════════════════════════════════════╗${NC}"
            echo -e "${YELLOW}║   🔐 CẦN XÁC THỰC GOOGLE DRIVE - CHỈ LÀM 1 LẦN!   ║${NC}"
            echo -e "${YELLOW}╚══════════════════════════════════════════════════════╝${NC}"
            echo -e ""
            echo -e "${CYAN}Vì server không có trình duyệt, hãy làm theo 3 bước:${NC}"
            echo -e ""
            echo -e "${WHITE}📌 BƯỚC 1: Cài rclone trên MÁY TÍNH CÁ NHÂN của bạn:${NC}"
            echo -e "   https://rclone.org/downloads/"
            echo -e ""
            echo -e "${WHITE}📌 BƯỚC 2: Chạy lệnh này trên MÁY TÍNH CÁ NHÂN:${NC}"
            echo -e "${GREEN}   rclone authorize \"drive\"${NC}"
            echo -e ""
            echo -e "   → Nó sẽ mở trình duyệt → Đăng nhập Google → Chấp nhận"
            echo -e "   → Copy toàn bộ đoạn JSON token hiện ra"
            echo -e ""
            echo -e "${WHITE}📌 BƯỚC 3: Paste token vào đây, nhấn Enter (nhập ẩn an toàn):${NC}"
            echo -n "   Token JSON: "
            local gdrive_token_input=""
            read -rs gdrive_token_input
            echo ""

            if [ -n "$gdrive_token_input" ]; then
                mkdir -p "$(dirname "$rclone_conf")"
                chmod 700 "$(dirname "$rclone_conf")" 2>/dev/null || true
                cat >> "$rclone_conf" << RCLONE_CONF
[${gdrive_remote}]
type = drive
scope = drive
token = ${gdrive_token_input}
RCLONE_CONF
                chmod 600 "$rclone_conf" 2>/dev/null || true
                echo -e "${GREEN}✅ Đã lưu cấu hình Google Drive thành công!${NC}"
            else
                echo -e "${RED}❌ Không nhập token. Dừng cấu hình Google Drive.${NC}" >&2
                return 1
            fi
        else
            echo -e "${RED}❌ Lỗi: Google Drive remote '${gdrive_remote}:' chưa được cấu hình và môi trường non-interactive.${NC}" >&2
            echo -e "${YELLOW}💡 Cấu hình rclone trước hoặc cung cấp GDRIVE_TOKEN trong biến môi trường.${NC}" >&2
            return 1
        fi
    else
        echo -e "${GREEN}✅ Google Drive đã được kết nối (remote: ${gdrive_remote}:)${NC}"
    fi

    # Ensure rclone.conf permissions
    if [ -f "$rclone_conf" ]; then
        chmod 600 "$rclone_conf" 2>/dev/null || true
    fi

    # 3. Test remote connectivity
    echo -e "${CYAN}🔍 Kiểm tra kết nối Google Drive...${NC}"
    if ! rclone lsd "${gdrive_remote}:" --max-depth 1 &>/dev/null; then
        echo -e "${RED}❌ Không kết nối được Google Drive. Kiểm tra lại token hoặc mạng.${NC}" >&2
        return 1
    fi
    echo -e "${GREEN}✅ Kết nối Google Drive OK!${NC}"

    # 4. Save marker file ONLY AFTER successful remote connectivity verification!
    if [ -n "$comfy_base" ]; then
        save_gdrive_marker "$comfy_base" "$gdrive_remote" "$gdrive_folder"
    fi

    # 5. Check inotify-tools.  Polling with the verified dedupe state is safe
    # when it is unavailable, so do not install packages automatically.
    if ! command -v inotifywait &>/dev/null; then
        echo -e "${YELLOW}ℹ️ inotifywait chưa có; dùng polling 15 giây với chống upload lặp.${NC}"
    fi

    # 6. Start watcher daemon with flock guard
    start_gdrive_3d_watcher "$comfy_base" "$gdrive_remote" "$gdrive_folder"
    return $?
}

# Export functions for subshells
export -f get_gdrive_marker_path get_gdrive_synced_state_path save_gdrive_marker read_gdrive_marker remove_gdrive_marker is_file_already_synced mark_file_as_synced is_valid_3d_output_file wait_for_file_stable sync_single_file_safe gdrive_3d_watcher_daemon start_gdrive_3d_watcher stop_gdrive_3d_watcher status_gdrive_3d_watcher auto_start_gdrive_watcher_if_enabled run_stage_06 2>/dev/null || true

# ==============================================================================
# 8. STANDALONE CLI DISPATCHER
# ==============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    CMD="${1:-run}"
    case "$CMD" in
        --start|--start-watcher|start)
            shift
            start_gdrive_3d_watcher "$@"
            ;;
        --stop|--stop-watcher|stop)
            shift
            stop_gdrive_3d_watcher "$@"
            ;;
        --status|--status-watcher|status)
            shift
            status_gdrive_3d_watcher "$@"
            ;;
        *)
            run_stage_06 "$@"
            ;;
    esac
fi
