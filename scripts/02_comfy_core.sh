#!/bin/bash

run_stage_02() {
    init_runtime_env || return 1

    echo -e "${MAGENTA}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}🔑 Stage 02: Cấu hình Token & ComfyUI Core${NC}"
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════════${NC}"

    if [ -z "${CIVITAI_TOKEN:-}" ]; then
        if [ -t 0 ] && [ "${DRY_RUN:-0}" != "1" ]; then
            echo -e "${YELLOW}Nhập Civitai API Token của bạn (bấm Enter để bỏ qua):${NC}"
            read -r -s CIVITAI_TOKEN
            echo ""
        else
            echo -e "${YELLOW}ℹ️ Không tìm thấy CIVITAI_TOKEN trong môi trường. Tiếp tục không dùng token...${NC}"
        fi
    fi

    if [ -n "${CIVITAI_TOKEN:-}" ]; then
        CIVITAI_TOKEN="${CIVITAI_TOKEN#\?}"
        CIVITAI_TOKEN="${CIVITAI_TOKEN#token=}"
        CIVITAI_TOKEN="$(echo -n "$CIVITAI_TOKEN" | tr -d '[:space:]')"
        
        if command -v jq &>/dev/null; then
            ENCODED_TOKEN=$(printf '%s' "$CIVITAI_TOKEN" | jq -sRr @uri)
        else
            ENCODED_TOKEN=$(printf '%s' "$CIVITAI_TOKEN" | sed 's/ /%20/g; s/#/%23/g; s/&/%26/g; s/+/%2B/g')
        fi
        echo -e "${GREEN}✅ Đã nhận Civitai Token (${CIVITAI_TOKEN:0:4}...${CIVITAI_TOKEN: -4}).${NC}"
    else
        ENCODED_TOKEN=""
    fi

    export CIVITAI_TOKEN ENCODED_TOKEN

    echo -e "\n${BLUE}🔄 Cập nhật/Cài đặt ComfyUI chính tại:${NC} $COMFY_BASE"
    if [ -d "$COMFY_BASE/.git" ]; then
        echo -e "   ${YELLOW}🔄 Repo đã tồn tại, tiến hành git pull...${NC}"
        (cd "$COMFY_BASE" && env ${GIT_SSL_ENV:-} git pull --quiet 2>&1 | tail -5) || echo -e "   ${YELLOW}⚠️ Git pull có cảnh báo.${NC}"
    elif [ -f "$COMFY_BASE/main.py" ]; then
        echo -e "   ${GREEN}✅ Phát hiện ComfyUI sẵn có (không dùng Git repo).${NC}"
    else
        echo -e "   ${BLUE}📦 Tải mới ComfyUI Core từ GitHub...${NC}"
        clone_or_pull "https://github.com/comfyanonymous/ComfyUI.git" "$COMFY_BASE" "ComfyUI Core"
    fi
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_stage_02 "$@"
fi
