#!/bin/bash

run_stage_05() {
    init_runtime_env || return 1

    END_TIME=$(date +%s)
    ELAPSED_SEC=$((END_TIME - START_TIME))
    
    local hours=$((ELAPSED_SEC / 3600))
    local minutes=$(( (ELAPSED_SEC % 3600) / 60 ))
    local seconds=$((ELAPSED_SEC % 60))
    
    local time_str=""
    [ $hours -gt 0 ] && time_str="${hours}h "
    time_str="${time_str}${minutes}m ${seconds}s"

    echo -e "\n${BLUE}📝 Stage 05: Tổng hợp Manifest & Tạo Báo Cáo Tối Ưu Tải Xuống...${NC}"
    export COMFY_BASE TOTAL MANIFEST_FILE LOG_FILE REPORT_FILE REPORT_JSON ELAPSED_SEC TIME_STR DRY_RUN

    "$PYTHON_CMD" - "$MANIFEST_FILE" "$REPORT_FILE" "$REPORT_JSON" "${AUTO_INSTALLED_TOOLS[*]}" <<'PY'
import json
import os
import sys
import datetime
import subprocess

manifest_path = sys.argv[1]
report_md_path = sys.argv[2]
report_json_path = sys.argv[3]
auto_tools = sys.argv[4].strip()

comfy_base = os.environ.get("COMFY_BASE", "")
log_file = os.environ.get("LOG_FILE", "")
elapsed_sec = int(os.environ.get("ELAPSED_SEC", "0"))
time_str = os.environ.get("TIME_STR", "0s")
dry_run = os.environ.get("DRY_RUN", "0") == "1"

# Parse log file for exact statistics
ok_primary = []
ok_mirror = []
skipped = []
failed = []

if os.path.exists(log_file):
    with open(log_file, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            parts = [p.strip() for p in line.split("|")]
            if len(parts) >= 3:
                level = parts[1]
                data = parts[2:]
                if level == "OK_PRIMARY":
                    ok_primary.append(data)
                elif level == "OK_MIRROR":
                    ok_mirror.append(data)
                elif level == "SKIP":
                    skipped.append(data)
                elif level == "FAIL":
                    failed.append(data)

total_processed = len(ok_primary) + len(ok_mirror) + len(skipped) + len(failed)
downloaded_total = len(ok_primary) + len(ok_mirror) + len(failed)

error_rate = 0.0
if downloaded_total > 0:
    error_rate = round((len(failed) / downloaded_total) * 100, 2)
elif total_processed > 0 and len(failed) > 0:
    error_rate = round((len(failed) / total_processed) * 100, 2)

# Build JSON report
report_data = {
    "timestamp": datetime.datetime.now().isoformat(),
    "comfy_base": comfy_base,
    "total_execution_time": time_str,
    "elapsed_seconds": elapsed_sec,
    "metrics": {
        "total_files": total_processed,
        "primary_success_count": len(ok_primary),
        "mirror_success_count": len(ok_mirror),
        "skipped_count": len(skipped),
        "failed_count": len(failed),
        "error_rate_percent": error_rate
    },
    "auto_installed_tools": auto_tools.split() if auto_tools else [],
    "mirror_downloads": [],
    "failed_downloads": []
}

for item in ok_mirror:
    # item: description, output_path, mirror_url, size
    desc = item[0] if len(item) > 0 else "N/A"
    path = item[1] if len(item) > 1 else "N/A"
    mirror_url = item[2] if len(item) > 2 else "N/A"
    size = item[3] if len(item) > 3 else "N/A"
    report_data["mirror_downloads"].append({
        "description": desc,
        "path": path,
        "mirror_url": mirror_url,
        "size": size
    })

for item in failed:
    desc = item[0] if len(item) > 0 else "N/A"
    path = item[1] if len(item) > 1 else "N/A"
    primary_url = item[2] if len(item) > 2 else "N/A"
    report_data["failed_downloads"].append({
        "description": desc,
        "path": path,
        "primary_url": primary_url,
        "reason": "Mọi link chính và link phụ đều không thể tải"
    })

# Save JSON report
with open(report_json_path, "w", encoding="utf-8") as f:
    json.dump(report_data, f, indent=2, ensure_ascii=False)

# Save JSON manifest
manifest_data = {
    "timestamp": report_data["timestamp"],
    "comfyui_base": comfy_base,
    "total_models": total_processed,
    "models": report_data
}
with open(manifest_path, "w", encoding="utf-8") as f:
    json.dump(manifest_data, f, indent=2, ensure_ascii=False)

# Generate Markdown Report File
with open(report_md_path, "w", encoding="utf-8") as f:
    f.write(f"# 📊 BÁO CÁO TỐI ƯU CHI TIẾT TẢI XUỐNG COMFYUI\n\n")
    f.write(f"- **Thời gian thực hiện**: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
    f.write(f"- **Thư mục ComfyUI**: `{comfy_base}`\n")
    f.write(f"- **⏱️ Tổng thời gian tốn**: `{time_str}` ({elapsed_sec}s)\n")
    f.write(f"- **🔴 Tỷ lệ sai số / lỗi (Error Rate)**: `{error_rate}%`\n\n")

    f.write(f"## 📈 THỐNG KÊ TỔNG QUAN\n\n")
    f.write(f"| Chỉ số | Số lượng |\n")
    f.write(f"|---|---|\n")
    f.write(f"| 📦 Tổng số file xử lý | **{total_processed}** |\n")
    f.write(f"| 🌐 Thành công (Link Chính) | **{len(ok_primary)}** |\n")
    f.write(f"| ✨ Thành công (Link Phụ / Mirror) | **{len(ok_mirror)}** |\n")
    f.write(f"| ⏩ Bỏ qua (Đã tồn tại) | **{len(skipped)}** |\n")
    f.write(f"| ❌ Tải thất bại | **{len(failed)}** |\n")
    f.write(f"| 🔴 Tỷ lệ Lỗi (Error Rate) | **{error_rate}%** |\n\n")

    if auto_tools:
        f.write(f"## 🛠️ CÔNG CỤ TỰ ĐỘNG BỔ SUNG\n")
        f.write(f"Hệ thống đã tự động cài đặt các công cụ còn thiếu: `{auto_tools}`\n\n")

    f.write(f"## ✨ DANH SÁCH FILE ĐÃ TẢI QUA LINK PHỤ (MIRROR)\n\n")
    if ok_mirror:
        f.write(f"| Tên File / Description | Đường dẫn lưu | Link phụ đã dùng | Dung lượng |\n")
        f.write(f"|---|---|---|---|\n")
        for m in report_data["mirror_downloads"]:
            f.write(f"| {m['description']} | `{m['path']}` | `{m['mirror_url']}` | {m['size']} |\n")
    else:
        f.write(f"*Không có file nào phải dùng link phụ (tất cả link chính đều hoạt động tốt).* \n")
    f.write("\n")

    f.write(f"## ❌ DANH SÁCH FILE TẢI LỖI (FAILED)\n\n")
    if failed:
        f.write(f"| Tên File / Description | Đường dẫn lưu | Link chính | Ghi chú lỗi |\n")
        f.write(f"|---|---|---|---|\n")
        for fl in report_data["failed_downloads"]:
            f.write(f"| {fl['description']} | `{fl['path']}` | `{fl['primary_url']}` | {fl['reason']} |\n")
    else:
        f.write(f"✅ **Không có file nào bị lỗi!** Tất cả các file đã được tải thành công.\n")

PY

    # Print Visual Terminal Report
    echo -e "\n${MAGENTA}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}📊 BÁO CÁO TỐI ƯU CHI TIẾT SAI SỐ VÀ THỜI GIAN TẢI XUỐNG${NC}"
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════════${NC}"

    local ok_p
    local ok_m
    local skp
    local fls
    ok_p=$(grep -c "| OK_PRIMARY |" "$LOG_FILE" 2>/dev/null) || ok_p=0
    ok_m=$(grep -c "| OK_MIRROR |" "$LOG_FILE" 2>/dev/null) || ok_m=0
    skp=$(grep -c "| SKIP |" "$LOG_FILE" 2>/dev/null) || skp=0
    fls=$(grep -c "| FAIL |" "$LOG_FILE" 2>/dev/null) || fls=0

    local total_count=$((ok_p + ok_m + skp + fls))
    local total_down=$((ok_p + ok_m + fls))
    local err_rate="0.0"

    if [ $total_down -gt 0 ]; then
        err_rate=$(awk -v f="$fls" -v t="$total_down" 'BEGIN {printf "%.2f", (f/t)*100}')
    fi

    echo -e "${BLUE}⏱️  Tổng thời gian tốn:${NC} ${GREEN}$time_str${NC} (${ELAPSED_SEC} giây)"
    echo -e "${BLUE}📁 Tổng số file xử lý:${NC}  $total_count"
    echo -e "${GREEN}🌐 Link Chính thành công:${NC} $ok_p"
    echo -e "${MAGENTA}✨ Link Phụ (Mirror) dùng:${NC} $ok_m"
    echo -e "${CYAN}⏩ Bỏ qua (Đã có sẵn):${NC}    $skp"
    echo -e "${RED}❌ Tải thất bại:${NC}          $fls"
    echo -e "${YELLOW}🔴 Tỷ lệ sai số / lỗi:${NC}   ${RED}${err_rate}%${NC}"

    if [ ${#AUTO_INSTALLED_TOOLS[@]} -gt 0 ]; then
        echo -e "\n${YELLOW}🛠️  Công cụ đã tự động tải bổ sung:${NC} ${AUTO_INSTALLED_TOOLS[*]}"
    fi

    if [ $ok_m -gt 0 ]; then
        echo -e "\n${MAGENTA}✨ DANH SÁCH FILE ĐÃ TẢI BẰNG LINK PHỤ (MIRROR):${NC}"
        grep "| OK_MIRROR |" "$LOG_FILE" 2>/dev/null | while IFS='|' read -r timestamp level content; do
            echo -e "   ${MAGENTA}• ${content}${NC}"
        done
    fi

    if [ $fls -gt 0 ]; then
        echo -e "\n${RED}❌ DANH SÁCH FILE TẢI THẤT BẠI:${NC}"
        grep "| FAIL |" "$LOG_FILE" 2>/dev/null | while IFS='|' read -r timestamp level content; do
            echo -e "   ${RED}• ${content}${NC}"
        done
    else
        echo -e "\n${GREEN}🎉 TẤT CẢ FILE ĐÃ ĐƯỢC TẢI HOÀN HẢO!${NC}"
    fi

    echo -e "\n${BLUE}📄 Báo cáo Markdown chi tiết đã được lưu tại:${NC} $REPORT_FILE"
    echo -e "${BLUE}📄 Báo cáo JSON máy đọc đã được lưu tại:${NC} $REPORT_JSON"
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════════${NC}"
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_stage_05 "$@"
fi
