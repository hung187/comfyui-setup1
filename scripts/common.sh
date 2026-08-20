#!/bin/bash

if [ "${COMFY_COMMON_SH_LOADED:-}" = "1" ]; then
    return 0
fi
export COMFY_COMMON_SH_LOADED=1
export COMFY_COMMON_SH_VERSION="1"

set +e
export LC_ALL=C

# Colors for rich CLI display
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Source validation module
COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$COMMON_DIR/validation.sh" ]; then
    source "$COMMON_DIR/validation.sh"
elif [ -f "$COMMON_DIR/scripts/validation.sh" ]; then
    source "$COMMON_DIR/scripts/validation.sh"
fi

# Default global configurations
REQUIRED_SPACE_GB="${REQUIRED_SPACE_GB:-10}"
USER_AGENT="${USER_AGENT:-Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36}"
MAX_RETRIES="${MAX_RETRIES:-5}"
TIMEOUT="${TIMEOUT:-60}"
DISABLE_SSL_VERIFY="${DISABLE_SSL_VERIFY:-0}"
DRY_RUN="${DRY_RUN:-0}"
WGET_SSL_OPT=""
CURL_SSL_OPT=""
ARIA2_SSL_OPT=""
PIP_SSL_OPT=""
GIT_SSL_ENV=""
PIP_BASE_CMD=""
PYTHON_CMD="python3"
LOG_FILE=""
FAILED_LOG_FILE=""
MANIFEST_FILE=""
REPORT_FILE=""
REPORT_JSON=""
START_TIME="${START_TIME:-$(date +%s)}"
CURRENT=0
TOTAL=0

declare -a MODEL_LIST=()
declare -a AUTO_INSTALLED_TOOLS=()
declare -a FAILED_FILES=()
declare -a MIRROR_FILES=()

# Canonical helper to redact sensitive query credentials across UI, logs, states and reports
redact_url() {
    local raw_url="$1"
    if [ -z "$raw_url" ]; then
        echo ""
        return 0
    fi
    echo "$raw_url" | sed -E 's/([?&](token|api_key|apikey|key|authorization|access_token|auth|secret|signature|Signature)=)[^&[:space:]]+/\1***/g'
}

# Format config strings
resolve_config_value() {
    local value="$1"
    value="${value//\$COMFY_BASE/$COMFY_BASE}"
    value="${value//\$MODELS/$MODELS}"
    value="${value//\$CUSTOM_NODES/$CUSTOM_NODES}"
    value="${value//\$ENCODED_TOKEN/${ENCODED_TOKEN:-}}"
    printf '%s' "$value"
}

# Standalone Python helper for safe ComfyUI folder consolidation (audited for zero data loss)
consolidate_comfy_dirs() {
    local src_base="$1"
    local dst_base="$2"

    # Pre-check safe paths
    if ! validate_safe_path "$src_base" 2>/dev/null || ! validate_safe_path "$dst_base" 2>/dev/null; then
        echo -e "${RED}❌ consolidate_comfy_dirs: Đường dẫn không an toàn hoặc chứa root hệ thống!${NC}" >&2
        return 1
    fi

    python3 - "$src_base" "$dst_base" <<'PY_CONSOLIDATE'
import os, sys, shutil, hashlib, time

src_base = os.path.abspath(sys.argv[1])
dst_base = os.path.abspath(sys.argv[2])

if src_base == dst_base:
    sys.exit(0)

def get_sha256(filepath):
    if os.path.islink(filepath):
        return None
    h = hashlib.sha256()
    try:
        with open(filepath, 'rb') as f:
            while chunk := f.read(1048576):
                h.update(chunk)
        return h.hexdigest()
    except Exception:
        return None

quarantine_dir = os.path.join(dst_base, 'preserve_quarantine')
managed_subdirs = {'models', 'custom_nodes', 'output'}

# 1. Inventory all items in source directory
all_src_files = []
for root, dirs, files in os.walk(src_base, followlinks=False):
    for f in files:
        all_src_files.append(os.path.join(root, f))
    for d in dirs:
        d_path = os.path.join(root, d)
        if os.path.islink(d_path):
            all_src_files.append(d_path)

verified_migrated = set()

# 2. Migrate recognized managed folders
for s in managed_subdirs:
    src_sub = os.path.join(src_base, s)
    dst_sub = os.path.join(dst_base, s)
    if not os.path.exists(src_sub):
        continue
    os.makedirs(dst_sub, exist_ok=True)

    for root, dirs, files in os.walk(src_sub, followlinks=False):
        rel = os.path.relpath(root, src_sub)
        target_dir = os.path.join(dst_sub, rel) if rel != '.' else dst_sub
        os.makedirs(target_dir, exist_ok=True)

        for f in files:
            src_file = os.path.join(root, f)
            dst_file = os.path.join(target_dir, f)

            if os.path.islink(src_file):
                if not os.path.exists(dst_file) and not os.path.islink(dst_file):
                    link_target = os.readlink(src_file)
                    os.symlink(link_target, dst_file)
                verified_migrated.add(src_file)
                continue

            src_hash = get_sha256(src_file)
            if not os.path.exists(dst_file):
                shutil.copy2(src_file, dst_file, follow_symlinks=False)
                dst_hash = get_sha256(dst_file)
                if src_hash == dst_hash:
                    verified_migrated.add(src_file)
            else:
                dst_hash = get_sha256(dst_file) if not os.path.islink(dst_file) else None
                if src_hash and src_hash == dst_hash:
                    verified_migrated.add(src_file)
                else:
                    # Conflict: preserve into quarantine
                    src_hash_str = src_hash or 'unknown'
                    q_target = os.path.join(quarantine_dir, s, rel) if rel != '.' else os.path.join(quarantine_dir, s)
                    os.makedirs(q_target, exist_ok=True)
                    timestamp = int(time.time())
                    q_file = os.path.join(q_target, f"{src_hash_str[:8]}_{timestamp}_{f}")
                    count = 1
                    while os.path.exists(q_file):
                        q_file = os.path.join(q_target, f"{src_hash_str[:8]}_{timestamp}_{count}_{f}")
                        count += 1
                    shutil.copy2(src_file, q_file, follow_symlinks=False)
                    q_hash = get_sha256(q_file)
                    if src_hash == q_hash:
                        verified_migrated.add(src_file)

# 3. Preserve any unclassified / extra user files and directories (input/, user/, workflows, etc.)
for root, dirs, files in os.walk(src_base, followlinks=False):
    rel_root = os.path.relpath(root, src_base)
    top_dir = rel_root.split(os.sep)[0] if rel_root != '.' else '.'
    if top_dir in managed_subdirs:
        continue

    # Unmanaged directory or top-level file
    target_q_dir = os.path.join(quarantine_dir, 'unclassified_secondary', rel_root) if rel_root != '.' else os.path.join(quarantine_dir, 'unclassified_secondary')
    os.makedirs(target_q_dir, exist_ok=True)

    for f in files:
        src_file = os.path.join(root, f)
        if src_file in verified_migrated:
            continue
        dst_file = os.path.join(target_q_dir, f)
        if os.path.islink(src_file):
            if not os.path.exists(dst_file) and not os.path.islink(dst_file):
                os.symlink(os.readlink(src_file), dst_file)
            verified_migrated.add(src_file)
            continue

        src_hash = get_sha256(src_file)
        shutil.copy2(src_file, dst_file, follow_symlinks=False)
        dst_hash = get_sha256(dst_file)
        if src_hash == dst_hash:
            verified_migrated.add(src_file)

# 4. Final verification: Check that 100% of source files were verified
unaccounted = [f for f in all_src_files if f not in verified_migrated]
if unaccounted:
    print(f"ERROR: {len(unaccounted)} files failed migration verification!", file=sys.stderr)
    for u in unaccounted[:5]:
        print(f"  Unaccounted: {u}", file=sys.stderr)
    sys.exit(1)

print("SUCCESS: 100% of files verified and preserved.")
sys.exit(0)
PY_CONSOLIDATE
}

