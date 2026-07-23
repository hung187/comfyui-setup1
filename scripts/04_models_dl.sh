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
    if [ ! -f "$config_file" ]; then
        echo -e "${RED}❌ Không tìm thấy $config_file${NC}"
        return 1
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
        
        # Determine 4-column vs 5-column format
        local field_count
        field_count=$(awk -F'|' '{print NF}' <<< "$entry")
        
        local url="" explicit_alts="" path="" desc="" sha=""
        if [ "$field_count" -ge 5 ]; then
            IFS='|' read -r url explicit_alts path desc sha <<< "$entry"
        else
            IFS='|' read -r url path desc sha <<< "$entry"
            explicit_alts=""
        fi

        url=$(resolve_config_value "$url")
        explicit_alts=$(resolve_config_value "$explicit_alts")
        path=$(resolve_config_value "$path")
        desc=$(resolve_config_value "$desc")

        MODEL_LIST+=("$url|$explicit_alts|$path|$desc|$sha")
        download_model_smart "$url" "$explicit_alts" "$path" "$desc" "$sha"
    done

    export TOTAL CURRENT LOG_FILE MANIFEST_FILE
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_stage_04 "$@"
fi
