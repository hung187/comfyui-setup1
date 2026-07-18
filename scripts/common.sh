#!/bin/bash

if [[ -n "${COMFY_SETUP_COMMON_SOURCED:-}" ]]; then
    return 0
fi
COMFY_SETUP_COMMON_SOURCED=1

set +e
export LC_ALL=C

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

COMFY_BASE="${COMFY_BASE:-/content/drive/MyDrive/ComfyUI}"
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
CURRENT=0
TOTAL=0
declare -a MODEL_LIST=()

resolve_config_value() {
    local value="$1"
    value="${value//\$COMFY_BASE/$COMFY_BASE}"
    value="${value//\$MODELS/$MODELS}"
    value="${value//\$CUSTOM_NODES/$CUSTOM_NODES}"
    value="${value//\$ENCODED_TOKEN/$ENCODED_TOKEN}"
    printf '%s' "$value"
}

resolve_comfy_base() {
    local candidate="$1"
    if [ -n "$candidate" ] && mkdir -p "$candidate" 2>/dev/null; then
        printf '%s\n' "$candidate"
        return 0
    fi

    local fallback="$HOME/ComfyUI"
    if mkdir -p "$fallback" 2>/dev/null; then
        printf '%s\n' "$fallback"
        return 0
    fi

    local workspace_fallback="$PWD/comfyui-output"
    mkdir -p "$workspace_fallback" 2>/dev/null || true
    printf '%s\n' "$workspace_fallback"
}

init_runtime_env() {
    export LC_ALL=C
    COMFY_BASE="$(resolve_comfy_base "$COMFY_BASE")"
    MODELS="$COMFY_BASE/models"
    CUSTOM_NODES="$COMFY_BASE/custom_nodes"
    export COMFY_BASE MODELS CUSTOM_NODES REQUIRED_SPACE_GB DISABLE_SSL_VERIFY DRY_RUN
    export WGET_SSL_OPT CURL_SSL_OPT ARIA2_SSL_OPT PIP_SSL_OPT GIT_SSL_ENV PIP_BASE_CMD PYTHON_CMD LOG_FILE MANIFEST_FILE CURRENT TOTAL

    if [ "$DISABLE_SSL_VERIFY" = "1" ]; then
        echo -e "${YELLOW}⚠️  Đã TẮT xác minh SSL theo yêu cầu (DISABLE_SSL_VERIFY=1).${NC}"
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
        echo -e "${RED}❌ Python3 không có, không thể tiếp tục.${NC}"
        return 1
    fi

    PYTHON_CMD="python3"
    local python_version
    python_version=$($PYTHON_CMD -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    $PYTHON_CMD -c "import sys; exit(0 if sys.version_info >= (3,10) else 1)" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}⚠️  Python $python_version < 3.10, một số node có thể không tương thích.${NC}"
    fi

    mkdir -p "$COMFY_BASE" "$MODELS" "$CUSTOM_NODES"
    if [ -z "$LOG_FILE" ]; then
        LOG_FILE="$COMFY_BASE/setup_log_$(date +%Y%m%d_%H%M%S).txt"
        > "$LOG_FILE"
    fi
    if [ -z "$MANIFEST_FILE" ]; then
        MANIFEST_FILE="$COMFY_BASE/manifest.json"
    fi
    return 0
}

log_event() {
    local level="$1"
    local message="$2"
    if [ -n "$LOG_FILE" ]; then
        mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
        echo "$(date '+%Y-%m-%d %H:%M:%S') | $level | $message" >> "$LOG_FILE"
    fi
}

check_tool() {
    local tool="$1"
    local apt_pkg="$2"
    if command -v "$tool" &>/dev/null; then
        echo -e "   ${GREEN}✅ $tool đã có${NC}"
        return 0
    else
        echo -e "   ${RED}❌ $tool chưa cài${NC}"
        echo -e "      ${YELLOW}➡️  Cài thủ công bằng lệnh: sudo apt-get update && sudo apt-get install -y $apt_pkg${NC}"
        return 1
    fi
}

check_disk_space() {
    local avail_space_gb
    avail_space_gb=$(df -BG "$COMFY_BASE" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ -z "$avail_space_gb" ]; then
        echo -e "${YELLOW}⚠️  Không thể kiểm tra dung lượng ổ đĩa.${NC}"
        return 0
    elif [ "$avail_space_gb" -lt "$REQUIRED_SPACE_GB" ]; then
        echo -e "${RED}⚠️  Dung lượng trống: ${avail_space_gb}GB, cần ít nhất ${REQUIRED_SPACE_GB}GB.${NC}"
        echo -e "${YELLOW}   Có thể hết dung lượng giữa chừng khi tải. Vẫn tiếp tục? (y/N)${NC}"
        read -r CONTINUE_LOW_SPACE
        if [[ ! "$CONTINUE_LOW_SPACE" =~ ^[Yy]$ ]]; then
            echo -e "${RED}Đã hủy. Hãy giải phóng thêm dung lượng rồi chạy lại.${NC}"
            return 1
        fi
    else
        echo -e "${GREEN}✅ Dung lượng trống: ${avail_space_gb}GB${NC}"
    fi
}