# Auto-detect ComfyUI path across Cloud Servers & Local Machines + Safe Non-Destructive Consolidation
resolve_comfy_base() {
    local candidate_cli="${1:-}"
    local primary_target=""

    # CLI / Env explicit override takes priority
    if [ -n "$candidate_cli" ]; then
        primary_target="$candidate_cli"
    elif [ -n "${COMFY_BASE:-}" ]; then
        primary_target="$COMFY_BASE"
    elif [ -n "${COMFYUI_PATH:-}" ]; then
        primary_target="$COMFYUI_PATH"
    fi

    # Known common cloud & server paths
    local search_paths=(
        "/app/ComfyUI"
        "/app/comfyUI"
        "/workspace/ComfyUI"
        "/workspace/comfyui"
        "/content/ComfyUI"
        "/content/drive/MyDrive/ComfyUI"
        "/kaggle/working/ComfyUI"
        "/opt/ml/code/ComfyUI"
        "$HOME/ComfyUI"
        "$HOME/comfyui"
        "$PWD/ComfyUI"
        "$PWD"
    )

    # 1. Collect all valid existing ComfyUI installations
    local existing_dirs=()
    for p in "${search_paths[@]}"; do
        if [ -d "$p" ] && { [ -f "$p/main.py" ] || [ -f "$p/folder_paths.py" ]; }; then
            local real_p
            real_p=$(readlink -f "$p" 2>/dev/null || echo "$p")
            local already_added=0
            for e in "${existing_dirs[@]}"; do
                if [ "$e" = "$real_p" ]; then
                    already_added=1
                    break
                fi
            done
            if [ $already_added -eq 0 ]; then
                existing_dirs+=("$real_p")
            fi
        fi
    done

    # Fallback to system-wide search if no standard path had main.py
    if [ ${#existing_dirs[@]} -eq 0 ]; then
        while IFS= read -r found_main; do
            if [ -n "$found_main" ]; then
                local found_dir
                found_dir=$(dirname "$found_main")
                local real_p
                real_p=$(readlink -f "$found_dir" 2>/dev/null || echo "$found_dir")
                existing_dirs+=("$real_p")
            fi
        done < <(find /app /workspace /content /root /opt "$HOME" -maxdepth 3 -name "main.py" 2>/dev/null | head -n 5)
    fi

    # 2. Pick primary target directory
    if [ -z "$primary_target" ]; then
        if [ ${#existing_dirs[@]} -gt 0 ]; then
            primary_target="${existing_dirs[0]}"
        else
            if [ -d "/app" ] && [ -w "/app" ]; then
                primary_target="/app/ComfyUI"
            elif [ -d "/workspace" ] && [ -w "/workspace" ]; then
                primary_target="/workspace/ComfyUI"
            elif [ -d "/content" ] && [ -w "/content" ]; then
                primary_target="/content/ComfyUI"
            else
                primary_target="$HOME/ComfyUI"
            fi
        fi
    fi

    primary_target=$(readlink -f "$primary_target" 2>/dev/null || echo "$primary_target")

    # Safety Guard on primary_target
    if ! validate_safe_path "$primary_target" 2>/dev/null; then
        echo -e "${RED}⚠️  COMFY_BASE target không an toàn ($primary_target), fallback về $HOME/ComfyUI${NC}" >&2
        primary_target="$HOME/ComfyUI"
    fi

    mkdir -p "$primary_target" 2>/dev/null || true

    # 3. SAFE Consolidation: Full inventory + verification before any deletion
    if [ ${#existing_dirs[@]} -gt 1 ]; then
        echo -e "${YELLOW}🔍 Phát hiện có ${#existing_dirs[@]} thư mục ComfyUI trên hệ thống!${NC}" >&2
        echo -e "${GREEN}🎯 Thư mục chính được chọn:${NC} $primary_target" >&2

        for dup in "${existing_dirs[@]}"; do
            local dup_real
            dup_real=$(readlink -f "$dup" 2>/dev/null || echo "$dup")

            # === SANITY GUARDS BEFORE ANY OPERATION ===
            if ! validate_safe_path "$dup_real" 2>/dev/null; then
                echo -e "${RED}⚠️  Bỏ qua đường dẫn không an toàn hoặc thư mục gốc hệ thống:${NC} $dup_real" >&2
                continue
            fi

            if [ "$dup_real" != "$primary_target" ] && [ -d "$dup_real" ]; then
                echo -e "${YELLOW}📦 Đang kiểm tra & gộp an toàn dữ liệu từ thư mục phụ ($dup_real)...${NC}" >&2

                if consolidate_comfy_dirs "$dup_real" "$primary_target" >&2; then
                    # Verify ComfyUI marker in candidate before safe cleanup
                    if [ -f "$dup_real/main.py" ] || [ -f "$dup_real/folder_paths.py" ] || [ -d "$dup_real/models" ]; then
                        echo -e "${GREEN}✅ Đã di chuyển và xác thực 100% dữ liệu từ $dup_real an toàn.${NC}" >&2
                        rm -rf "$dup_real" 2>/dev/null || true
                    else
                        echo -e "${YELLOW}⚠️  Thiếu marker ComfyUI, giữ nguyên $dup_real.${NC}" >&2
                    fi
                else
                    echo -e "${RED}⚠️  Có file chưa được xác thực trong $dup_real. GIỮ NGUYÊN THƯ MỤC để đảm bảo an toàn tuyệt đối.${NC}" >&2
                fi
            fi
        done
    else
        echo -e "${GREEN}🔍 Phát hiện thư mục ComfyUI hiện có tại:${NC} $primary_target" >&2
    fi

    printf '%s\n' "$primary_target"
}

# Auto-install missing tools dynamically
ensure_tool_installed() {
    local tool="$1"
    local apt_pkg="$2"

    if command -v "$tool" &>/dev/null; then
        echo -e "   ${GREEN}✅ $tool đã có sẵn${NC}"
        return 0
    fi

    echo -e "   ${YELLOW}⚠️  Thiếu công cụ '$tool', đang tự động tải & cài đặt...${NC}"

    # Try apt-get if available
    if command -v apt-get &>/dev/null; then
        local SUDO=""
        if [ "$(id -u)" -ne 0 ] && command -v sudo &>/dev/null; then
            SUDO="sudo"
        fi
        $SUDO apt-get update -qq 2>/dev/null || true
        if $SUDO apt-get install -y -qq $apt_pkg &>/dev/null; then
            echo -e "   ${GREEN}✅ Cài đặt thành công '$tool' qua apt-get!${NC}"
            AUTO_INSTALLED_TOOLS+=("$tool (apt)")
            return 0
        fi
    fi

    # Try python pip if applicable
    if [ "$tool" = "jq" ] && command -v pip3 &>/dev/null; then
        pip3 install --quiet jq 2>/dev/null || true
    fi

    # Re-check after installation attempt
    if command -v "$tool" &>/dev/null; then
        echo -e "   ${GREEN}✅ Công cụ '$tool' đã sẵn sàng!${NC}"
        AUTO_INSTALLED_TOOLS+=("$tool")
        return 0
    else
        echo -e "   ${RED}❌ Bỏ qua cài '$tool' (không đủ quyền root/apt-get). Script sẽ tự chọn công cụ thay thế nếu có.${NC}"
        return 1
    fi
}

# Initialize environment paths and flags
init_runtime_env() {
    export LC_ALL=C
    COMFY_BASE="$(resolve_comfy_base "${COMFY_BASE:-}")"
    MODELS="$COMFY_BASE/models"
    CUSTOM_NODES="$COMFY_BASE/custom_nodes"
    export COMFY_BASE MODELS CUSTOM_NODES REQUIRED_SPACE_GB DISABLE_SSL_VERIFY DRY_RUN

    if [ "$DISABLE_SSL_VERIFY" = "1" ]; then
        WGET_SSL_OPT="--no-check-certificate"
        CURL_SSL_OPT="-k"
        ARIA2_SSL_OPT="--check-certificate=false"
        PIP_SSL_OPT="--trusted-host pypi.org --trusted-host files.pythonhosted.org --trusted-host download.pytorch.org"
        GIT_SSL_ENV="GIT_SSL_NO_VERIFY=true"
    fi

    # Auto-detect Python executable with ComfyUI virtualenv priority
    if [ -x "$COMFY_BASE/venv/bin/python" ]; then
        PYTHON_CMD="$COMFY_BASE/venv/bin/python"
    elif [ -x "$COMFY_BASE/.venv/bin/python" ]; then
        PYTHON_CMD="$COMFY_BASE/.venv/bin/python"
    elif command -v python3 &>/dev/null; then
        PYTHON_CMD="$(command -v python3)"
    elif command -v python &>/dev/null; then
        PYTHON_CMD="$(command -v python)"
    else
        echo -e "${RED}❌ Python không tìm thấy trên hệ thống.${NC}"
        return 1
    fi

    PIP_BASE_CMD="$PYTHON_CMD -m pip"
    export PYTHON_CMD PIP_BASE_CMD

    mkdir -p "$COMFY_BASE" "$MODELS" "$CUSTOM_NODES"

    if [ -z "$LOG_FILE" ]; then
        LOG_FILE="$COMFY_BASE/setup_log.txt"
    fi
    if [ -z "$FAILED_LOG_FILE" ]; then
        FAILED_LOG_FILE="$COMFY_BASE/failed_downloads.log"
    fi
    if [ -z "$MANIFEST_FILE" ]; then
        MANIFEST_FILE="$COMFY_BASE/manifest.json"
    fi
    if [ -z "$REPORT_FILE" ]; then
        REPORT_FILE="$COMFY_BASE/SETUP_REPORT.md"
    fi
    if [ -z "$REPORT_JSON" ]; then
        REPORT_JSON="$COMFY_BASE/setup_report.json"
    fi

    return 0
}

log_event() {
    local level="$1"
    local raw_message="$2"
    local message
    message=$(redact_url "$raw_message")

    if [ -n "${LOG_FILE:-}" ]; then
        mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
        echo "$(date '+%Y-%m-%d %H:%M:%S') | $level | $message" >> "$LOG_FILE"
    fi
    if [ "$level" = "FAIL" ] && [ -n "${FAILED_LOG_FILE:-}" ]; then
        mkdir -p "$(dirname "$FAILED_LOG_FILE")" 2>/dev/null || true
        echo "$(date '+%Y-%m-%d %H:%M:%S') | FAIL | $message" >> "$FAILED_LOG_FILE"
    fi
}

check_disk_space() {
    local avail_space_gb
    avail_space_gb=$(df -BG "$COMFY_BASE" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ -z "$avail_space_gb" ]; then
        echo -e "${YELLOW}⚠️  Không thể kiểm tra dung lượng ổ đĩa.${NC}"
        return 0
    elif [ "$avail_space_gb" -lt "$REQUIRED_SPACE_GB" ]; then
        echo -e "${RED}❌ Dung lượng đĩa còn quá ít: ${avail_space_gb}GB, nhỏ hơn ngưỡng tối thiểu ${REQUIRED_SPACE_GB}GB. Tạm dừng để tránh tràn đĩa.${NC}"
        log_event "DISK_LOW" "Space: ${avail_space_gb}GB < ${REQUIRED_SPACE_GB}GB"
        return 1
    else
        echo -e "${GREEN}✅ Dung lượng trống: ${avail_space_gb}GB${NC}"
        return 0
    fi
}

# Standalone Python model file validator (validates tensor offsets & handles SHA256 reliably)
verify_model_file_internal() {
    local file_path="$1"
    local expected_sha256="${2:-}"

    python3 - "$file_path" "$expected_sha256" <<'PY_VERIFY'
import sys, os, json, hashlib

filepath = sys.argv[1]
expected_sha = sys.argv[2].strip().lower() if len(sys.argv) > 2 else ""

try:
    if not os.path.exists(filepath):
        print("0")
        sys.exit(0)

    file_size = os.path.getsize(filepath)
    if not expected_sha and file_size < 100000:
        print("0")
        sys.exit(0)

    with open(filepath, 'rb') as f:
        head = f.read(4096)

    # 1. HTML / XML / JSON Error page detection
    head_lower = head[:1024].lower().strip()
    if (head_lower.startswith(b'<html') or
        head_lower.startswith(b'<!doctype') or
        head_lower.startswith(b'<?xml') or
        head_lower.startswith(b'{"error"') or
        head_lower.startswith(b'{"message"') or
        head_lower.startswith(b'{"statuscode"') or
        b'<title>404' in head_lower or
        b'<title>403' in head_lower or
        b'<title>500' in head_lower or
        (b'cloudflare' in head_lower and b'error' in head_lower)):
        print("0")
        sys.exit(0)

    # 2. Text file / Shell script rejection (Shebang or non-binary plain text)
    if head.startswith(b'#!/') or head.startswith(b'# ---') or head.startswith(b'/*') or head.startswith(b'//'):
        print("0")
        sys.exit(0)

    is_safetensors = filepath.endswith('.safetensors') or filepath.endswith('.safetensors.part')

    # 3. Safetensors validation: uint64 header size + JSON parse + Tensor Offset Body Boundary Check
    if is_safetensors or len(head) >= 8:
        header_len = int.from_bytes(head[:8], 'little')
        if 0 < header_len < 100000000 and (8 + header_len) <= file_size:
            with open(filepath, 'rb') as f:
                f.seek(8)
                json_bytes = f.read(header_len)
                try:
                    meta = json.loads(json_bytes.decode('utf-8'))
                    if isinstance(meta, dict):
                        body_start = 8 + header_len
                        valid_tensors_found = 0
                        for k, v in meta.items():
                            if k == '__metadata__':
                                continue
                            if isinstance(v, dict) and 'data_offsets' in v:
                                offsets = v['data_offsets']
                                if not isinstance(offsets, list) or len(offsets) != 2:
                                    print("0")
                                    sys.exit(0)
                                start_off, end_off = offsets[0], offsets[1]
                                if not (0 <= start_off <= end_off):
                                    print("0")
                                    sys.exit(0)
                                if (body_start + end_off) > file_size:
                                    # Truncated tensor body!
                                    print("0")
                                    sys.exit(0)
                                valid_tensors_found += 1

                        if is_safetensors and valid_tensors_found == 0 and '__metadata__' not in meta:
                            print("0")
                            sys.exit(0)

                        # Passed safetensors structural integrity check
                        if expected_sha:
                            h = hashlib.sha256()
                            with open(filepath, 'rb') as vf:
                                while chunk := vf.read(1048576):
                                    h.update(chunk)
                            actual_sha = h.hexdigest().lower()
                            if actual_sha != expected_sha:
                                print("0")
                                sys.exit(0)
                        print("1")
                        sys.exit(0)
                except Exception:
                    if is_safetensors:
                        print("0")
                        sys.exit(0)

    # 4. PyTorch Zip / Pickle validation
    if head.startswith(b'PK\x03\x04') or head.startswith(b'\x80\x02') or head.startswith(b'BIN'):
        if expected_sha:
            h = hashlib.sha256()
            with open(filepath, 'rb') as vf:
                while chunk := vf.read(1048576):
                    h.update(chunk)
            if h.hexdigest().lower() != expected_sha:
                print("0")
                sys.exit(0)
        print("1")
        sys.exit(0)

    # 5. GGUF format validation
    if head.startswith(b'GGUF'):
        if expected_sha:
            h = hashlib.sha256()
            with open(filepath, 'rb') as vf:
                while chunk := vf.read(1048576):
                    h.update(chunk)
            if h.hexdigest().lower() != expected_sha:
                print("0")
                sys.exit(0)
        print("1")
        sys.exit(0)

    # 6. ONNX protobuf format validation
    if filepath.endswith('.onnx') or filepath.endswith('.onnx.part') or head.startswith(b'\x08'):
        if expected_sha:
            h = hashlib.sha256()
            with open(filepath, 'rb') as vf:
                while chunk := vf.read(1048576):
                    h.update(chunk)
            if h.hexdigest().lower() != expected_sha:
                print("0")
                sys.exit(0)
        print("1")
        sys.exit(0)

    # If format is safetensors or other known model type and reached here, reject
    if is_safetensors:
        print("0")
        sys.exit(0)

    # Generic binary validation ONLY allowed with explicit expected_sha
    if expected_sha:
        h = hashlib.sha256()
        with open(filepath, 'rb') as vf:
            while chunk := vf.read(1048576):
                h.update(chunk)
        if h.hexdigest().lower() != expected_sha:
            print("0")
            sys.exit(0)
        print("1")
        sys.exit(0)

    # Unknown un-hashed binary format -> Reject
    print("0")
except Exception:
    print("0")
PY_VERIFY
}

verify_model_file() {
    local file_path="$1"
    local expected_sha256="${2:-}"

    if [ ! -f "$file_path" ]; then
        return 1
    fi

    local is_valid
    is_valid=$(verify_model_file_internal "$file_path" "$expected_sha256")
    if [ "$is_valid" = "1" ]; then
        return 0
    else
        return 1
    fi
}

# Update source health score dynamically (POSIX concurrency-safe with fcntl.flock + Token Redaction + Exact Domain Check)
update_source_health() {
    local url="$1"
    local status="$2"
    local health_file="${COMFY_BASE:-}/source_health.json"

    [ -z "${COMFY_BASE:-}" ] && return 0

    python3 - "$health_file" "$url" "$status" <<'PY_HEALTH' 2>/dev/null || true
import sys, os, json, time, urllib.parse, fcntl, re

health_file, url, status = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    parsed = urllib.parse.urlparse(url)
    hostname = (parsed.hostname or "").lower()
except Exception:
    hostname = ""

if not hostname:
    sys.exit(0)

clean_domain = re.sub(r'([?&](token|api_key|apikey|key|authorization|access_token|auth|secret|signature)=)[^&]+', r'\1***', hostname)

lock_file = health_file + '.lock'
os.makedirs(os.path.dirname(health_file), exist_ok=True)

try:
    with open(lock_file, 'w') as lock_f:
        fcntl.flock(lock_f, fcntl.LOCK_EX)
        try:
            data = {}
            if os.path.exists(health_file):
                try:
                    with open(health_file, 'r') as f:
                        data = json.load(f)
                except Exception:
                    data = {}

            entry = data.get(clean_domain, {'success': 0, 'fails': 0, 'health_score': 100})

            # Exact domain and validated subdomain boundary trust check
            if (hostname == 'civitai.com' or hostname.endswith('.civitai.com') or
                hostname == 'huggingface.co' or hostname.endswith('.huggingface.co') or hostname.endswith('.hf.co') or
                hostname == 'github.com' or hostname.endswith('.github.com') or hostname.endswith('.githubusercontent.com')):
                entry['trust_tier'] = 100
            elif hostname == 'hf-mirror.com' or hostname.endswith('.hf-mirror.com') or hostname == 'ghproxy.net' or hostname.endswith('.ghproxy.net'):
                entry['trust_tier'] = 85
            else:
                entry['trust_tier'] = 75

            if status == 'ok':
                entry['success'] = entry.get('success', 0) + 1
                entry['health_score'] = min(100, entry.get('health_score', 100) + 5)
            elif status == '404':
                entry['fails'] = entry.get('fails', 0) + 1
                entry['health_score'] = max(0, entry.get('health_score', 100) - 40)
            elif status == '429':
                entry['fails'] = entry.get('fails', 0) + 1
                entry['health_score'] = max(0, entry.get('health_score', 100) - 15)
            elif status == 'corrupted':
                entry['fails'] = entry.get('fails', 0) + 1
                entry['health_score'] = max(0, entry.get('health_score', 100) - 60)
            else:
                entry['fails'] = entry.get('fails', 0) + 1
                entry['health_score'] = max(0, entry.get('health_score', 100) - 20)

            entry['last_status'] = status
            entry['updated_at'] = int(time.time())
            data[clean_domain] = entry

            tmp_file = f"{health_file}.tmp.{os.getpid()}_{time.time_ns()}"
            with open(tmp_file, 'w') as f:
                json.dump(data, f, indent=2)
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp_file, health_file)
        finally:
            fcntl.flock(lock_f, fcntl.LOCK_UN)
except Exception:
    pass
PY_HEALTH
}

# Cross-source .part contamination prevention via sidecar metadata
manage_part_metadata() {
    local url="$1"
    local part_file="$2"
    local expected_sha256="${3:-}"
    local action="${4:-check}"
    local meta_file="${part_file}.meta.json"

    python3 - "$url" "$part_file" "$expected_sha256" "$action" "$meta_file" <<'PY_PART_META'
import sys, os, json, time, re

url, part_file, expected_sha, action, meta_file = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
clean_url = re.sub(r'([?&](token|api_key|apikey|key|authorization|access_token|auth|secret|signature)=)[^&]+', r'\1***', url)

if action == 'check':
    if os.path.exists(part_file) and os.path.exists(meta_file):
        try:
            with open(meta_file, 'r') as f:
                meta = json.load(f)
            meta_url = meta.get('source_url', '')
            meta_sha = meta.get('expected_sha256', '')
            # If same source URL OR verified identical expected_sha256 -> Safe to resume
            if meta_url == clean_url or (expected_sha and meta_sha and meta_sha.lower() == expected_sha.lower()):
                print("RESUME_OK")
                sys.exit(0)
            else:
                # Cross-source mismatch! Quarantine old part file to avoid contamination
                timestamp = int(time.time())
                q_part = f"{part_file}.cross_source_quarantine_{timestamp}"
                try:
                    os.replace(part_file, q_part)
                except Exception:
                    pass
                print("RESET_DIFFERENT_SOURCE")
        except Exception:
            print("RESET_CORRUPT_META")
    else:
        print("FRESH_START")

    # Write initial/updated metadata
    try:
        os.makedirs(os.path.dirname(meta_file), exist_ok=True)
        with open(meta_file, 'w') as f:
            json.dump({
                'source_url': clean_url,
                'expected_sha256': expected_sha,
                'created_at': int(time.time())
            }, f, indent=2)
    except Exception:
        pass
PY_PART_META
}

# Single URL downloader supporting aria2c -> wget -> curl -> python with memory-safe streaming & TLS defaults
exec_download_tool() {
    local url="$1"
    local part_file="$2"
    local expected_sha256="${3:-}"
    local user_agent="${USER_AGENT:-Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36}"
    local max_retries="${MAX_RETRIES:-5}"
    local timeout="${TIMEOUT:-60}"

    mkdir -p "$(dirname "$part_file")"

    # Check and guard .part sidecar metadata against cross-source contamination
    local part_status
    part_status=$(manage_part_metadata "$url" "$part_file" "$expected_sha256" "check")
    if [ "$part_status" = "RESET_DIFFERENT_SOURCE" ]; then
        echo -e "   ${YELLOW}⚠️  Phát hiện file .part từ nguồn khác không tương thích - Đã reset an toàn để tránh nhiễm byte.${NC}"
    fi

    # Probe Content-Length / Range support for intelligent concurrency tuning
    local max_conn_limit="${ARIA2_CONNECTIONS_MAX:-8}"
    local connections=4
    local split=4

    local probed_size
    probed_size=$(curl -sIL -A "$user_agent" --connect-timeout 5 "$url" 2>/dev/null | grep -i '^content-length:' | tail -n1 | tr -d '\r' | awk '{print $2}' || echo 0)

    if [ -n "$probed_size" ] && [ "$probed_size" -gt 0 ] 2>/dev/null; then
        if [ "$probed_size" -lt 33554432 ]; then # < 32 MB
            connections=2
            split=2
        elif [ "$probed_size" -lt 268435456 ]; then # 32 MB - 256 MB
            connections=4
            split=4
        else # > 256 MB
            connections=8
            split=8
        fi
    fi

    # Reduce concurrency if host recently encountered 429 rate limits
    if [ -f "${COMFY_BASE:-}/source_health.json" ]; then
        local has_recent_429
        has_recent_429=$(python3 - "$COMFY_BASE/source_health.json" "$url" <<'PY_CHECK_429' 2>/dev/null || echo "0"
import sys, json, urllib.parse
hf, u = sys.argv[1], sys.argv[2]
try:
    domain = urllib.parse.urlparse(u).netloc
    with open(hf) as f:
        data = json.load(f)
    entry = data.get(domain, {})
    print("1" if entry.get("last_status") == "429" else "0")
except Exception:
    print("0")
PY_CHECK_429
)
        if [ "$has_recent_429" = "1" ]; then
            connections=2
            split=2
        fi
    fi

    # Clamp connections to ARIA2_CONNECTIONS_MAX (bounded between 1 and 16)
    if [ "$connections" -gt "$max_conn_limit" ]; then
        connections="$max_conn_limit"
        split="$max_conn_limit"
    fi
    if [ "$connections" -gt 16 ]; then
        connections=16
        split=16
    fi
    if [ "$connections" -lt 1 ]; then
        connections=1
        split=1
    fi

    if command -v aria2c &>/dev/null; then
        echo -e "   ${BLUE}⚡ Tải qua aria2c (Resumable + 307 follow)...${NC}"
        if aria2c $ARIA2_SSL_OPT \
               --user-agent="$user_agent" \
               --max-connection-per-server="$connections" \
               --split="$split" \
               --min-split-size=2M \
               --console-log-level=error \
               --summary-interval=0 \
               --timeout="$timeout" \
               --max-tries="$max_retries" \
               --retry-wait=2 \
               --continue=true \
               --max-file-not-found=3 \
               --dir="$(dirname "$part_file")" \
               --out="$(basename "$part_file")" \
               "$url" >/dev/null 2>&1; then
            if verify_model_file "$part_file" "$expected_sha256"; then
                update_source_health "$url" "ok"
                return 0
            fi
        fi
    fi

    if command -v wget &>/dev/null; then
        echo -e "   ${BLUE}🐢 Tải qua wget (Resumable + User-Agent)...${NC}"
        if wget -c $WGET_SSL_OPT \
                --user-agent="$user_agent" \
                --max-redirect=10 \
                --tries="$max_retries" \
                --waitretry=2 \
                --timeout="$timeout" \
                -q --show-progress \
                -O "$part_file" "$url"; then
            if verify_model_file "$part_file" "$expected_sha256"; then
                update_source_health "$url" "ok"
                return 0
            fi
        fi
    fi

    if command -v curl &>/dev/null; then
        echo -e "   ${BLUE}🔄 Tải qua curl (-L 307 follow + Resume)...${NC}"
        if curl -L -C - $CURL_SSL_OPT \
                -A "$user_agent" \
                --max-redirs 10 \
                --retry "$max_retries" \
                --retry-delay 2 \
                --connect-timeout "$timeout" \
                -o "$part_file" "$url" >/dev/null 2>&1; then
            if verify_model_file "$part_file" "$expected_sha256"; then
                update_source_health "$url" "ok"
                return 0
            fi
        fi
    fi

    if command -v python3 &>/dev/null; then
        echo -e "   ${BLUE}🐍 Tải qua Python urllib (Chunked Streaming + TLS Verified)...${NC}"
        if $PYTHON_CMD - "$url" "$part_file" "$user_agent" "$timeout" "${DISABLE_SSL_VERIFY:-0}" <<'PY_STREAM' >/dev/null 2>&1
import sys, os, urllib.request, ssl

url, out, ua, timeout, dis_ssl = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5]

# TLS Verification enabled by default; only disabled when DISABLE_SSL_VERIFY=1
if dis_ssl == "1":
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
else:
    ctx = ssl.create_default_context()

req = urllib.request.Request(url, headers={'User-Agent': ua})

# Check if resuming partial file
mode = 'wb'
headers_range = {}
if os.path.exists(out):
    cur_size = os.path.getsize(out)
    if cur_size > 0:
        req.add_header('Range', f'bytes={cur_size}-')
        mode = 'ab'

with urllib.request.urlopen(req, context=ctx, timeout=timeout) as resp:
    # If server sent HTTP 200 instead of 206, start fresh to prevent duplicate bytes
    if resp.status == 200 and mode == 'ab':
        mode = 'wb'
    with open(out, mode) as f:
        while True:
            chunk = resp.read(4 * 1024 * 1024) # 4MB chunked streaming
            if not chunk:
                break
            f.write(chunk)
PY_STREAM
        then
            if verify_model_file "$part_file" "$expected_sha256"; then
                update_source_health "$url" "ok"
                return 0
            fi
        fi
    fi

    update_source_health "$url" "fail"
    return 1
}

# Kiểm tra link còn sống hay không
check_url_alive() {
    local url="$1"
    local user_agent="${USER_AGENT:-Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36}"
    local http_code=0

    if command -v curl &>/dev/null; then
        http_code=$(curl -s -o /dev/null -w "%{http_code}" \
            --max-time 10 --connect-timeout 8 \
            -L --head \
            ${CURL_SSL_OPT} \
            -A "$user_agent" \
            "$url" 2>/dev/null || echo "0")
    elif command -v wget &>/dev/null; then
        if wget -q --spider --timeout=10 --tries=1 --user-agent="$user_agent" ${WGET_SSL_OPT} "$url" 2>/dev/null; then
            http_code=200
        else
            http_code=0
        fi
    else
        return 0
    fi

    case "$http_code" in
        200|201|206|301|302|303|307|308)
            return 0 ;;
        401|403)
            return 0 ;;
        404|410|451)
            update_source_health "$url" "404"
            return 1 ;;
        429)
            update_source_health "$url" "429"
            return 0 ;;
        0|"")
            return 1 ;;
        *)
            return 1 ;;
    esac
}

