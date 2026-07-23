#!/bin/bash

run_stage_01() {
    echo -e "${BLUE}🔍 Stage 01: Kiểm tra & Cài đặt công cụ hệ thống...${NC}"
    init_runtime_env || return 1

    ensure_tool_installed "git" "git" || true
    ensure_tool_installed "wget" "wget" || true
    ensure_tool_installed "aria2c" "aria2" || true
    ensure_tool_installed "sha256sum" "coreutils" || true
    ensure_tool_installed "python3" "python3 python3-pip" || true
    ensure_tool_installed "jq" "jq" || true

    if ! command -v python3 &>/dev/null; then
        echo -e "${RED}❌ Python3 không khả dụng. Không thể tiếp tục.${NC}"
        return 1
    fi

    echo -e "\n${BLUE}📦 Cài đặt Python packages...${NC}"

    mkdir -p "$COMFY_BASE"
    PIP_LOG="$COMFY_BASE/pip_install.log"
    > "$PIP_LOG"

    $PIP_BASE_CMD install --upgrade pip $PIP_SSL_OPT >> "$PIP_LOG" 2>&1 || true

    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo -e "   ${CYAN}🧪 [DRY_RUN] Bỏ qua tải torch nặng (~2-3GB), kiểm tra pip...${NC}"
        if $PIP_BASE_CMD --version >> "$PIP_LOG" 2>&1; then
            echo -e "   ${GREEN}✅ [DRY_RUN] Pip sẵn sàng.${NC}"
        fi
    else
        if "$PYTHON_CMD" -c "import torch" &>/dev/null; then
            TORCH_VER=$("$PYTHON_CMD" -c "import torch; print(torch.__version__)" 2>/dev/null)
            echo -e "   ${GREEN}✅ torch đã có sẵn (v$TORCH_VER), bỏ qua cài lại.${NC}"
        else
            echo -e "   ${YELLOW}⬇️  Đang cài đặt PyTorch (vui lòng đợi vài phút)...${NC}"
            $PIP_BASE_CMD install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118 $PIP_SSL_OPT --break-system-packages >> "$PIP_LOG" 2>&1 \
                || $PIP_BASE_CMD install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118 $PIP_SSL_OPT >> "$PIP_LOG" 2>&1 \
                || true
        fi
    fi

    echo -e "${GREEN}✅ Môi trường Python đã hoàn tất.${NC}"
    check_disk_space
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_stage_01 "$@"
fi
