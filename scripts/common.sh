#!/bin/bash

if [[ -n "${COMFY_SETUP_COMMON_SOURCED:-}" ]]; then
    return 0
fi
COMFY_SETUP_COMMON_SOURCED=1

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

# Default global configurations
REQUIRED_SPACE_GB=100
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

# Format config strings
resolve_config_value() {
    local value="$1"
    value="${value//\$COMFY_BASE/$COMFY_BASE}"
    value="${value//\$MODELS/$MODELS}"
    value="${value//\$CUSTOM_NODES/$CUSTOM_NODES}"
    value="${value//\$ENCODED_TOKEN/${ENCODED_TOKEN:-}}"
    printf '%s' "$value"
}

# Auto-detect ComfyUI path across Cloud Servers & Local Machines
resolve_comfy_base() {
    local candidate_cli="${1:-}"
    
    # Priority list of possible paths
    local candidates=()
    [ -n "$candidate_cli" ] && candidates+=("$candidate_cli")
    [ -n "${COMFY_BASE:-}" ] && candidates+=("$COMFY_BASE")
    [ -n "${COMFYUI_PATH:-}" ] && candidates+=("$COMFYUI_PATH")
    
    # Common Cloud & Server Environments
    candidates+=(
        "/app/ComfyUI"
        "/app/comfyUI"
        "/content/drive/MyDrive/ComfyUI"
        "/content/ComfyUI"
        "/workspace/ComfyUI"
        "/workspace/comfyui"
        "/kaggle/working/ComfyUI"
        "/opt/ml/code/ComfyUI"
        "$HOME/ComfyUI"
        "$HOME/comfyui"
        "$HOME/Desktop/ComfyUI"
        "$PWD/ComfyUI"
        "$PWD"
    )

    # 1st PASS: Search for existing ComfyUI installations (containing main.py or folder_paths.py)
    for path in "${candidates[@]}"; do
        [ -z "$path" ] && continue
        if [ -d "$path" ] && { [ -f "$path/main.py" ] || [ -f "$path/folder_paths.py" ] || [ -f "$path/nodes.py" ]; }; then
            echo -e "${GREEN}🔍 Phát hiện thư mục ComfyUI hiện có tại:${NC} $path" >&2
            printf '%s\n' "$path"
            return 0
        fi
    done

    # 2nd PASS: Use the first existing & writable directory
    for path in "${candidates[@]}"; do
        [ -z "$path" ] && continue
        if mkdir -p "$path" 2>/dev/null; then
            echo -e "${YELLOW}📁 Tạo/Sử dụng thư mục ComfyUI tại:${NC} $path" >&2
            printf '%s\n' "$path"
            return 0
        fi
    done

    # Fallback to home or current workspace
    local fallback="$HOME/ComfyUI"
    mkdir -p "$fallback" 2>/dev/null || fallback="$PWD/comfyui-output"
    mkdir -p "$fallback" 2>/dev/null || true
    echo -e "${YELLOW}📁 Sử dụng thư mục mặc định:${NC} $fallback" >&2
    printf '%s\n' "$fallback"
}

# Auto-install missing tools dynamically (apt / static binary download)
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
        git config --global http.sslVerify false 2>/dev/null || true
    fi

    if command -v pip3 &>/dev/null; then
        PIP_BASE_CMD="pip3"
    else
        PIP_BASE_CMD="python3 -m pip"
    fi

    if ! command -v python3 &>/dev/null; then
        echo -e "${RED}❌ Python3 không tìm thấy trên hệ thống.${NC}"
        return 1
    fi

    PYTHON_CMD="python3"
    mkdir -p "$COMFY_BASE" "$MODELS" "$CUSTOM_NODES"
    
    if [ -z "$LOG_FILE" ]; then
        LOG_FILE="$COMFY_BASE/setup_log.txt"
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
    local message="$2"
    if [ -n "${LOG_FILE:-}" ]; then
        mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
        echo "$(date '+%Y-%m-%d %H:%M:%S') | $level | $message" >> "$LOG_FILE"
    fi
}

check_disk_space() {
    local avail_space_gb
    avail_space_gb=$(df -BG "$COMFY_BASE" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ -z "$avail_space_gb" ]; then
        echo -e "${YELLOW}⚠️  Không thể kiểm tra dung lượng ổ đĩa.${NC}"
        return 0
    elif [ "$avail_space_gb" -lt "$REQUIRED_SPACE_GB" ]; then
        echo -e "${RED}⚠️  Dung lượng trống: ${avail_space_gb}GB, khuyến nghị ít nhất ${REQUIRED_SPACE_GB}GB.${NC}"
    else
        echo -e "${GREEN}✅ Dung lượng trống: ${avail_space_gb}GB${NC}"
    fi
}

