#!/bin/bash

run_stage_03() {
    init_runtime_env || return 1

    echo -e "\n${MAGENTA}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}📦 Stage 03: Cài đặt Custom Nodes...${NC}"
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════════${NC}"
    mkdir -p "$CUSTOM_NODES"

    local config_file="$SCRIPT_DIR/config/nodes_list.txt"
    if [ ! -f "$config_file" ]; then
        echo -e "${RED}❌ Không tìm thấy $config_file${NC}"
        return 1
    fi

    # Run node configuration validation
    if ! validate_nodes_config "$config_file" "$CUSTOM_NODES" 2>/dev/null; then
        echo -e "${RED}❌ File cấu hình nodes_list.txt không hợp lệ hoặc có lỗi bảo mật!${NC}"
        return 1
    fi

    local node_ok=0 node_fail=0 node_total=0

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        [ "${line#\#}" != "$line" ] && continue
        local url="" path="" desc=""
        IFS='|' read -r url path desc <<< "$line"
        url=$(resolve_config_value "$url")
        path=$(resolve_config_value "$path")
        desc=$(resolve_config_value "$desc")

        if [ -z "$path" ]; then
            path="$CUSTOM_NODES/$(basename "$url" .git)"
        fi
        if [ -z "$desc" ]; then
            desc="$(basename "$url" .git)"
        fi

        # Pre-check containment and URL
        if ! validate_node_destination "$path" "$CUSTOM_NODES" 2>/dev/null || ! validate_url "$url" 2>/dev/null; then
            echo -e "${RED}❌ Bỏ qua node có đường dẫn hoặc URL không hợp lệ: $desc${NC}"
            node_fail=$((node_fail + 1))
            continue
        fi

        node_total=$((node_total + 1))
        if clone_or_pull "$url" "$path" "$desc"; then
            node_ok=$((node_ok + 1))
        else
            node_fail=$((node_fail + 1))
        fi
    done < "$config_file"

    echo -e "\n${BLUE}📦 Cài đặt Dependencies cho Custom Nodes...${NC}"
    for dir in "$CUSTOM_NODES"/*/; do
        [ -d "$dir" ] && install_requirements "$dir"
    done

    echo -e "   ${CYAN}🧹 Dọn dẹp bộ nhớ tạm pip cache để giải phóng đĩa...${NC}"
    $PIP_BASE_CMD cache purge >> "$COMFY_BASE/pip_install.log" 2>&1 || true

    echo -e "\n${MAGENTA}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✅ Stage 03 hoàn tất: $node_ok/$node_total nodes cài thành công${NC}$([ $node_fail -gt 0 ] && echo -e " | ${RED}❌ $node_fail thất bại${NC}")"
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════════${NC}\n"
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_stage_03 "$@"
fi
