#!/bin/bash

run_stage_05() {
    init_runtime_env || return 1

    echo -e "\n${BLUE}📝 Tạo manifest.json với Python để đảm bảo an toàn...${NC}"
    export COMFY_BASE TOTAL MANIFEST_FILE
    "$PYTHON_CMD" - "$MANIFEST_FILE" "${MODEL_LIST[@]}" <<'PY'
import json
import os
import subprocess
import sys
import datetime

manifest = {
    "timestamp": datetime.datetime.now().isoformat(),
    "comfyui_base": os.environ.get("COMFY_BASE", ""),
    "total_models": int(os.environ.get("TOTAL", "0")),
    "model_list": [],
}

for entry in sys.argv[2:]:
    url, path, desc, sha = entry.split("|", 3)
    status = "MISSING"
    size_h = ""
    actual_sha = ""

    if os.path.isfile(path):
        status = "OK"
        size_h = subprocess.getoutput(f'du -sh "{path}"').split()[0]
        if os.system("command -v sha256sum >/dev/null 2>&1") == 0:
            actual_sha = subprocess.getoutput(f'sha256sum "{path}"').split()[0]

    manifest["model_list"].append({
        "url": url,
        "path": path,
        "desc": desc,
        "status": status,
        "size": size_h,
        "sha256": actual_sha,
    })

with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump(manifest, f, indent=2, ensure_ascii=False)
PY

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Manifest đã lưu tại $MANIFEST_FILE${NC}"
    else
        echo -e "${RED}❌ Lỗi tạo manifest, vẫn tiếp tục.${NC}"
    fi

    echo -e "\n${MAGENTA}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}📊 BÁO CÁO HOÀN THÀNH${NC}"
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════════${NC}"

    if [ "${DRY_RUN:-0}" = "1" ]; then
        dry_url_ok=$(grep -c "| DRY_OK |" "$LOG_FILE" 2>/dev/null) || dry_url_ok=0
        dry_url_fail=$(grep -c "| DRY_FAIL |" "$LOG_FILE" 2>/dev/null) || dry_url_fail=0
        dry_clone_ok=$(grep -c "| DRY_CLONE_OK |" "$LOG_FILE" 2>/dev/null) || dry_clone_ok=0
        dry_clone_fail=$(grep -c "| DRY_CLONE_FAIL |" "$LOG_FILE" 2>/dev/null) || dry_clone_fail=0
        dry_pip_ok=$(grep -c "| DRY_PIP_OK |" "$LOG_FILE" 2>/dev/null) || dry_pip_ok=0
        dry_pip_warn=$(grep -c "| DRY_PIP_WARN |" "$LOG_FILE" 2>/dev/null) || dry_pip_warn=0

        echo -e "${CYAN}🧪 KẾT QUẢ DRY_RUN (không có file/model nào được tải thật)${NC}\n"
        echo -e "${BLUE}🔗 URL Model:${NC}   ${GREEN}$dry_url_ok OK${NC} / ${RED}$dry_url_fail LỖI${NC} / tổng $TOTAL"
        local total_nodes
        total_nodes=$(grep -cvE '^\s*(#|$)' "$SCRIPT_DIR/config/nodes_list.txt" 2>/dev/null) || total_nodes=0
        echo -e "${BLUE}📦 Custom Node:${NC} ${GREEN}$dry_clone_ok OK${NC} / ${RED}$dry_clone_fail LỖI${NC} / tổng $total_nodes"
        echo -e "${BLUE}🐍 Pip requirements:${NC} ${GREEN}$dry_pip_ok OK${NC} / ${YELLOW}$dry_pip_warn CẢNH BÁO${NC}"

        if [ "$dry_url_fail" -gt 0 ] || [ "$dry_clone_fail" -gt 0 ]; then
            echo -e "\n${RED}⚠️  Có lỗi cần xử lý trước khi chạy thật. Xem chi tiết trong: $LOG_FILE${NC}"
            echo -e "${YELLOW}   Lọc nhanh dòng lỗi: grep 'FAIL' \"$LOG_FILE\"${NC}"
        else
            echo -e "\n${GREEN}✅ Tất cả URL và repo đều hợp lệ, script sẵn sàng chạy thật!${NC}"
            echo -e "${YELLOW}   Chạy thật (tải đầy đủ): bash $0${NC}"
        fi
        echo -e "\n${MAGENTA}════════════════════════════════════════════════════════════════${NC}"
        return 0
    fi

    count_ckpt=$(find "$MODELS/checkpoints" -type f \( -name "*.safetensors" -o -name "*.ckpt" -o -name "*.gguf" \) 2>/dev/null | wc -l)
    count_ctrl=$(find "$MODELS/controlnet" -type f -name "*.safetensors" 2>/dev/null | wc -l)
    count_lora=$(find "$MODELS/loras" -type f -name "*.safetensors" 2>/dev/null | wc -l)
    count_vae=$(find "$MODELS/vae" -type f -name "*.safetensors" 2>/dev/null | wc -l)
    count_clip=$(find "$MODELS/clip_vision" -type f -name "*.safetensors" 2>/dev/null | wc -l)
    count_ipad=$(find "$MODELS/ipadapter" -type f -name "*.safetensors" 2>/dev/null | wc -l)
    count_up=$(find "$MODELS/upscale_models" -type f 2>/dev/null | wc -l)
    count_face=$(find "$MODELS/insightface" "$MODELS/facerestore" "$MODELS/facexlib" -type f 2>/dev/null | wc -l)
    count_diff=$(find "$MODELS/diffusion_models" -type f 2>/dev/null | wc -l)

    total_size=$(du -sh "$MODELS" 2>/dev/null | cut -f1)
    ok_count=$(grep -c "| OK |" "$LOG_FILE" 2>/dev/null) || ok_count=0
    skip_count=$(grep -c "| SKIP |" "$LOG_FILE" 2>/dev/null) || skip_count=0

    echo -e "${BLUE}📁 Checkpoints:${NC} $count_ckpt"
    echo -e "${BLUE}🎮 ControlNet:${NC} $count_ctrl"
    echo -e "${BLUE}🎨 LoRAs:${NC} $count_lora"
    echo -e "${BLUE}📐 VAE:${NC} $count_vae"
    echo -e "${BLUE}👁️ CLIP Vision:${NC} $count_clip"
    echo -e "${BLUE}🧩 IP-Adapter:${NC} $count_ipad"
    echo -e "${BLUE}🔍 Upscale:${NC} $count_up"
    echo -e "${BLUE}🙂 Face (insightface/facerestore/facexlib):${NC} $count_face"
    echo -e "${BLUE}🌀 Diffusion Models:${NC} $count_diff"
    echo -e "${GREEN}💾 Tổng dung lượng:${NC} $total_size"
    echo -e "${GREEN}📥 Tải mới thành công:${NC} $ok_count  ${CYAN}⏩ Bỏ qua (đã có sẵn):${NC} $skip_count  ${BLUE}(tổng $TOTAL model)${NC}"

    fail_count=$(grep -c "FAIL" "$LOG_FILE" 2>/dev/null) || fail_count=0
    if [ "$fail_count" -gt 0 ]; then
        echo -e "${RED}⚠️  Có $fail_count lần tải thất bại. Xem log: $LOG_FILE${NC}"
    else
        echo -e "${GREEN}✅ Tất cả các file tải thành công!${NC}"
    fi

    echo -e "\n${YELLOW}🔄 Hãy khởi động lại ComfyUI hoặc bấm Refresh.${NC}"
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════════${NC}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_stage_05 "$@"
fi