download_model() {
    local url="$1"
    local output_path="$2"
    local description="$3"
    local expected_sha256="$4"
    local dir_name
    dir_name=$(dirname "$output_path")
    mkdir -p "$dir_name"

    echo -e "\n${CYAN}⬇️  [${CURRENT}/${TOTAL}] Tải:${NC} $description"
    echo -e "   ${YELLOW}URL:${NC} $url"
    echo -e "   ${YELLOW}Lưu:${NC} $output_path"

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
            echo -e "   ${YELLOW}⚠️  File nhỏ hơn 1MB, tải lại.${NC}"
            rm -f "$output_path"
        fi
    fi

    if [ "${DRY_RUN:-0}" = "1" ]; then
        if [[ "$url" != http* ]] || [ -z "$output_path" ]; then
            echo -e "   ${RED}❌ [DRY_RUN] URL hoặc đường dẫn không hợp lệ (rỗng/token thiếu?).${NC}"
            log_event "DRY_FAIL" "$description | $output_path | BAD_FORMAT"
            return 1
        fi

        local http_code=""
        if command -v curl &>/dev/null; then
            http_code=$(curl -s $CURL_SSL_OPT -o /dev/null -w "%{http_code}" -L --max-time 15 -I "$url" 2>/dev/null)
        elif command -v wget &>/dev/null; then
            wget --spider $WGET_SSL_OPT --timeout=15 -q "$url" 2>/dev/null && http_code="200" || http_code="000"
        else
            echo -e "   ${YELLOW}⚠️  [DRY_RUN] Không có curl/wget để kiểm tra, bỏ qua kiểm tra mạng.${NC}"
            log_event "DRY_SKIP" "$description | $output_path | NO_CURL_WGET"
            return 0
        fi

        if [[ "$http_code" =~ ^(200|206|302|301)$ ]]; then
            echo -e "   ${GREEN}🧪 [DRY_RUN] OK (HTTP $http_code) - URL/token hợp lệ, sẽ tải được.${NC}"
            log_event "DRY_OK" "$description | $output_path | HTTP_$http_code"
            return 0
        else
            echo -e "   ${RED}❌ [DRY_RUN] LỖI (HTTP $http_code) - URL sai, hết hạn, hoặc token không hợp lệ.${NC}"
            log_event "DRY_FAIL" "$description | $output_path | HTTP_$http_code"
            return 1
        fi
    fi

    local temp_file="${output_path}.tmp"
    local success=0
    if command -v aria2c &>/dev/null; then
        echo -e "   ${BLUE}⚡ Dùng aria2c (tăng tốc)${NC}"
        aria2c $ARIA2_SSL_OPT \
               --max-connection-per-server=4 \
               --split=4 \
               --console-log-level=error \
               --summary-interval=1 \
               --timeout=30 \
               --max-tries=10 \
               --retry-wait=5 \
               --continue=true \
               --dir="$(dirname "$temp_file")" \
               --out="$(basename "$temp_file")" \
               "$url" && success=1
    elif command -v wget &>/dev/null; then
        echo -e "   ${BLUE}🐢 Dùng wget (có retry)${NC}"
        wget -c $WGET_SSL_OPT --tries=10 --waitretry=5 --timeout=30 --progress=bar:force:noscroll -O "$temp_file" "$url" && success=1
    else
        echo -e "${RED}❌ Không có wget hay aria2c. Cần cài đặt.${NC}"
        return 1
    fi

    if [ $success -eq 0 ] || [ ! -f "$temp_file" ]; then
        echo -e "   ${RED}❌ Tải thất bại.${NC}"
        log_event "FAIL" "$description | $output_path"
        rm -f "$temp_file"
        return 1
    fi

    local size
    size=$(stat -c%s "$temp_file" 2>/dev/null || stat -f%z "$temp_file" 2>/dev/null || echo 0)
    if [ "$size" -lt 1048576 ]; then
        echo -e "   ${RED}❌ File quá nhỏ (${size} bytes) – có thể lỗi.${NC}"
        log_event "FAIL_SIZE" "$description | $output_path"
        rm -f "$temp_file"
        return 1
    fi

    if [ -n "$expected_sha256" ] && command -v sha256sum &>/dev/null; then
        local actual_sha
        actual_sha=$(sha256sum "$temp_file" 2>/dev/null | awk '{print $1}')
        if [ "$actual_sha" != "$expected_sha256" ]; then
            echo -e "   ${RED}❌ SHA256 không khớp.${NC}"
            log_event "FAIL_SHA" "$description | $output_path"
            rm -f "$temp_file"
            return 1
        fi
    fi

    mv "$temp_file" "$output_path"
    local size_h
    size_h=$(du -sh "$output_path" | cut -f1)
    echo -e "   ${GREEN}✅ Thành công (${size_h})${NC}"
    log_event "OK" "$description | $output_path | $size_h"
    return 0
}

