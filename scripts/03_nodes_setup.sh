#!/bin/bash

run_stage_03() {
    init_runtime_env || return 1

    echo -e "\n${BLUE}📦 CÀI ĐẶT CUSTOM NODES...${NC}"
    mkdir -p "$CUSTOM_NODES"

    local config_file="$SCRIPT_DIR/config/nodes_list.txt"
    if [ ! -f "$config_file" ]; then
        echo -e "${RED}❌ Không tìm thấy $config_file${NC}"
        return 1
    fi

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
        clone_or_pull "$url" "$path" "$desc"
    done < "$config_file"

    echo -e "\n${BLUE}📦 CÀI DEPENDENCIES CHO CUSTOM NODES...${NC}"
    for dir in "$CUSTOM_NODES"/*/; do
        [ -d "$dir" ] && install_requirements "$dir"
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_stage_03 "$@"
fi