# Generate fallback mirror URLs dynamically based on primary link platform
generate_mirror_urls() {
    local primary_url="$1"
    local explicit_alts="${2:-}"
    local mirrors=()

    if [ -n "$explicit_alts" ]; then
        IFS=',' read -ra ALT_ARR <<< "$explicit_alts"
        for alt in "${ALT_ARR[@]}"; do
            alt="$(echo -n "$alt" | xargs)"
            if [ -n "$alt" ]; then
                local alt_trust
                alt_trust=$(classify_source_trust "$alt")
                if [ "$alt_trust" != "FORBIDDEN" ]; then
                    mirrors+=("$alt")
                fi
            fi
        done
    fi

    if [[ "$primary_url" == *"huggingface.co"* ]]; then
        local mirror_hf="${primary_url/huggingface.co/hf-mirror.com}"
        local short_hf="${primary_url/huggingface.co/hf.co}"
        mirrors+=("$mirror_hf" "$short_hf")
    elif [[ "$primary_url" == *"github.com"* ]]; then
        local gh_proxy1="https://ghproxy.net/$primary_url"
        local gh_proxy2="https://gh-proxy.com/$primary_url"
        mirrors+=("$gh_proxy1" "$gh_proxy2")
    elif [[ "$primary_url" == *"civitai.com"* ]]; then
        if [[ "$primary_url" == *"&token="* ]] || [[ "$primary_url" == *"?token="* ]]; then
            local clean_url
            clean_url=$(echo "$primary_url" | sed 's/[?&]token=[^&]*//g')
            [ "$clean_url" != "$primary_url" ] && mirrors+=("$clean_url")
        fi
    fi

    printf "%s\n" "${mirrors[@]}"
}

