#!/bin/bash
# Stage 06: Cài rclone & Thiết lập tự động sync ảnh sang Google Drive

run_stage_06() {
    local comfy_base="${COMFY_BASE:-}"
    local output_dir="$comfy_base/output"
    local gdrive_remote="${GDRIVE_REMOTE:-gdrive}"
    local gdrive_folder="${GDRIVE_FOLDER:-ComfyUI_Output}"
    local rclone_conf="${RCLONE_CONFIG_PATH:-$HOME/.config/rclone/rclone.conf}"

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}📤 Stage 06: Tự Động Lưu Ảnh Vào Google Drive${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Skip nếu không bật
    if [ "${ENABLE_GDRIVE:-0}" != "1" ]; then
        echo -e "${YELLOW}⏭️  Bỏ qua Google Drive Sync (thêm --gdrive để bật).${NC}"
        return 0
    fi

    mkdir -p "$output_dir" 2>/dev/null || true

    # 1. Cài rclone nếu chưa có
    if ! command -v rclone &>/dev/null; then
        echo -e "${YELLOW}📦 Đang cài rclone...${NC}"
        curl -fsSL https://rclone.org/install.sh | bash 2>/dev/null || \
        apt-get install -y rclone 2>/dev/null || {
            echo -e "${RED}❌ Không thể cài rclone. Bỏ qua sync Google Drive.${NC}"
            return 0
        }
        echo -e "${GREEN}✅ rclone đã cài xong!${NC}"
    else
        echo -e "${GREEN}✅ rclone đã có sẵn ($(rclone --version | head -1))${NC}"
    fi

    # 2. Kiểm tra đã cấu hình Google Drive chưa
    if ! rclone listremotes 2>/dev/null | grep -q "^${gdrive_remote}:"; then
        # Thử dùng token từ biến môi trường nếu có (cho CI/CD headless)
        if [ -n "${GDRIVE_TOKEN:-}" ] && [ -n "${GDRIVE_CLIENT_ID:-}" ] && [ -n "${GDRIVE_CLIENT_SECRET:-}" ]; then
            echo -e "${CYAN}🔑 Đang cấu hình Google Drive bằng token từ biến môi trường...${NC}"
            mkdir -p "$(dirname "$rclone_conf")"
            cat >> "$rclone_conf" << RCLONE_CONF
[${gdrive_remote}]
type = drive
client_id = ${GDRIVE_CLIENT_ID}
client_secret = ${GDRIVE_CLIENT_SECRET}
token = ${GDRIVE_TOKEN}
RCLONE_CONF
            echo -e "${GREEN}✅ Đã cấu hình Google Drive tự động!${NC}"
        else
            # Hướng dẫn xác thực thủ công 1 lần
            echo -e ""
            echo -e "${YELLOW}╔══════════════════════════════════════════════════════╗${NC}"
            echo -e "${YELLOW}║   🔐 CẦN XÁC THỰC GOOGLE DRIVE - CHỈ LÀM 1 LẦN!   ║${NC}"
            echo -e "${YELLOW}╚══════════════════════════════════════════════════════╝${NC}"
            echo -e ""
            echo -e "${CYAN}Vì server không có trình duyệt, hãy làm theo 2 bước:${NC}"
            echo -e ""
            echo -e "${WHITE}📌 BƯỚC 1: Cài rclone trên MÁY TÍNH CÁ NHÂN của bạn:${NC}"
            echo -e "   https://rclone.org/downloads/"
            echo -e ""
            echo -e "${WHITE}📌 BƯỚC 2: Chạy lệnh này trên MÁY TÍNH CÁ NHÂN:${NC}"
            echo -e "${GREEN}   rclone authorize \"drive\"${NC}"
            echo -e ""
            echo -e "   → Nó sẽ mở trình duyệt → Đăng nhập Google → Chấp nhận"
            echo -e "   → Copy toàn bộ đoạn JSON token hiện ra"
            echo -e ""
            echo -e "${WHITE}📌 BƯỚC 3: Paste token vào đây, nhấn Enter:${NC}"
            echo -n "   Token JSON: "
            read -r GDRIVE_TOKEN_INPUT

            if [ -n "$GDRIVE_TOKEN_INPUT" ]; then
                mkdir -p "$(dirname "$rclone_conf")"
                cat >> "$rclone_conf" << RCLONE_CONF
[${gdrive_remote}]
type = drive
scope = drive
token = ${GDRIVE_TOKEN_INPUT}
RCLONE_CONF
                echo -e "${GREEN}✅ Đã lưu cấu hình Google Drive thành công!${NC}"
            else
                echo -e "${YELLOW}⚠️  Không nhập token, bỏ qua bước kết nối Google Drive.${NC}"
                echo -e "${CYAN}💡 Bạn có thể chạy lại sau bằng lệnh:${NC} bash install.sh --gdrive"
                return 0
            fi
        fi
    else
        echo -e "${GREEN}✅ Google Drive đã được kết nối (remote: ${gdrive_remote}:)${NC}"
    fi

    # 3. Kiểm tra kết nối Drive hoạt động không
    echo -e "${CYAN}🔍 Kiểm tra kết nối Google Drive...${NC}"
    if ! rclone lsd "${gdrive_remote}:" --max-depth 1 &>/dev/null; then
        echo -e "${RED}❌ Không kết nối được Google Drive. Kiểm tra lại token.${NC}"
        return 0
    fi
    echo -e "${GREEN}✅ Kết nối Google Drive OK!${NC}"

    # 4. Tạo folder đích trên Google Drive
    rclone mkdir "${gdrive_remote}:${gdrive_folder}" 2>/dev/null || true
    echo -e "${GREEN}📁 Thư mục Google Drive: ${gdrive_remote}:${gdrive_folder}${NC}"

    # 5. Dừng tiến trình watcher cũ nếu có
    pkill -f "gdrive_watcher" 2>/dev/null || true
    pkill -f "inotifywait.*output" 2>/dev/null || true
    sleep 1

    # 6. Cài inotify-tools nếu chưa có (để watch thư mục real-time)
    if ! command -v inotifywait &>/dev/null; then
        echo -e "${YELLOW}📦 Đang cài inotify-tools để theo dõi thư mục output...${NC}"
        apt-get install -y inotify-tools 2>/dev/null || true
    fi

    # 7. Tạo watcher script
    local watcher_script="/tmp/gdrive_watcher.sh"
    cat > "$watcher_script" << WATCHER_SCRIPT
#!/bin/bash
OUTPUT_DIR="$output_dir"
GDRIVE_REMOTE="${gdrive_remote}"
GDRIVE_FOLDER="${gdrive_folder}"

echo "[\$(date '+%H:%M:%S')] 👀 Đang theo dõi thư mục output: \$OUTPUT_DIR"

if command -v inotifywait &>/dev/null; then
    # Chế độ real-time: upload ngay khi có ảnh mới
    while true; do
        inotifywait -q -e close_write,moved_to --format '%f' "\$OUTPUT_DIR" 2>/dev/null | while read -r filename; do
            case "\$filename" in
                *.png|*.jpg|*.jpeg|*.webp|*.gif)
                    echo "[\$(date '+%H:%M:%S')] 📤 Đang tải lên Google Drive: \$filename"
                    rclone copy "\$OUTPUT_DIR/\$filename" "\$GDRIVE_REMOTE:\$GDRIVE_FOLDER/" 2>/dev/null && \
                    echo "[\$(date '+%H:%M:%S')] ✅ Đã lưu vào Google Drive: \$GDRIVE_FOLDER/\$filename" || \
                    echo "[\$(date '+%H:%M:%S')] ❌ Lỗi tải lên: \$filename"
                    ;;
            esac
        done
        sleep 1
    done
else
    # Chế độ polling: kiểm tra mỗi 30 giây
    while true; do
        rclone copy "\$OUTPUT_DIR" "\$GDRIVE_REMOTE:\$GDRIVE_FOLDER/" \
            --include "*.{png,jpg,jpeg,webp}" \
            --no-update-modtime 2>/dev/null
        sleep 30
    done
fi
WATCHER_SCRIPT
    chmod +x "$watcher_script"

    # 8. Khởi chạy watcher trong nền
    nohup bash "$watcher_script" > /tmp/gdrive_watcher.log 2>&1 &
    local watcher_pid=$!
    echo "$watcher_pid" > /tmp/gdrive_watcher.pid

    echo -e ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   🎉 TỰ ĐỘNG SYNC ẢNH SANG GOOGLE DRIVE BẬT RỒI!  ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo -e "${WHITE}   📁 Ảnh được tạo sẽ tự động lưu vào:${NC}"
    echo -e "      Google Drive → ${gdrive_folder}/"
    echo -e "${CYAN}   📋 Xem log sync:${NC} tail -f /tmp/gdrive_watcher.log"
    echo -e "${CYAN}   🛑 Dừng sync:${NC}   kill \$(cat /tmp/gdrive_watcher.pid)"
    echo -e ""
}