# Generate fallback mirror URLs dynamically based on primary link platform
generate_mirror_urls() {
    local primary_url="$1"
    local explicit_alts="${2:-}"
    local mirrors=()

    # Add explicit alternative links first if provided
    if [ -n "$explicit_alts" ]; then
        IFS=',' read -ra ALT_ARR <<< "$explicit_alts"
        for alt in "${ALT_ARR[@]}"; do
            alt="$(echo -n "$alt" | xargs)"
            [ -n "$alt" ] && mirrors+=("$alt")
        done
    fi

    # Auto-generate dynamic mirrors
    if [[ "$primary_url" == *"civitai.com"* ]]; then
        local red_url="${primary_url/civitai.com/civitai.red}"
        mirrors+=("$red_url")
    elif [[ "$primary_url" == *"civitai.red"* ]]; then
        local com_url="${primary_url/civitai.red/civitai.com}"
        mirrors+=("$com_url")
    elif [[ "$primary_url" == *"huggingface.co"* ]]; then
        local mirror_hf="${primary_url/huggingface.co/hf-mirror.com}"
        local short_hf="${primary_url/huggingface.co/hf.co}"
        mirrors+=("$mirror_hf" "$short_hf")
    elif [[ "$primary_url" == *"github.com"* ]]; then
        local gh_proxy1="https://ghproxy.net/$primary_url"
        local gh_proxy2="https://gh-proxy.com/$primary_url"
        mirrors+=("$gh_proxy1" "$gh_proxy2")
    fi

    printf "%s\n" "${mirrors[@]}"
}

# Single URL downloader supporting aria2c -> wget -> curl -> python
exec_download_tool() {
    local url="$1"
    local temp_file="$2"

    if command -v aria2c &>/dev/null; then
        echo -e "   ${BLUE}⚡ Tải qua aria2c...${NC}"
        if aria2c $ARIA2_SSL_OPT \
               --max-connection-per-server=4 \
               --split=4 \
               --console-log-level=error \
               --summary-interval=0 \
               --timeout=20 \
               --max-tries=3 \
               --retry-wait=2 \
               --continue=true \
               --dir="$(dirname "$temp_file")" \
               --out="$(basename "$temp_file")" \
               "$url" >/dev/null 2>&1; then
            if [ -f "$temp_file" ] && [ "$(stat -c%s "$temp_file" 2>/dev/null || stat -f%z "$temp_file" 2>/dev/null || echo 0)" -gt 1048576 ]; then
                return 0
            fi
        fi
    fi

    if command -v wget &>/dev/null; then
        echo -e "   ${BLUE}🐢 Tải qua wget...${NC}"
        if wget -c $WGET_SSL_OPT --tries=3 --waitretry=2 --timeout=20 -q --show-progress -O "$temp_file" "$url"; then
            if [ -f "$temp_file" ] && [ "$(stat -c%s "$temp_file" 2>/dev/null || stat -f%z "$temp_file" 2>/dev/null || echo 0)" -gt 1048576 ]; then
                return 0
            fi
        fi
    fi

    if command -v curl &>/dev/null; then
        echo -e "   ${BLUE}🔄 Tải qua curl...${NC}"
        if curl -L -C - $CURL_SSL_OPT --retry 2 --retry-delay 2 --connect-timeout 20 -o "$temp_file" "$url" >/dev/null 2>&1; then
            if [ -f "$temp_file" ] && [ "$(stat -c%s "$temp_file" 2>/dev/null || stat -f%z "$temp_file" 2>/dev/null || echo 0)" -gt 1048576 ]; then
                return 0
            fi
        fi
    fi

    if command -v python3 &>/dev/null; then
        echo -e "   ${BLUE}🐍 Tải qua Python urllib...${NC}"
        if $PYTHON_CMD - "$url" "$temp_file" <<'PY' >/dev/null 2>&1
import sys, urllib.request, ssl
url, out = sys.argv[1], sys.argv[2]
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
with urllib.request.urlopen(req, context=ctx, timeout=30) as resp, open(out, 'wb') as f:
    f.write(resp.read())
PY
        then
            if [ -f "$temp_file" ] && [ "$(stat -c%s "$temp_file" 2>/dev/null || stat -f%z "$temp_file" 2>/dev/null || echo 0)" -gt 1048576 ]; then
                return 0
            fi
        fi
    fi

    return 1
}

