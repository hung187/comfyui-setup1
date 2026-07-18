#!/bin/bash

run_stage_02() {
    init_runtime_env || return 1

    echo -e "${MAGENTA}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}🔑 CẤU HÌNH CIVITAI TOKEN${NC}"
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════════${NC}"

    if [ -z "$CIVITAI_TOKEN" ]; then
        echo -e "${YELLOW}Nhập Civitai API Token của bạn (ký tự sẽ được ẩn):${NC}"
        echo -e "${YELLOW}Lưu ý: chỉ dán RIÊNG chuỗi token, KHÔNG kèm chữ 'token=' phía trước.${NC}"
        read -r -s CIVITAI_TOKEN
        echo ""
    fi

    if [ -z "$CIVITAI_TOKEN" ]; then
        echo -e "${RED}❌ Không có token nào được nhập. Một số model trên Civitai sẽ tải thất bại.${NC}"
        echo -e "${YELLOW}   Bạn có muốn tiếp tục mà không có token? (y/N)${NC}"
        read -r CONTINUE_NO_TOKEN
        if [[ ! "$CONTINUE_NO_TOKEN" =~ ^[Yy]$ ]]; then
            echo -e "${RED}Đã hủy. Chạy lại script và nhập token để tiếp tục.${NC}"
            return 1
        fi
    else
        CIVITAI_TOKEN="${CIVITAI_TOKEN#\?}"
        CIVITAI_TOKEN="${CIVITAI_TOKEN#token=}"
        CIVITAI_TOKEN="$(echo -n "$CIVITAI_TOKEN" | tr -d '[:space:]')"
        echo -e "${GREEN}✅ Đã nhận token (${CIVITAI_TOKEN:0:4}...${CIVITAI_TOKEN: -4}).${NC}"
    fi

    if [ -n "$CIVITAI_TOKEN" ]; then
        if command -v jq &>/dev/null; then
            ENCODED_TOKEN=$(printf '%s' "$CIVITAI_TOKEN" | jq -sRr @uri)
        else
            ENCODED_TOKEN=$(printf '%s' "$CIVITAI_TOKEN" | sed 's/ /%20/g; s/#/%23/g; s/&/%26/g; s/+/%2B/g')
        fi
    else
        ENCODED_TOKEN=""
    fi

    export CIVITAI_TOKEN ENCODED_TOKEN

    echo -e "${GREEN}▶️  Bắt đầu quá trình cài đặt...${NC}\n"

    if [ -n "$CIVITAI_TOKEN" ] && [ "${DRY_RUN:-0}" != "1" ] && command -v curl &>/dev/null; then
        echo -e "${BLUE}🔎 Đang kiểm tra token với Civitai...${NC}"
        TEST_URL="https://civitai.com/api/download/models/1546777?fileId=1446530&token=$ENCODED_TOKEN"
        TEST_CODE=$(curl -s $CURL_SSL_OPT -o /dev/null -w "%{http_code}" -L --max-time 15 -I "$TEST_URL" 2>/dev/null)
        if [[ "$TEST_CODE" =~ ^(401|403)$ ]]; then
            echo -e "${RED}❌ Token KHÔNG hợp lệ (HTTP $TEST_CODE - Authorization failed).${NC}"
            echo -e "${YELLOW}   Nguyên nhân thường gặp: dán nhầm cả 'token=xxx' thay vì chỉ dán riêng chuỗi token.${NC}"
            echo -e "${YELLOW}   Lấy token đúng tại: https://civitai.com/user/account -> API Keys${NC}"
            echo -e "${YELLOW}   Bạn có muốn tiếp tục dù token sai? Các model cần đăng nhập sẽ tải lỗi. (y/N)${NC}"
            read -r CONTINUE_BAD_TOKEN
            if [[ ! "$CONTINUE_BAD_TOKEN" =~ ^[Yy]$ ]]; then
                echo -e "${RED}Đã hủy. Chạy lại script và nhập đúng token.${NC}"
                return 1
            fi
        elif [[ "$TEST_CODE" == "000" ]]; then
            echo -e "${YELLOW}⚠️  Không kết nối được để kiểm tra token (có thể do lỗi SSL/mạng).${NC}"
            echo -e "${YELLOW}   Nếu gặp lỗi SSL certificate, thử chạy lại với: DISABLE_SSL_VERIFY=1 bash $0${NC}"
        else
            echo -e "${GREEN}✅ Token hợp lệ (HTTP $TEST_CODE).${NC}"
        fi
    fi

    echo -e "\n${BLUE}🔄 Cập nhật ComfyUI chính...${NC}"
    if [ -d "$COMFY_BASE/.git" ]; then
        (cd "$COMFY_BASE" && env $GIT_SSL_ENV git pull --quiet 2>&1 | tail -5)
    else
        echo -e "${YELLOW}⚠️  ComfyUI không phải git, bỏ qua.${NC}"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_stage_02 "$@"
fi
