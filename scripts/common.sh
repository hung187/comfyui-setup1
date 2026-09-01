#!/bin/bash
# ==============================================================================
# THƯ VIỆN DÙNG CHUNG (CORE UTILITIES) CHO COMFYUI SETUP PIPELINE
# Chứa toàn bộ các hàm dùng lại: Quản lý môi trường, Downloader, Mã hóa Token,
# Quản lý đĩa cứng, Resume Range, Liveness Probing, Verify Integrity & Logging.
# ==============================================================================

if [ "${COMFY_COMMON_SH_LOADED:-}" = "1" ]; then
    return 0 2>/dev/null || exit 0
fi
export COMFY_COMMON_SH_LOADED=1
export COMFY_COMMON_SH_VERSION="2"

set +e
export LC_ALL=C

# Colors for rich CLI display
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
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
MAX_RETRIES="${MAX_RETRIES:-3}"
TIMEOUT="${TIMEOUT:-60}"
DISABLE_SSL_VERIFY="${DISABLE_SSL_VERIFY:-0}"
DRY_RUN="${DRY_RUN:-0}"
UPDATE_EXISTING="${UPDATE_EXISTING:-0}"
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

# Calculate canonical safe source fingerprint (SHA256 of credential-stripped URL)
canonical_source_id() {
    local raw_url="$1"
    python3 - "$raw_url" <<'PY_CID'
import sys, urllib.parse, hashlib, re

raw_url = sys.argv[1] if len(sys.argv) > 1 else ""
if not raw_url:
    print("")
    sys.exit(0)

try:
    parsed = urllib.parse.urlparse(raw_url)
    qs = urllib.parse.parse_qsl(parsed.query, keep_blank_values=True)
    # Filter out sensitive credentials
    safe_qs = []
    for k, v in qs:
        k_lower = k.lower()
        if k_lower in ('token', 'api_key', 'apikey', 'key', 'authorization', 'access_token', 'auth', 'secret', 'signature'):
            continue
        safe_qs.append((k, v))
    safe_query = urllib.parse.urlencode(sorted(safe_qs))
    canonical_url = urllib.parse.urlunparse((parsed.scheme.lower(), parsed.netloc.lower(), parsed.path, parsed.params, safe_query, ""))
    cid = hashlib.sha256(canonical_url.encode('utf-8')).hexdigest()
    print(cid)
except Exception:
    print(hashlib.sha256(raw_url.encode('utf-8')).hexdigest())
PY_CID
}

# Resolve placeholders like $MODELS, $CUSTOM_NODES, $COMFY_BASE in strings
resolve_config_value() {
    local value="$1"
    value="${value//\$COMFY_BASE/$COMFY_BASE}"
    value="${value//\$MODELS/$MODELS}"
    value="${value//\$CUSTOM_NODES/$CUSTOM_NODES}"
    value="${value//\$ENCODED_TOKEN/${ENCODED_TOKEN:-}}"
    value="${value//\$CIVITAI_TOKEN/${CIVITAI_TOKEN:-}}"
    printf '%s' "$value"
}

# Reusable Civitai Credential Preparation Helper
prepare_civitai_credentials() {
    if [ -n "${CIVITAI_TOKEN:-}" ]; then
        local raw_token="${CIVITAI_TOKEN#\?}"
        raw_token="${raw_token#token=}"
        raw_token="${raw_token#&token=}"
        raw_token="$(echo -n "$raw_token" | tr -d '[:space:]')"

        if command -v jq &>/dev/null; then
            ENCODED_TOKEN=$(printf '%s' "$raw_token" | jq -sRr @uri)
        else
            ENCODED_TOKEN=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$raw_token" 2>/dev/null || echo "$raw_token")
        fi
        export CIVITAI_TOKEN="$raw_token"
        export ENCODED_TOKEN="$ENCODED_TOKEN"
        echo -e "   ${GREEN}🔑 Civitai Token: SET${NC}"
        return 0
    fi

    # Interactive prompt only if terminal is attached
    if [ -t 0 ]; then
        echo -e "\n${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║${NC}   ${MAGENTA}🔑 CẤU HÌNH CIVITAI API TOKEN (ĐỂ TẢI MODEL NSFW/EARLY)${NC}    ${YELLOW}║${NC}"
        echo -e "${YELLOW}╠══════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${YELLOW}║${NC}  Một số Checkpoints/LoRA yêu cầu Token Civitai để tải:       ${YELLOW}║${NC}"
        echo -e "${YELLOW}║${NC}  Lấy token tại: ${CYAN}https://civitai.com/user/account${NC}               ${YELLOW}║${NC}"
        echo -e "${YELLOW}║${NC}  👉 Nhập Token và nhấn [ENTER].                              ${YELLOW}║${NC}"
        echo -e "${YELLOW}║${NC}  👉 Bỏ trống / Nhấn [ENTER] ngay để bỏ qua (tải link phụ).    ${YELLOW}║${NC}"
        echo -e "${YELLOW}║${NC}  ⏱️  Tự động bỏ qua sau 5 phút nếu không có phản hồi.         ${YELLOW}║${NC}"
        echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"

        local user_input=""
        read -r -t 300 -p "🔑 Nhập Civitai API Token: " user_input || true
        echo ""
        if [ -n "$user_input" ]; then
            CIVITAI_TOKEN="$user_input"
            prepare_civitai_credentials
            return 0
        fi
    fi

    ENCODED_TOKEN=""
    export ENCODED_TOKEN=""
    echo -e "   ${YELLOW}ℹ️  Civitai Token: NOT SET (sử dụng link mirror phụ khi cần)${NC}"
    return 0
}

