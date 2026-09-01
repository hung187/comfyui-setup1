#!/bin/bash

run_stage_02() {
    init_runtime_env || return 1

    echo -e "${MAGENTA}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}⚙️  Stage 02: Cấu hình Token & Cài đặt ComfyUI Core${NC}"
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════════${NC}"

    prepare_civitai_credentials

    echo -e "\n${BLUE}🔄 Cập nhật/Cài đặt ComfyUI Core tại:${NC} $COMFY_BASE"
    if [ -d "$COMFY_BASE/.git" ]; then
        if [ "${UPDATE_EXISTING:-0}" = "1" ]; then
            echo -e "   ${YELLOW}🔄 Repo đã tồn tại, tiến hành git pull...${NC}"
            (cd "$COMFY_BASE" && env ${GIT_SSL_ENV:-} git pull --quiet 2>&1 | tail -5) || echo -e "   ${YELLOW}⚠️ Git pull có cảnh báo.${NC}"
        else
            echo -e "   ${GREEN}✅ Repo ComfyUI Core đã tồn tại (giữ nguyên).${NC}"
        fi
    elif [ -f "$COMFY_BASE/main.py" ]; then
        echo -e "   ${GREEN}✅ Phát hiện ComfyUI sẵn có (không dùng Git repo).${NC}"
    else
        echo -e "   ${BLUE}📦 Tải mới ComfyUI Core từ GitHub...${NC}"
        local temp_core
        temp_core=$(mktemp -d)
        if env ${GIT_SSL_ENV:-} git clone --quiet --depth 1 "https://github.com/comfyanonymous/ComfyUI.git" "$temp_core"; then
            cp -rn "$temp_core"/. "$COMFY_BASE"/ 2>/dev/null || cp -r "$temp_core"/* "$COMFY_BASE"/ 2>/dev/null || true
            rm -rf "$temp_core"
            echo -e "   ${GREEN}✅ Cài đặt ComfyUI Core thành công.${NC}"
        else
            rm -rf "$temp_core"
            echo -e "   ${RED}❌ Tải ComfyUI Core thất bại.${NC}"
            return 1
        fi
    fi
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_stage_02 "$@"
fi
