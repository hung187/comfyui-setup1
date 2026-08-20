#!/bin/bash

# Standalone reusable state machine writer for ComfyUI model downloads
update_state_machine_internal() {
    local state_file="$1"
    local path="$2"
    local status="$3"
    local current_url="${4:-}"
    local attempts="${5:-0}"
    local downloader="${6:-unknown}"
    local err_msg="${7:-}"
    local total="${8:-0}"

    python3 - "$state_file" "$path" "$status" "$current_url" "$attempts" "$downloader" "$err_msg" "$total" <<'PY_STATE' 2>/dev/null || true
import sys, os, json, time, fcntl, re

state_file, path, status, current_url, attempts, downloader, err_msg, total = (
    sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6], sys.argv[7], int(sys.argv[8])
)

# Use normalized path relative to models dir as key if possible, else normalized absolute path
norm_path = os.path.normpath(path)
clean_url = re.sub(r'([?&](token|api_key|apikey|key|authorization|access_token|auth|secret|signature)=)[^&]+', r'\1***', current_url)

lock_file = state_file + '.lock'
os.makedirs(os.path.dirname(state_file), exist_ok=True)

try:
    with open(lock_file, 'w') as lock_f:
        fcntl.flock(lock_f, fcntl.LOCK_EX)
        try:
            data = {'updated_at': time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), 'total': total, 'models': {}}
            if os.path.exists(state_file):
                try:
                    with open(state_file, 'r') as f:
                        data = json.load(f)
                except Exception:
                    data = {'updated_at': time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), 'total': total, 'models': {}}

            fsize = os.path.getsize(norm_path) if os.path.exists(norm_path) else 0
            if 'models' not in data:
                data['models'] = {}

            # Key by destination normalized path to prevent same-basename collisions in different folders
            data['models'][norm_path] = {
                'path': norm_path,
                'status': status,
                'size': fsize,
                'actual_source_url': clean_url,
                'attempts': int(attempts),
                'downloader': downloader,
                'last_error': err_msg,
                'timestamp': int(time.time())
            }
            data['updated_at'] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

            tmp_file = f"{state_file}.tmp.{os.getpid()}_{time.time_ns()}"
            with open(tmp_file, 'w') as f:
                json.dump(data, f, indent=2)
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp_file, state_file)
        finally:
            fcntl.flock(lock_f, fcntl.LOCK_UN)
except Exception:
    pass
PY_STATE
}

export -f update_state_machine_internal 2>/dev/null || true

run_stage_04() {
    init_runtime_env || return 1

    echo -e "\n${MAGENTA}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}🚀 Stage 04: Bắt đầu tải Models với cơ chế Multi-Mirror Fallback...${NC}"
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════════${NC}"

    mkdir -p "$MODELS"/checkpoints/IL \
             "$MODELS"/controlnet \
             "$MODELS"/loras/{Quality,Face,Hands,Character,Style,Effect,Pose} \
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
    local state_json="$COMFY_BASE/download_state.json"

    if [ ! -f "$config_file" ]; then
        echo -e "${RED}❌ Không tìm thấy $config_file${NC}"
        return 1
    fi

    # Pre-validate primary and backup configs
    if ! validate_models_config "$config_file" "$MODELS" 2>/dev/null; then
        echo -e "${RED}❌ File models_list.csv không vượt qua kiểm tra cấu hình!${NC}"
        return 1
    fi
    if [ -f "$backup_config_file" ] && ! validate_backup_config "$backup_config_file" "$config_file" "$MODELS" 2>/dev/null; then
        echo -e "${RED}❌ File models_backup_list.csv không vượt qua kiểm tra cấu hình!${NC}"
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
                [ -n "$alink" ] && [[ "$alink" != *"civitai.red"* ]] && combined_alts="${combined_alts:+$combined_alts,}$alink"
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
    local success_count=0
    local skip_count=0
    local fail_count=0

    update_state_machine() {
        local path="$1"
        local status="$2"
        local current_url="${3:-}"
        local attempts="${4:-0}"
        local downloader="${5:-aria2c/curl}"
        local err_msg="${6:-}"

        update_state_machine_internal "$state_json" "$path" "$status" "$current_url" "$attempts" "$downloader" "$err_msg" "$TOTAL"
    }

    local idx=0
    for entry in "${model_entries[@]}"; do
        CURRENT=$((CURRENT + 1))
        idx=$((idx + 1))

        local url="" explicit_alts="" path="" desc="" sha=""
        IFS='|' read -r url path desc sha <<< "$entry"

        url=$(resolve_config_value "$url")
        path=$(resolve_config_value "$path")
        desc=$(resolve_config_value "$desc")

        explicit_alts="${backup_map[$path]:-}"
        MODEL_LIST+=("$url|$explicit_alts|$path|$desc|$sha")

        update_state_machine "$path" "resolving_source" "$url" 0 "downloader" ""

        if download_model_smart "$url" "$explicit_alts" "$path" "$desc" "$sha"; then
            # Extract actual used url from MIRROR_FILES if mirror was used
            local recorded_url="$url"
            for mf in "${MIRROR_FILES[@]}"; do
                local m_desc="" m_out="" m_prim="" m_used="" m_sz=""
                IFS='|' read -r m_desc m_out m_prim m_used m_sz <<< "$mf"
                if [ "$m_out" = "$path" ]; then
                    recorded_url="$m_used"
                    break
                fi
            done

            update_state_machine "$path" "completed" "$recorded_url" 1 "downloader" ""
            success_count=$((success_count + 1))
        else
            update_state_machine "$path" "failed" "$url" 1 "downloader" "Tất cả mirror đều lỗi hoặc không vượt qua verification"
            fail_count=$((fail_count + 1))
        fi
    done

    export TOTAL CURRENT LOG_FILE MANIFEST_FILE

    echo -e "\n${MAGENTA}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✅ Stage 04 hoàn tất: $CURRENT/$TOTAL model xử lý | ✔ $success_count thành công | ❌ $fail_count thất bại${NC}"
    echo -e "${CYAN}📄 Báo cáo trạng thái chi tiết đã lưu tại:${NC} $state_json"
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════════${NC}\n"
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_stage_04 "$@"
fi
