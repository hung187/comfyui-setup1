#!/bin/bash

run_stage_04() {
    init_runtime_env || return 1

    echo -e "\n${MAGENTA}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}🚀 BẮT ĐẦU TẢI ${TOTAL} MODEL...${NC}"
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════════${NC}"

    mkdir -p "$MODELS"/checkpoints/{IL,PONY} "$MODELS"/controlnet "$MODELS"/loras/{Quality,Face,Hair,Eyes,Hands,Clothes,Character,Style,Effect,Pose,HENTAI,TU_THE_VIDEO} "$MODELS"/vae "$MODELS"/clip_vision "$MODELS"/ipadapter "$MODELS"/upscale_models "$MODELS"/insightface "$MODELS"/facerestore "$MODELS"/facexlib "$MODELS"/diffusion_models

    LOG_FILE="$COMFY_BASE/setup_log_$(date +%Y%m%d_%H%M%S).txt"
    MANIFEST_FILE="$COMFY_BASE/manifest.json"
    > "$LOG_FILE"

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
        IFS='|' read -r url path desc sha <<< "$entry"
        url=$(resolve_config_value "$url")
        path=$(resolve_config_value "$path")
        desc=$(resolve_config_value "$desc")
        MODEL_LIST+=("$url|$path|$desc|$sha")
        CURRENT=$((CURRENT+1))
        download_model "$url" "$path" "$desc" "$sha"
    done

    export TOTAL CURRENT LOG_FILE MANIFEST_FILE
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_stage_04 "$@"
fi
