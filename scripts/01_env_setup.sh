#!/bin/bash

run_stage_01() {
    echo -e "${BLUE}🔍 Kiểm tra công cụ cần thiết...${NC}"
    init_runtime_env || return 1

    check_tool "git" "git" || true
    check_tool "wget" "wget" || true
    check_tool "aria2c" "aria2" || true
    check_tool "sha256sum" "coreutils" || true
    check_tool "python3" "python3 python3-pip" || true
    check_tool "jq" "jq" || true

    if ! command -v python3 &>/dev/null; then
        echo -e "${RED}❌ Python3 không có, không thể tiếp tục.${NC}"
        return 1
    fi

    echo -e "\n${BLUE}📦 Cài đặt Python packages (trực tiếp vào hệ thống, không venv)...${NC}"

    mkdir -p "$COMFY_BASE"
    PIP_LOG="$COMFY_BASE/pip_install.log"
    > "$PIP_LOG"

    $PIP_BASE_CMD install --upgrade pip $PIP_SSL_OPT >> "$PIP_LOG" 2>&1

    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo -e "   ${CYAN}🧪 [DRY_RUN] Bỏ qua cài torch (nặng ~2-3GB), chỉ kiểm tra pip hoạt động.${NC}"
        if $PIP_BASE_CMD --version >> "$PIP_LOG" 2>&1; then
            echo -e "   ${GREEN}✅ [DRY_RUN] pip hoạt động bình thường.${NC}"
        else
            echo -e "   ${RED}❌ [DRY_RUN] pip KHÔNG hoạt động (xem $PIP_LOG).${NC}"
        fi
    else
        if "$PYTHON_CMD" -c "import torch" &>/dev/null; then
            TORCH_VER=$("$PYTHON_CMD" -c "import torch; print(torch.__version__)" 2>/dev/null)
            echo -e "   ${GREEN}✅ torch đã cài sẵn (v$TORCH_VER), bỏ qua cài lại.${NC}"
        else
            echo -e "   ${YELLOW}⬇️  Đang cài torch (~2-3GB, có thể mất vài phút, xin đừng Ctrl+C)...${NC}"
            $PIP_BASE_CMD install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118 $PIP_SSL_OPT --break-system-packages >> "$PIP_LOG" 2>&1 \
                || $PIP_BASE_CMD install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118 $PIP_SSL_OPT >> "$PIP_LOG" 2>&1
        fi

        if [ -f "$COMFY_BASE/requirements.txt" ]; then
            $PIP_BASE_CMD install -r "$COMFY_BASE/requirements.txt" $PIP_SSL_OPT --break-system-packages >> "$PIP_LOG" 2>&1 \
                || $PIP_BASE_CMD install -r "$COMFY_BASE/requirements.txt" $PIP_SSL_OPT >> "$PIP_LOG" 2>&1
        fi
    fi

    echo -e "${GREEN}✅ Python packages sẵn sàng.${NC}"
    check_disk_space
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_stage_01 "$@"
fi