# Standalone Python helper for safe ComfyUI folder consolidation (audited for zero data loss)
consolidate_comfy_dirs() {
    local src_base="$1"
    local dst_base="$2"

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

all_src_files = []
for root, dirs, files in os.walk(src_base, followlinks=False):
    for f in files:
        all_src_files.append(os.path.join(root, f))
    for d in dirs:
        d_path = os.path.join(root, d)
        if os.path.islink(d_path):
            all_src_files.append(d_path)

verified_migrated = set()

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

for root, dirs, files in os.walk(src_base, followlinks=False):
    rel_root = os.path.relpath(root, src_base)
    top_dir = rel_root.split(os.sep)[0] if rel_root != '.' else '.'
    if top_dir in managed_subdirs:
        continue

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

unaccounted = [f for f in all_src_files if f not in verified_migrated]
if unaccounted:
    print(f"ERROR: {len(unaccounted)} files failed migration verification!", file=sys.stderr)
    sys.exit(1)

print("SUCCESS: 100% of files verified and preserved.")
sys.exit(0)
PY_CONSOLIDATE
}

# Verify if a directory is a valid ComfyUI installation (has main.py and strong structural markers)
is_valid_comfyui_dir() {
    local target="${1:-}"
    [ -z "$target" ] && return 1

    local real_dir
    real_dir=$(readlink -f "$target" 2>/dev/null || realpath "$target" 2>/dev/null || echo "$target")
    [ ! -d "$real_dir" ] && return 1

    local dangerous_roots=("/" "/root" "/workspace" "/app" "/content" "/home" "/etc" "/var" "/usr" "/bin" "/sbin" "/tmp" "/kaggle/working" "/opt" "/data" "/mnt")
    for dr in "${dangerous_roots[@]}"; do
        if [ "$real_dir" = "$dr" ]; then
            return 1
        fi
    done

    [ ! -f "$real_dir/main.py" ] && return 1

    # Require strong structural markers: comfy package, folder_paths.py, execution.py, or nodes.py
    if [ -d "$real_dir/comfy" ] || [ -f "$real_dir/folder_paths.py" ] || [ -f "$real_dir/execution.py" ] || [ -f "$real_dir/nodes.py" ]; then
        return 0
    fi

    return 1
}

# Inspect running processes to detect active ComfyUI instance without killing or modifying it
detect_running_comfyui() {
    python3 - <<'PY_DETECT_ACTIVE' 2>/dev/null
import os, sys, glob

active = set()

def check_dir(p):
    if not p or not os.path.isdir(p): return False
    if not os.path.isfile(os.path.join(p, "main.py")): return False
    if (
        os.path.isdir(os.path.join(p, "comfy")) or
        os.path.isfile(os.path.join(p, "folder_paths.py")) or
        os.path.isfile(os.path.join(p, "execution.py")) or
        os.path.isfile(os.path.join(p, "nodes.py"))
    ):
        return True
    return False

# Scan /proc
for p in glob.glob('/proc/[0-9]*'):
    try:
        cmd_file = os.path.join(p, 'cmdline')
        if not os.path.isfile(cmd_file):
            continue
        with open(cmd_file, 'rb') as f:
            raw = f.read()
        if not raw:
            continue
        args = [a.decode('utf-8', errors='ignore') for a in raw.split(b'\0') if a]
        cmd_str = ' '.join(args)
        if 'main.py' in cmd_str:
            for arg in args:
                if arg.endswith('main.py'):
                    if os.path.isabs(arg):
                        cand = os.path.dirname(arg)
                    else:
                        cwd = os.readlink(os.path.join(p, 'cwd'))
                        cand = os.path.normpath(os.path.join(cwd, os.path.dirname(arg)))
                    cand_real = os.path.realpath(cand)
                    if check_dir(cand_real):
                        active.add(cand_real)
            try:
                proc_cwd = os.readlink(os.path.join(p, 'cwd'))
                proc_cwd_real = os.path.realpath(proc_cwd)
                if check_dir(proc_cwd_real):
                    active.add(proc_cwd_real)
            except Exception:
                pass
    except Exception:
        continue

# Fallback ps if /proc not accessible
if not active:
    try:
        import subprocess
        out = subprocess.check_output(['ps', '-eo', 'pid,args'], text=True, stderr=subprocess.DEVNULL)
        for line in out.splitlines():
            if 'main.py' in line and ('python' in line or 'ComfyUI' in line or 'comfy' in line.lower()):
                for token in line.strip().split():
                    if token.endswith('main.py') and os.path.isabs(token):
                        cand = os.path.realpath(os.path.dirname(token))
                        if check_dir(cand):
                            active.add(cand)
    except Exception:
        pass

for a in sorted(active):
    print(a)
PY_DETECT_ACTIVE
}