clone_or_pull() {
    local repo_url="$1"
    local target_dir="$2"
    local description="$3"

    if [ "${DRY_RUN:-0}" = "1" ]; then
        if [[ "$repo_url" != http* ]]; then
            echo -e "   ${RED}❌ [DRY_RUN] URL repo không hợp lệ: $repo_url${NC}"
            log_event "DRY_CLONE_FAIL" "$description | $target_dir | BAD_FORMAT"
            return 1
        fi
        if env $GIT_SSL_ENV git ls-remote --exit-code "$repo_url" HEAD >/dev/null 2>&1; then
            echo -e "   ${GREEN}🧪 [DRY_RUN] Repo truy cập được:${NC} $description"
            log_event "DRY_CLONE_OK" "$description | $target_dir"
            return 0
        else
            echo -e "   ${RED}❌ [DRY_RUN] Không truy cập được repo (URL sai/private/mạng lỗi): $repo_url${NC}"
            log_event "DRY_CLONE_FAIL" "$description | $target_dir | UNREACHABLE"
            return 1
        fi
    fi

    if [ -d "$target_dir/.git" ]; then
        echo -e "   ${YELLOW}🔄 Repo đã tồn tại, cập nhật (git pull)${NC}"
        (cd "$target_dir" && env $GIT_SSL_ENV git pull --rebase --quiet) || echo -e "${RED}   Git pull thất bại${NC}"
        log_event "PULL" "$description | $target_dir"
        return 0
    elif [ -d "$target_dir" ]; then
        echo -e "   ${YELLOW}⚠️  Thư mục tồn tại nhưng không phải git, xóa và clone lại${NC}"
        rm -rf "$target_dir"
    fi

    echo -e "   ${BLUE}📦 Clone mới:${NC} $description"
    env $GIT_SSL_ENV git clone --quiet "$repo_url" "$target_dir"
    if [ $? -eq 0 ]; then
        echo -e "   ${GREEN}✅ Clone thành công${NC}"
        log_event "CLONE_OK" "$description | $target_dir"
        return 0
    else
        echo -e "   ${RED}❌ Clone thất bại${NC}"
        log_event "CLONE_FAIL" "$description | $target_dir"
        return 1
    fi
}

install_requirements() {
    local dir="$1"
    if [ -f "$dir/requirements.txt" ]; then
        echo -e "   ${CYAN}📥 Cài requirements cho $(basename "$dir")${NC}"

        if [ "${DRY_RUN:-0}" = "1" ]; then
            if $PIP_BASE_CMD install --dry-run -r "$dir/requirements.txt" $PIP_SSL_OPT >> "$COMFY_BASE/pip_install.log" 2>&1; then
                echo -e "   ${GREEN}🧪 [DRY_RUN] Requirements hợp lệ, có thể cài được.${NC}"
                log_event "DRY_PIP_OK" "$(basename "$dir")"
                return 0
            else
                echo -e "   ${YELLOW}⚠️  [DRY_RUN] pip --dry-run không hỗ trợ hoặc lỗi resolve (xem $COMFY_BASE/pip_install.log)${NC}"
                log_event "DRY_PIP_WARN" "$(basename "$dir")"
                return 0
            fi
        fi

        $PIP_BASE_CMD install -r "$dir/requirements.txt" $PIP_SSL_OPT --break-system-packages >> "$COMFY_BASE/pip_install.log" 2>&1 \
            || $PIP_BASE_CMD install -r "$dir/requirements.txt" $PIP_SSL_OPT >> "$COMFY_BASE/pip_install.log" 2>&1
        if [ $? -ne 0 ]; then
            echo -e "   ${RED}❌ Lỗi khi cài requirements (xem $COMFY_BASE/pip_install.log)${NC}"
            log_event "PIP_FAIL" "$(basename "$dir")"
            return 1
        else
            echo -e "   ${GREEN}✅ Dependencies OK${NC}"
            return 0
        fi
    fi
    return 0
}
