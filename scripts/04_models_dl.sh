#!/bin/bash

run_stage_04() {
    init_runtime_env || return 1

    echo -e "\n${MAGENTA}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}🚀 Stage 04: Bắt đầu tải Models với cơ chế Multi-Mirror Fallback...${NC}"
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════════${NC}"

    mkdir -p "$MODELS"/checkpoints/{IL,PONY} \
             "$MODELS"/controlnet \
             "$MODELS"/loras/{Quality,Face,Hair,Eyes,Hands,Clothes,Character,Style,Effect,Pose,HENTAI,TU_THE_VIDEO} \
             "$MODELS"/vae \
             "$MODELS"/clip_vision \
             "$MODELS"/ipadapter \
             "$MODELS"/upscale_models \
             "$MODELS"/insightface \
             "$MODELS"/facerestore \
             "$MODELS"/facexlib \
             "$MODELS"/diffusion_models

    local config_file="$SCRIPT_DIR/config/models_list.csv"
    local backup_config_file="$SCRIPT_DIR/config/models_backup_list.csv"

    if [ ! -f "$config_file" ]; then
        echo -e "${RED}❌ Không tìm thấy $config_file${NC}"
        return 1
    fi

    # Load Backup Links from models_backup_list.csv
    declare -A backup_map=()
    if [ -f "$backup_config_file" ]; then
        while IFS= read -r b_line; do
            [ -z "$b_line" ] && continue
            [ "${b_line#\#}" != "$b_line" ] && continue

            local b_path="" b_link1="" b_link2="" b_link3=""
            IFS='|' read -r b_path b_link1 b_link2 b_link3 <<< "$b_line"
            b_path=$(resolve_config_value "$b_path")
            
            local combined_alts=""
            for alink in "$b_link1" "$b_link2" "$b_link3"; do
                alink=$(resolve_config_value "$alink")
                [ -n "$alink" ] && combined_alts="${combined_alts:+$combined_alts,}$alink"
            done

            if [ -n "$b_path" ]; then
                backup_map["$b_path"]="$combined_alts"
            fi
        done < "$backup_config_file"
    fi

    local -a model_entries=()
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        [ "${line#\#}" != "$line" ] && continue
        model_entries+=("$line")
    done < "$config_file"

    MODEL_LIST=()
    TOTAL=${#model_entries[@]}
    CURRENT=0

    for entry in "${model_entries[@]}"; do
        CURRENT=$((CURRENT + 1))
        
        local url="" explicit_alts="" path="" desc="" sha=""
        IFS='|' read -r url path desc sha <<< "$entry"

        url=$(resolve_config_value "$url")
        path=$(resolve_config_value "$path")
        desc=$(resolve_config_value "$desc")

        # Fetch backup links from backup_map
        explicit_alts="${backup_map[$path]:-}"

        MODEL_LIST+=("$url|$explicit_alts|$path|$desc|$sha")
        download_model_smart "$url" "$explicit_alts" "$path" "$desc" "$sha"
    done

    export TOTAL CURRENT LOG_FILE MANIFEST_FILE
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_stage_04 "$@"
fi