# Bounded discovery of valid ComfyUI directories under known provider paths and safe roots
discover_comfyui_candidates() {
    local known_paths=(
        "/workspace/ComfyUI"
        "/workspace/comfyui"
        "/root/ComfyUI"
        "/root/comfyui"
        "/app/ComfyUI"
        "/app/comfyUI"
        "/app/comfyui"
        "/opt/ComfyUI"
        "/opt/comfyui"
        "/opt/ml/code/ComfyUI"
        "/content/ComfyUI"
        "/content/drive/MyDrive/ComfyUI"
        "/kaggle/working/ComfyUI"
        "$HOME/ComfyUI"
        "$HOME/comfyui"
        "$PWD/ComfyUI"
        "$PWD"
    )

    local found_list=()

    # 1. Direct check of known provider paths
    for kp in "${known_paths[@]}"; do
        if is_valid_comfyui_dir "$kp"; then
            local rkp
            rkp=$(readlink -f "$kp" 2>/dev/null || echo "$kp")
            local already=0
            for f in "${found_list[@]}"; do
                [ "$f" = "$rkp" ] && { already=1; break; }
            done
            [ $already -eq 0 ] && found_list+=("$rkp")
        fi
    done

    # 2. Bounded scan under safe roots (maxdepth 4)
    local scan_roots=(
        "/workspace"
        "/app"
        "/opt"
        "/content"
        "/kaggle/working"
        "/data"
        "/mnt"
        "$HOME"
    )
    [ -d "/root" ] && [ -r "/root" ] && [ "/root" != "$HOME" ] && scan_roots+=("/root")

    if [ -n "${COMFY_SCAN_EXTRA_ROOTS:-}" ]; then
        for extra in $COMFY_SCAN_EXTRA_ROOTS; do
            [ -d "$extra" ] && scan_roots+=("$extra")
        done
    fi

    for root in "${scan_roots[@]}"; do
        [ ! -d "$root" ] || [ ! -r "$root" ] && continue
        while IFS= read -r fmain; do
            [ -z "$fmain" ] && continue
            local cand_dir
            cand_dir=$(dirname "$fmain")
            if is_valid_comfyui_dir "$cand_dir"; then
                local rcand
                rcand=$(readlink -f "$cand_dir" 2>/dev/null || echo "$cand_dir")
                local already=0
                for f in "${found_list[@]}"; do
                    [ "$f" = "$rcand" ] && { already=1; break; }
                done
                [ $already -eq 0 ] && found_list+=("$rcand")
            fi
        done < <(find "$root" -maxdepth 4 -name "main.py" -type f 2>/dev/null | head -n 20)
    done

    for fl in "${found_list[@]}"; do
        printf '%s\n' "$fl"
    done
}