# Smart Model Downloader with multi-source fallback mirror engine
download_model_smart() {
    local primary_url="$1"
    local explicit_alts="$2"
    local output_path="$3"
    local description="$4"
    local expected_sha256="${5:-}"

    local dir_name
    dir_name=$(dirname "$output_path")
    mkdir -p "$dir_name"

    echo -e "\n${CYAN}⬇️  [${CURRENT}/${TOTAL}] Tải:${NC} $description"
    echo -e "   ${YELLOW}Lưu tại:${NC} $output_path"

    # Check if already downloaded and valid (>1MB)
    if [ -f "$output_path" ]; then
        local size
        size=$(stat -c%s "$output_path" 2>/dev/null || stat -f%z "$output_path" 2>/dev/null || echo 0)
        if [ "$size" -gt 1048576 ]; then
            local size_h
            size_h=$(du -sh "$output_path" | cut -f1)
            echo -e "   ${GREEN}⏩ Đã tồn tại (${size_h}), bỏ qua.${NC}"
            log_event "SKIP" "$description | $output_path | $size_h"
            return 0
        else
            echo -e "   ${YELLOW}⚠️  File quá nhỏ (<1MB), sẽ tiến hành tải lại.${NC}"
            rm -f "$output_path"
        fi
    fi

    # Dry run handling
    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo -e "   ${GREEN}🧪 [DRY_RUN] Giả lập OK:${NC} $primary_url"
        log_event "OK_PRIMARY" "$description | $output_path | $primary_url | DRY_RUN"
        return 0
    fi

    # Construct list of candidate URLs: Primary -> Alt Mirror URLs
    local candidate_urls=("$primary_url")
    mapfile -t mirrors < <(generate_mirror_urls "$primary_url" "$explicit_alts")
    for m in "${mirrors[@]}"; do
        [ -n "$m" ] && [ "$m" != "$primary_url" ] && candidate_urls+=("$m")
    done

    local temp_file="${output_path}.tmp"
    local download_success=0
    local used_url=""
    local is_mirror=0
    local attempt_count=0

    for url in "${candidate_urls[@]}"; do
        attempt_count=$((attempt_count + 1))
        if [ $attempt_count -eq 1 ]; then
            echo -e "   ${BLUE}🌐 Nguồn chính:${NC} $url"
        else
            echo -e "   ${YELLOW}🔄 Nguồn dự phòng (Link phụ #${attempt_count-1}):${NC} $url"
            is_mirror=1
        fi

        rm -f "$temp_file"
        if exec_download_tool "$url" "$temp_file"; then
            if [ -f "$temp_file" ]; then
                local fsize
                fsize=$(stat -c%s "$temp_file" 2>/dev/null || stat -f%z "$temp_file" 2>/dev/null || echo 0)
                if [ "$fsize" -gt 1048576 ]; then
                    # Check Hash if sha256 specified
                    if [ -n "$expected_sha256" ] && command -v sha256sum &>/dev/null; then
                        local actual_sha
                        actual_sha=$(sha256sum "$temp_file" 2>/dev/null | awk '{print $1}')
                        if [ "$actual_sha" != "$expected_sha256" ]; then
                            echo -e "   ${RED}❌ Sai SHA256 checksum! Thử nguồn khác...${NC}"
                            rm -f "$temp_file"
                            continue
                        fi
                    fi
                    
                    download_success=1
                    used_url="$url"
                    break
                else
                    echo -e "   ${RED}⚠️  File nhận được nhỏ hơn 1MB (có thể lỗi HTML/Redirect). Thử nguồn khác...${NC}"
                    rm -f "$temp_file"
                fi
            fi
        fi
    done

    if [ $download_success -eq 1 ] && [ -f "$temp_file" ]; then
        mv "$temp_file" "$output_path"
        local size_h
        size_h=$(du -sh "$output_path" | cut -f1)

        if [ $is_mirror -eq 1 ]; then
            echo -e "   ${MAGENTA}✨ TẢI THÀNH CÔNG TỪ LINK PHỤ (${size_h})${NC}"
            log_event "OK_MIRROR" "$description | $output_path | $used_url | $size_h"
            MIRROR_FILES+=("$description|$output_path|$primary_url|$used_url|$size_h")
        else
            echo -e "   ${GREEN}✅ Thành công (${size_h})${NC}"
            log_event "OK_PRIMARY" "$description | $output_path | $size_h"
        fi
        return 0
    else
        echo -e "   ${RED}❌ TẢI THẤT BẠI TẤT CẢ NGUỒN (Link chính + Link phụ).${NC}"
        log_event "FAIL" "$description | $output_path | $primary_url"
        FAILED_FILES+=("$description|$output_path|$primary_url|Tất cả mirror đều lỗi/không phản hồi")
        rm -f "$temp_file"
        return 1
    fi
}

# Clone or pull git repositories with mirror fallback capability
clone_or_pull() {
    local repo_url="$1"
    local target_dir="$2"
    local description="$3"

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
            MIRROR_FILES+=("$description|$target_dir|$repo_url|$mirror_git|Git Repo")
            return 0
        fi
    fi

    echo -e "   ${RED}❌ Clone thất bại hoàn toàn.${NC}"
    log_event "CLONE_FAIL" "$description | $target_dir"
    FAILED_FILES+=("$description|$target_dir|$repo_url|Git Clone Lỗi")
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