# Smart Model Downloader with multi-source fallback mirror engine, atomic .part download & resume
download_model_smart() {
    local primary_url="$1"
    local explicit_alts="$2"
    local output_path="$3"
    local description="$4"
    local expected_sha256="${5:-}"

    # === BOUNDARY REVALIDATION (DEFENSE-IN-DEPTH) ===
    if ! validate_model_destination "$output_path" "${MODELS:-}"; then
        echo -e "   ${RED}❌ Đường dẫn lưu model không an toàn hoặc nằm ngoài MODELS: $output_path${NC}"
        log_event "FAIL" "$description | Security boundary check failed for output path: $output_path"
        return 1
    fi
    if ! validate_url "$primary_url"; then
        echo -e "   ${RED}❌ URL chính không hợp lệ hoặc thuộc tên miền bị cấm: $(redact_url "$primary_url")${NC}"
        log_event "FAIL" "$description | Primary URL validation failed: $(redact_url "$primary_url")"
        return 1
    fi
    if [ -n "$expected_sha256" ] && ! validate_sha256 "$expected_sha256"; then
        echo -e "   ${RED}❌ Định dạng SHA256 không hợp lệ cho model: $description${NC}"
        log_event "FAIL" "$description | Malformed SHA256 format: $expected_sha256"
        return 1
    fi

    local dir_name
    dir_name=$(dirname "$output_path")
    mkdir -p "$dir_name"

    # INVARIANT REQUIRED BY PARSER: Do not alter this progress format!
    echo -e "\n${CYAN}⬇️  [${CURRENT}/${TOTAL}] Tải:${NC} $description"
    echo -e "   ${YELLOW}Lưu tại:${NC} $output_path"

    # 1. Kiểm tra dung lượng đĩa khả dụng
    if ! check_disk_space; then
        echo -e "   ${RED}❌ Dung lượng ổ đĩa không đủ! Bỏ qua model này.${NC}"
        log_event "FAIL" "$description | Disk space insufficient"
        FAILED_FILES+=("$description|$output_path|$(redact_url "$primary_url")|Dung lượng đĩa không đủ (<${REQUIRED_SPACE_GB}GB)")
        return 1
    fi

    # 2. Bỏ qua file đã hoàn tất và vượt qua verification
    if [ -f "$output_path" ]; then
        if verify_model_file "$output_path" "$expected_sha256"; then
            local size_h
            size_h=$(du -sh "$output_path" | cut -f1)
            echo -e "   ${GREEN}⏩ Đã tồn tại hoàn chỉnh (${size_h}), bỏ qua.${NC}"
            log_event "SKIP" "$description | $output_path | $size_h"
            return 0
        else
            echo -e "   ${YELLOW}⚠️  File tồn tại nhưng không vượt qua kiểm tra integrity, sẽ tiến hành tải lại.${NC}"
            rm -f "$output_path"
        fi
    fi

    # 3. Dry run handling
    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo -e "   ${GREEN}🧪 [DRY_RUN] Giả lập OK:${NC} $(redact_url "$primary_url")"
        log_event "OK_PRIMARY" "$description | $output_path | $(redact_url "$primary_url") | DRY_RUN"
        return 0
    fi

    # Construct list of candidate URLs: Primary -> Alt Mirror URLs
    local candidate_urls=("$primary_url")
    mapfile -t mirrors < <(generate_mirror_urls "$primary_url" "$explicit_alts")
    for m in "${mirrors[@]}"; do
        [ -n "$m" ] && [ "$m" != "$primary_url" ] && candidate_urls+=("$m")
    done

    local part_file="${output_path}.part"
    local download_success=0
    local used_url=""
    local is_mirror=0
    local attempt_count=0

    for url in "${candidate_urls[@]}"; do
        attempt_count=$((attempt_count + 1))
        local display_url
        display_url=$(redact_url "$url")

        # Third-party Mirror Policy: auto-skip unverified 3rd party mirrors without expected SHA256
        local s_trust
        s_trust=$(classify_source_trust "$url")
        if [ "$s_trust" = "THIRD_PARTY_MIRROR" ] && [ -z "$expected_sha256" ]; then
            echo -e "   ${YELLOW}⚠️  Bỏ qua mirror bên thứ ba chưa được xác thực (không có SHA256 để verify):${NC} $display_url"
            log_event "SKIP_UNVERIFIED_MIRROR" "$description | $display_url"
            continue
        fi

        if [ $attempt_count -eq 1 ]; then
            echo -e "   ${BLUE}🌐 Link chính gốc:${NC} $display_url"
        else
            local alt_idx=$((attempt_count - 1))
            echo -e "   ${YELLOW}🔄 Link phụ dự phòng #${alt_idx}:${NC} $display_url"
            is_mirror=1
        fi

        # === KIỂM TRA LINK CÒN SỐNG TRƯỚC KHI TẢI ===
        echo -ne "   ${CYAN}🔍 Đang kiểm tra link...${NC} "
        if ! check_url_alive "$url"; then
            echo -e "${RED}❌ Link chết / không phản hồi. Bỏ qua, thử link tiếp theo...${NC}"
            log_event "DEAD_LINK" "$description | $display_url"
            continue
        fi
        echo -e "${GREEN}✅ Link OK${NC}"

        if exec_download_tool "$url" "$part_file" "$expected_sha256"; then
            if verify_model_file "$part_file" "$expected_sha256"; then
                download_success=1
                used_url="$url"
                break
            else
                echo -e "   ${RED}⚠️  File tạm không vượt qua kiểm tra integrity (có thể lỗi HTML/Redirect/Checksum). Thử nguồn khác...${NC}"
                rm -f "$part_file" "${part_file}.meta.json"
            fi
        fi
    done

    if [ $download_success -eq 1 ] && [ -f "$part_file" ]; then
        mv "$part_file" "$output_path"
        rm -f "${part_file}.meta.json"
        local size_h
        size_h=$(du -sh "$output_path" | cut -f1)

        local display_used_url
        display_used_url=$(redact_url "$used_url")

        if [ $is_mirror -eq 1 ]; then
            echo -e "   ${MAGENTA}✨ TẢI THÀNH CÔNG TỪ LINK PHỤ (${size_h})${NC}"
            log_event "OK_MIRROR" "$description | $output_path | $display_used_url | $size_h"
            MIRROR_FILES+=("$description|$output_path|$(redact_url "$primary_url")|$display_used_url|$size_h")
        else
            echo -e "   ${GREEN}✅ Thành công (${size_h})${NC}"
            log_event "OK_PRIMARY" "$description | $output_path | $size_h"
        fi
        return 0
    else
        echo -e "   ${RED}❌ TẢI THẤT BẠI TẤT CẢ NGUỒN (Link chính + Link phụ).${NC}"
        log_event "FAIL" "$description | $output_path | $(redact_url "$primary_url")"
        FAILED_FILES+=("$description|$output_path|$(redact_url "$primary_url")|Tất cả mirror đều lỗi/không phản hồi")
        rm -f "$part_file" "${part_file}.meta.json"
        return 1
    fi
}