# Auto-detect ComfyUI path across Cloud Servers & Local Machines (Provider-Agnostic Priority)
resolve_comfy_base() {
    local candidate_cli="${1:-}"
    local allow_fresh="${2:-1}"

    # ── Priority 1: Explicit CLI (--comfy-dir) ──────────────────────────
    if [ -n "$candidate_cli" ]; then
        local real_cli
        real_cli=$(readlink -f "$candidate_cli" 2>/dev/null || echo "$candidate_cli")
        if ! validate_safe_path "$real_cli" 2>/dev/null; then
            echo -e "${RED}❌ Đường dẫn CLI --comfy-dir không an toàn hoặc không hợp lệ: $candidate_cli${NC}" >&2
            return 1
        fi
        if [ "$allow_fresh" -eq 0 ] && [ ! -d "$real_cli" ]; then
            echo -e "${RED}❌ Thư mục ComfyUI chỉ định không tồn tại: $real_cli${NC}" >&2
            return 1
        fi
        printf '%s\n' "$real_cli"
        return 0
    fi

    # ── Priority 2: Explicit Environment Variables ──────────────────────
    local env_val=""
    if [ -n "${COMFY_BASE:-}" ]; then
        env_val="$COMFY_BASE"
    elif [ -n "${COMFYUI_DIR:-}" ]; then
        env_val="$COMFYUI_DIR"
    elif [ -n "${COMFY_DIR:-}" ]; then
        env_val="$COMFY_DIR"
    elif [ -n "${COMFYUI_PATH:-}" ]; then
        env_val="$COMFYUI_PATH"
    fi

    if [ -n "$env_val" ]; then
        local real_env
        real_env=$(readlink -f "$env_val" 2>/dev/null || echo "$env_val")
        if ! validate_safe_path "$real_env" 2>/dev/null; then
            echo -e "${RED}❌ Đường dẫn biến môi trường không an toàn hoặc không hợp lệ: $env_val${NC}" >&2
            return 1
        fi
        if [ "$allow_fresh" -eq 0 ] && [ ! -d "$real_env" ]; then
            echo -e "${RED}❌ Thư mục ComfyUI từ biến môi trường không tồn tại: $real_env${NC}" >&2
            return 1
        fi
        printf '%s\n' "$real_env"
        return 0
    fi

    echo -e "${CYAN}🔎 Detecting ComfyUI...${NC}" >&2

    # ── Priority 3: Active Running ComfyUI Process ───────────────────────
    local active_dirs=()
    while IFS= read -r adir; do
        [ -n "$adir" ] && is_valid_comfyui_dir "$adir" && active_dirs+=("$adir")
    done < <(detect_running_comfyui 2>/dev/null)

    # ── Priority 4 & 5: Known Paths & Bounded Filesystem Discovery ────────
    local discovered_dirs=()
    while IFS= read -r ddir; do
        [ -n "$ddir" ] && is_valid_comfyui_dir "$ddir" && discovered_dirs+=("$ddir")
    done < <(discover_comfyui_candidates 2>/dev/null)

    # Merge active dirs and discovered dirs (deduplicated)
    local all_candidates=()
    for d in "${active_dirs[@]}" "${discovered_dirs[@]}"; do
        local already=0
        for c in "${all_candidates[@]}"; do
            [ "$c" = "$d" ] && { already=1; break; }
        done
        [ $already -eq 0 ] && all_candidates+=("$d")
    done

    # ── Case A: Exactly 1 Active running ComfyUI process ─────────────────
    if [ ${#active_dirs[@]} -eq 1 ]; then
        local chosen="${active_dirs[0]}"
        echo -e "${GREEN}✅ Found active running ComfyUI:${NC} $chosen" >&2
        printf '%s\n' "$chosen"
        return 0
    fi

    # ── Case B: Exactly 1 valid candidate discovered ─────────────────────
    if [ ${#all_candidates[@]} -eq 1 ]; then
        local chosen="${all_candidates[0]}"
        echo -e "${GREEN}✅ Found existing ComfyUI:${NC} $chosen" >&2
        printf '%s\n' "$chosen"
        return 0
    fi

    # ── Case C: Multiple valid candidates found (Ambiguity Protection) ───
    if [ ${#all_candidates[@]} -gt 1 ]; then
        echo -e "\n${RED}════════════════════════════════════════════════════════════════${NC}" >&2
        echo -e "${RED}❌ MULTIPLE COMFYUI INSTALLATIONS FOUND (${#all_candidates[@]} installations)${NC}" >&2
        echo -e "${RED}════════════════════════════════════════════════════════════════${NC}" >&2
        echo -e "${YELLOW}Hệ thống phát hiện nhiều thư mục cài đặt ComfyUI hợp lệ:${NC}" >&2
        local idx=1
        for cand in "${all_candidates[@]}"; do
            echo -e "  ${CYAN}$idx.${NC} $cand" >&2
            idx=$((idx + 1))
        done
        echo -e "\n${YELLOW}👉 Để đảm bảo an toàn, vui lòng chỉ định chính xác thư mục cần dùng:${NC}" >&2
        echo -e "   ${GREEN}bash <script>.sh --comfy-dir /path/to/ComfyUI${NC}" >&2
        echo -e "hoặc thiết lập biến môi trường:" >&2
        echo -e "   ${GREEN}export COMFY_BASE=/path/to/ComfyUI${NC}\n" >&2
        return 1
    fi

    # ── Case D: Zero candidates found (0) ─────────────────────────────────
    if [ "$allow_fresh" -eq 0 ]; then
        echo -e "${RED}❌ Existing ComfyUI installation not found. Nothing was created.${NC}" >&2
        return 1
    fi

    echo -e "${YELLOW}💡 EXISTING COMFYUI NOT FOUND${NC}" >&2

    local default_target=""
    if [ -d "/workspace" ] && [ -w "/workspace" ]; then
        default_target="/workspace/ComfyUI"
    elif [ -d "/app" ] && [ -w "/app" ]; then
        default_target="/app/ComfyUI"
    elif [ -d "/content" ] && [ -w "/content" ]; then
        default_target="/content/ComfyUI"
    else
        default_target="$HOME/ComfyUI"
    fi

    default_target=$(readlink -f "$default_target" 2>/dev/null || echo "$default_target")
    echo -e "📦 Fresh installation will be used: ${GREEN}YES${NC} (Target: $default_target)" >&2
    printf '%s\n' "$default_target"
    return 0
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

    if [ "$tool" = "jq" ] && command -v pip3 &>/dev/null; then
        pip3 install --quiet jq 2>/dev/null || true
    fi

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
    local policy="${1:-allow-fresh}"
    export LC_ALL=C
    local allow_f=1
    [ "$policy" = "require-existing" ] && allow_f=0

    local resolved_base
    if ! resolved_base="$(resolve_comfy_base "${COMFY_BASE:-}" "$allow_f")"; then
        return 1
    fi
    COMFY_BASE="$resolved_base"
    MODELS="$COMFY_BASE/models"
    CUSTOM_NODES="$COMFY_BASE/custom_nodes"
    export COMFY_BASE MODELS CUSTOM_NODES REQUIRED_SPACE_GB DISABLE_SSL_VERIFY DRY_RUN UPDATE_EXISTING

    if [ "$DISABLE_SSL_VERIFY" = "1" ]; then
        WGET_SSL_OPT="--no-check-certificate"
        CURL_SSL_OPT="-k"
        ARIA2_SSL_OPT="--check-certificate=false"
        PIP_SSL_OPT="--trusted-host pypi.org --trusted-host files.pythonhosted.org --trusted-host download.pytorch.org"
        GIT_SSL_ENV="GIT_SSL_NO_VERIFY=true"
    fi

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

    [ -z "${LOG_FILE:-}" ] && LOG_FILE="$COMFY_BASE/setup_log.txt"
    [ -z "${FAILED_LOG_FILE:-}" ] && FAILED_LOG_FILE="$COMFY_BASE/failed_downloads.log"
    [ -z "${MANIFEST_FILE:-}" ] && MANIFEST_FILE="$COMFY_BASE/manifest.json"
    [ -z "${REPORT_FILE:-}" ] && REPORT_FILE="$COMFY_BASE/SETUP_REPORT.md"
    [ -z "${REPORT_JSON:-}" ] && REPORT_JSON="$COMFY_BASE/setup_report.json"

    export LOG_FILE FAILED_LOG_FILE MANIFEST_FILE REPORT_FILE REPORT_JSON
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
    avail_space_gb=$(df -P -BG "$COMFY_BASE" 2>/dev/null | awk 'NR==2 {print $4}' | tr -dc '0-9')
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

# Standalone Python model file validator with strict structural integrity and authoritative SHA256 enforcement
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
    if file_size == 0:
        print("0")
        sys.exit(0)

    with open(filepath, 'rb') as f:
        head = f.read(4096)

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

    is_safetensors = filepath.endswith('.safetensors') or filepath.endswith('.safetensors.part')

    # 1. Safetensors validation: uint64 header size + JSON parse + Tensor Offset Body Boundary Check
    if is_safetensors or (len(head) >= 8 and not head.startswith(b'PK') and not head.startswith(b'GGUF') and not head.startswith(b'\x80')):
        header_len = int.from_bytes(head[:8], 'little')
        if 0 < header_len < 100000000 and (8 + header_len) <= file_size:
            with open(filepath, 'rb') as f:
                f.seek(8)
                json_bytes = f.read(header_len)
                try:
                    meta = json.loads(json_bytes.decode('utf-8'))
                    if isinstance(meta, dict) and len(meta) > 0:
                        body_start = 8 + header_len
                        has_tensors = False
                        offset_ranges = []
                        valid = True
                        for k, v in meta.items():
                            if k == '__metadata__':
                                continue
                            if not isinstance(v, dict):
                                valid = False
                                break
                            if 'dtype' not in v or not isinstance(v['dtype'], str):
                                valid = False
                                break
                            if 'shape' not in v or not isinstance(v['shape'], list) or not all(isinstance(x, int) and x >= 0 for x in v['shape']):
                                valid = False
                                break
                            if 'data_offsets' not in v or not isinstance(v['data_offsets'], list) or len(v['data_offsets']) != 2:
                                valid = False
                                break
                            start_off, end_off = v['data_offsets']
                            if not isinstance(start_off, int) or not isinstance(end_off, int):
                                valid = False
                                break
                            if not (0 <= start_off <= end_off):
                                valid = False
                                break
                            if (body_start + end_off) > file_size:
                                valid = False
                                break
                            offset_ranges.append((start_off, end_off))
                            has_tensors = True

                        if not valid or not has_tensors:
                            print("0")
                            sys.exit(0)

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

    # 2. GGUF format validation (.gguf)
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

    # 3. PyTorch Zip / Pickle / .pth / .pt / Generic binary REQUIRE AUTHORITATIVE SHA256
    if expected_sha:
        h = hashlib.sha256()
        with open(filepath, 'rb') as vf:
            while chunk := vf.read(1048576):
                h.update(chunk)
        if h.hexdigest().lower() == expected_sha:
            print("1")
            sys.exit(0)
        else:
            print("0")
            sys.exit(0)

    # All other binaries without authoritative expected_sha are REJECTED
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

# Update source health score with auto-expiring flock and zero credential persistence
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

lock_file = health_file + '.lock'
os.makedirs(os.path.dirname(health_file), exist_ok=True)

# Auto-clean stale locks older than 10 seconds
if os.path.exists(lock_file):
    try:
        if time.time() - os.path.getmtime(lock_file) > 10:
            os.remove(lock_file)
    except Exception:
        pass

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

            entry = data.get(hostname, {'success': 0, 'fails': 0, 'health_score': 100})

            if status == 'ok':
                entry['success'] = entry.get('success', 0) + 1
                entry['health_score'] = min(100, entry.get('health_score', 100) + 5)
            elif status == '404':
                entry['fails'] = entry.get('fails', 0) + 1
                entry['health_score'] = max(0, entry.get('health_score', 100) - 40)
            elif status == '429':
                entry['fails'] = entry.get('fails', 0) + 1
                entry['health_score'] = max(0, entry.get('health_score', 100) - 15)
            else:
                entry['fails'] = entry.get('fails', 0) + 1
                entry['health_score'] = max(0, entry.get('health_score', 100) - 20)

            entry['last_status'] = status
            entry['updated_at'] = int(time.time())
            data[hostname] = entry

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

# Cross-source .part contamination prevention via sidecar metadata (Zero Secret Storage)
manage_part_metadata() {
    local url="$1"
    local part_file="$2"
    local expected_sha256="${3:-}"
    local action="${4:-check}"
    local meta_file="${part_file}.meta.json"

    python3 - "$url" "$part_file" "$expected_sha256" "$action" "$meta_file" <<'PY_PART_META'
import sys, os, json, time, re, shutil, urllib.parse, hashlib

url, part_file, expected_sha, action, meta_file = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]

def get_source_id(u):
    try:
        parsed = urllib.parse.urlparse(u)
        qs = [q for q in urllib.parse.parse_qsl(parsed.query, keep_blank_values=True) if q[0].lower() not in ('token', 'api_key', 'apikey', 'key', 'auth', 'secret', 'signature', 'authorization')]
        canonical = urllib.parse.urlunparse((parsed.scheme.lower(), parsed.netloc.lower(), parsed.path, parsed.params, urllib.parse.urlencode(sorted(qs)), ""))
        return hashlib.sha256(canonical.encode('utf-8')).hexdigest()
    except Exception:
        return hashlib.sha256(u.encode('utf-8')).hexdigest()

current_source_id = get_source_id(url)
redacted_url = re.sub(r'([?&](token|api_key|apikey|key|authorization|access_token|auth|secret|signature)=)[^&]+', r'\1***', url)

if action == 'check':
    if os.path.exists(part_file) and os.path.exists(meta_file):
        try:
            with open(meta_file, 'r') as f:
                meta = json.load(f)
            saved_sid = meta.get('source_id', '')
            saved_sha = meta.get('expected_sha256', '')

            # Match source_id OR verified expected_sha256
            if (saved_sid and saved_sid == current_source_id) or (expected_sha and saved_sha and saved_sha.lower() == expected_sha.lower()):
                print("RESUME_OK")
                sys.exit(0)
            else:
                # Quarantine foreign part and clean aria2 control files
                timestamp = int(time.time())
                q_dir = os.path.join(os.path.dirname(part_file), "preserve_quarantine")
                os.makedirs(q_dir, exist_ok=True)
                q_part = os.path.join(q_dir, f"quarantine_{timestamp}_{os.path.basename(part_file)}")
                try:
                    shutil.move(part_file, q_part)
                except Exception:
                    pass
                aria2_file = f"{part_file}.aria2"
                if os.path.exists(aria2_file):
                    try: os.remove(aria2_file)
                    except Exception: pass
                print("RESET_DIFFERENT_SOURCE")
        except Exception:
            print("RESET_CORRUPT_META")
    else:
        print("FRESH_START")

    try:
        os.makedirs(os.path.dirname(meta_file), exist_ok=True)
        with open(meta_file, 'w') as f:
            json.dump({
                'source_id': current_source_id,
                'source_url': redacted_url,
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
    local max_retries="${MAX_RETRIES:-3}"
    local timeout="${TIMEOUT:-60}"

    mkdir -p "$(dirname "$part_file")"

    # Check and guard .part sidecar metadata against cross-source contamination
    local part_status
    part_status=$(manage_part_metadata "$url" "$part_file" "$expected_sha256" "check")
    if [ "$part_status" = "RESET_DIFFERENT_SOURCE" ]; then
        echo -e "   ${YELLOW}⚠️  Phát hiện file .part từ nguồn khác - Đã cách ly an toàn vào preserve_quarantine/${NC}"
    fi

    local connections=4
    local split=4

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

if dis_ssl == "1":
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
else:
    ctx = ssl.create_default_context()

req = urllib.request.Request(url, headers={'User-Agent': ua})

mode = 'wb'
cur_size = 0
if os.path.exists(out):
    cur_size = os.path.getsize(out)
    if cur_size > 0:
        req.add_header('Range', f'bytes={cur_size}-')
        mode = 'ab'

with urllib.request.urlopen(req, context=ctx, timeout=timeout) as resp:
    # Verify Content-Range header if resuming (status 206)
    if resp.status == 206 and mode == 'ab':
        cr = resp.headers.get('Content-Range', '')
        if not cr.startswith(f'bytes {cur_size}-'):
            # Range mismatch -> reset to fresh download
            mode = 'wb'
    elif resp.status == 200:
        mode = 'wb'

    with open(out, mode) as f:
        while True:
            chunk = resp.read(4 * 1024 * 1024)
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

# Liveness probe using bounded HEAD or Range: bytes=0-0 (Never unrestricted GET)
check_url_alive() {
    local url="$1"
    local user_agent="${USER_AGENT:-Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36}"
    local http_code=0

    if command -v curl &>/dev/null; then
        # 1. Try lightweight HEAD probe
        http_code=$(curl -s -o /dev/null -w "%{http_code}" \
            --max-time 10 --connect-timeout 8 \
            -L -I \
            ${CURL_SSL_OPT} \
            -A "$user_agent" \
            "$url" 2>/dev/null || echo "0")

        # 2. If server returns 405 (Method Not Allowed) or fails HEAD, fallback to Range 0-0 probe
        if [ "$http_code" = "405" ] || [ "$http_code" = "0" ] || [ "$http_code" = "400" ]; then
            http_code=$(curl -s -o /dev/null -w "%{http_code}" \
                --max-time 10 --connect-timeout 8 \
                -L -r 0-0 \
                ${CURL_SSL_OPT} \
                -A "$user_agent" \
                "$url" 2>/dev/null || echo "0")
        fi
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
        IFS='|' read -ra ALT_ARR <<< "$explicit_alts"
        for alt in "${ALT_ARR[@]}"; do
            alt="$(echo -n "$alt" | xargs)"
            if [ -n "$alt" ]; then
                mirrors+=("$alt")
            fi
        done
    fi

    if [[ "$primary_url" == *"huggingface.co"* ]] && [[ "$primary_url" != *"hf-mirror.com"* ]]; then
        local mirror_hf="${primary_url/huggingface.co/hf-mirror.com}"
        mirrors+=("$mirror_hf")
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
            size_h=$(du -sh "$output_path" 2>/dev/null | cut -f1 || echo "OK")
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
    local candidate_urls=()
    local p_trust
    p_trust=$(classify_source_trust "$primary_url")
    if [ "$p_trust" = "THIRD_PARTY_MIRROR" ] && [ -z "$expected_sha256" ]; then
        echo -e "   ${YELLOW}⚠️  Bỏ qua nguồn chính do là mirror bên thứ ba nhưng thiếu SHA256:${NC} $(redact_url "$primary_url")"
    else
        candidate_urls+=("$primary_url")
    fi

    mapfile -t mirrors < <(generate_mirror_urls "$primary_url" "$explicit_alts")
    for m in "${mirrors[@]}"; do
        [ -z "$m" ] && continue
        [ "$m" = "$primary_url" ] && continue
        if validate_url "$m" 2>/dev/null; then
            local m_trust
            m_trust=$(classify_source_trust "$m")
            if [ "$m_trust" = "THIRD_PARTY_MIRROR" ] && [ -z "$expected_sha256" ]; then
                echo -e "   ${YELLOW}⚠️  Bỏ qua mirror bên thứ ba (không có SHA256):${NC} $(redact_url "$m")"
            else
                candidate_urls+=("$m")
            fi
        fi
    done

    if [ ${#candidate_urls[@]} -eq 0 ]; then
        echo -e "   ${RED}❌ Không có URL nguồn hợp lệ để tải: $description${NC}"
        log_event "FAIL" "$description | No valid sources remaining"
        FAILED_FILES+=("$description|$output_path|$(redact_url "$primary_url")|Không có nguồn hợp lệ")
        return 1
    fi

    local part_file="${output_path}.part"
    local download_success=0
    local used_url=""
    local is_mirror=0
    local attempt_count=0

    for url in "${candidate_urls[@]}"; do
        attempt_count=$((attempt_count + 1))
        local display_url
        display_url=$(redact_url "$url")

        if [ $attempt_count -eq 1 ] && [ "$url" = "$primary_url" ]; then
            echo -e "   ${BLUE}🌐 Link chính gốc:${NC} $display_url"
        else
            local alt_idx=$((attempt_count - 1))
            echo -e "   ${YELLOW}🔄 Link phụ dự phòng #${alt_idx}:${NC} $display_url"
            is_mirror=1
        fi

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
                echo -e "   ${RED}⚠️  File tạm không vượt qua kiểm tra integrity. Thử nguồn khác...${NC}"
                rm -f "$part_file" "${part_file}.meta.json" "${part_file}.aria2"
            fi
        fi
    done

    if [ $download_success -eq 1 ] && [ -f "$part_file" ]; then
        mv "$part_file" "$output_path"
        rm -f "${part_file}.meta.json" "${part_file}.aria2"
        local size_h
        size_h=$(du -sh "$output_path" 2>/dev/null | cut -f1 || echo "OK")
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
        rm -f "$part_file" "${part_file}.meta.json" "${part_file}.aria2"
        return 1
    fi
}

# Clone or pull git repositories safely (No unverified third-party proxy for executable code)
clone_or_pull() {
    local repo_url="$1"
    local target_dir="$2"
    local description="$3"

    if ! validate_safe_path "$target_dir" 2>/dev/null; then
        echo -e "   ${RED}❌ Đường dẫn clone/pull không an toàn: '$target_dir'${NC}"
        return 1
    fi
    if [ -n "${CUSTOM_NODES:-}" ] && [ "$target_dir" != "${COMFY_BASE:-}" ] && ! validate_node_destination "$target_dir" "$CUSTOM_NODES" 2>/dev/null; then
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
        if [ "${UPDATE_EXISTING:-0}" = "1" ]; then
            echo -e "   ${YELLOW}🔄 Cập nhật repo (git pull):${NC} $description"
            (cd "$target_dir" && env ${GIT_SSL_ENV:-} git pull --rebase --quiet) || echo -e "   ${YELLOW}⚠️ Git pull có cảnh báo${NC}"
            log_event "PULL" "$description | $target_dir"
        else
            echo -e "   ${GREEN}✅ Đã có sẵn repo (giữ nguyên):${NC} $description"
        fi
        return 0
    elif [ -d "$target_dir" ]; then
        echo -e "   ${GREEN}✅ Đã có sẵn thư mục:${NC} $description"
        return 0
    fi

    echo -e "   ${BLUE}📦 Clone mới:${NC} $description"

    local clone_ok=0
    for attempt in 1 2 3; do
        if env ${GIT_SSL_ENV:-} git clone --quiet --depth 1 "$repo_url" "$target_dir" 2>/dev/null; then
            clone_ok=1
            break
        else
            sleep $((attempt * 2))
        fi
    done

    if [ $clone_ok -eq 1 ]; then
        echo -e "   ${GREEN}✅ Clone thành công${NC}"
        log_event "CLONE_OK" "$description | $target_dir"
        return 0
    else
        echo -e "   ${RED}❌ Clone thất bại từ GitHub.${NC}"
        log_event "CLONE_FAIL" "$description | $target_dir"
        FAILED_FILES+=("$description|$target_dir|$(redact_url "$repo_url")|Git Clone Lỗi")
        return 1
    fi
}

install_requirements() {
    local dir="$1"
    if [ -f "$dir/requirements.txt" ]; then
        echo -e "   ${CYAN}📥 Cài dependencies cho $(basename "$dir")${NC}"

        if [ "${DRY_RUN:-0}" = "1" ]; then
            log_event "DRY_PIP_OK" "$(basename "$dir")"
            return 0
        fi

        if $PIP_BASE_CMD install -r "$dir/requirements.txt" $PIP_SSL_OPT --break-system-packages >> "$COMFY_BASE/pip_install.log" 2>&1 \
            || $PIP_BASE_CMD install -r "$dir/requirements.txt" $PIP_SSL_OPT >> "$COMFY_BASE/pip_install.log" 2>&1; then
            return 0
        else
            echo -e "   ${RED}❌ Lỗi khi cài đặt requirements cho $(basename "$dir")${NC}"
            return 1
        fi
    fi
    return 0
}

export -f is_valid_comfyui_dir detect_running_comfyui discover_comfyui_candidates redact_url canonical_source_id resolve_config_value prepare_civitai_credentials consolidate_comfy_dirs resolve_comfy_base ensure_tool_installed init_runtime_env log_event check_disk_space verify_model_file_internal verify_model_file update_source_health manage_part_metadata exec_download_tool check_url_alive generate_mirror_urls download_model_smart clone_or_pull install_requirements 2>/dev/null || true