# Clone or pull git repositories with fallback mirror proxy support
clone_or_pull() {
    local repo_url="$1"
    local target_dir="$2"
    local description="$3"

    # === BOUNDARY REVALIDATION (DEFENSE-IN-DEPTH) ===
    if ! validate_safe_path "$target_dir" 2>/dev/null; then
        echo -e "   ${RED}❌ Đường dẫn clone/pull không an toàn: '$target_dir'${NC}"
        return 1
    fi
    if [ -n "${CUSTOM_NODES:-}" ] && ! validate_node_destination "$target_dir" "$CUSTOM_NODES" 2>/dev/null; then
        echo -e "   ${RED}❌ Đường dẫn clone nằm ngoài thư mục CUSTOM_NODES: '$target_dir'${NC}"
        return 1
    fi
    if ! validate_url "$repo_url" 2>/dev/null; then
        echo -e "   ${RED}❌ URL repository không hợp lệ: '$repo_url'${NC}"
        return 1
    fi

    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo -e "   ${GREEN}🧪 [DRY_RUN] Git OK:${NC} $description"
        log_event "CLONE_OK" "$description | $target_dir | DRY_RUN"
        return 0
    fi

    if [ -d "$target_dir/.git" ]; then
        echo -e "   ${YELLOW}🔄 Cập nhật repo (git pull):${NC} $description"
        (cd "$target_dir" && env ${GIT_SSL_ENV:-} git pull --rebase --quiet) || echo -e "   ${YELLOW}⚠️ Git pull có cảnh báo${NC}"
        log_event "PULL" "$description | $target_dir"
        return 0
    elif [ -d "$target_dir" ]; then
        echo -e "   ${YELLOW}⚠️  Thư mục tồn tại nhưng không phải git repo, làm sạch và clone lại...${NC}"
        rm -rf "$target_dir"
    fi

    echo -e "   ${BLUE}📦 Clone mới:${NC} $description"

    # Try primary repo URL first
    if env ${GIT_SSL_ENV:-} git clone --quiet "$repo_url" "$target_dir" 2>/dev/null; then
        echo -e "   ${GREEN}✅ Clone thành công${NC}"
        log_event "CLONE_OK" "$description | $target_dir"
        return 0
    fi

    # Try Git Mirror proxy fallback if GitHub
    if [[ "$repo_url" == *"github.com"* ]]; then
        local mirror_git="https://ghproxy.net/$repo_url"
        echo -e "   ${YELLOW}🔄 Clone thất bại, thử git mirror phụ:${NC} $mirror_git"
        if env ${GIT_SSL_ENV:-} git clone --quiet "$mirror_git" "$target_dir" 2>/dev/null; then
            echo -e "   ${MAGENTA}✨ Clone thành công qua Git Mirror!${NC}"
            log_event "CLONE_MIRROR_OK" "$description | $target_dir | $mirror_git"
            MIRROR_FILES+=("$description|$target_dir|$(redact_url "$repo_url")|$mirror_git|Git Repo")
            return 0
        fi
    fi

    echo -e "   ${RED}❌ Clone thất bại hoàn toàn.${NC}"
    log_event "CLONE_FAIL" "$description | $target_dir"
    FAILED_FILES+=("$description|$target_dir|$(redact_url "$repo_url")|Git Clone Lỗi")
    return 1
}

install_requirements() {
    local dir="$1"
    if [ -f "$dir/requirements.txt" ]; then
        echo -e "   ${CYAN}📥 Cài dependencies cho $(basename "$dir")${NC}"

        if [ "${DRY_RUN:-0}" = "1" ]; then
            log_event "DRY_PIP_OK" "$(basename "$dir")"
            return 0
        fi

        $PIP_BASE_CMD install -r "$dir/requirements.txt" $PIP_SSL_OPT --break-system-packages >> "$COMFY_BASE/pip_install.log" 2>&1 \
            || $PIP_BASE_CMD install -r "$dir/requirements.txt" $PIP_SSL_OPT >> "$COMFY_BASE/pip_install.log" 2>&1 \
            || true
    fi
    return 0
}

export -f redact_url resolve_config_value consolidate_comfy_dirs resolve_comfy_base ensure_tool_installed init_runtime_env log_event check_disk_space verify_model_file_internal verify_model_file update_source_health manage_part_metadata exec_download_tool check_url_alive generate_mirror_urls download_model_smart clone_or_pull install_requirements 2>/dev/null || true
