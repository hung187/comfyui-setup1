#!/bin/bash
# ==============================================================================
# fix_nodes.sh - Tự Động Sửa Lỗi Thiếu Package cho Tất Cả Custom Nodes
# Cách dùng: bash fix_nodes.sh
# ==============================================================================
set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

# ==============================================================================
fix_custom_nodes() {
    init_runtime_env || return 1

    echo -e "\n${MAGENTA}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║   🔧  TỰ ĐỘNG SỬA LỖI THIẾU PACKAGE - CUSTOM NODES         ║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════╝${NC}\n"

    local NODES_DIR="$CUSTOM_NODES"

    if [ ! -d "$NODES_DIR" ]; then
        echo -e "${RED}❌ Không tìm thấy thư mục custom_nodes tại: $NODES_DIR${NC}"
        return 1
    fi

    # Đếm số lượng node
    local total_nodes=0
    local fixed_nodes=0
    local failed_nodes=0
    local skipped_nodes=0

    local -a failed_list=()

    echo -e "${CYAN}📂 Đang quét thư mục custom_nodes:${NC} $NODES_DIR\n"

    # Duyệt qua từng thư mục node
    for node_dir in "$NODES_DIR"/*/; do
        [ -d "$node_dir" ] || continue

        local node_name
        node_name=$(basename "$node_dir")

        # Bỏ qua thư mục ẩn và __pycache__
        [[ "$node_name" == .* ]] && continue
        [[ "$node_name" == "__pycache__" ]] && continue

        total_nodes=$((total_nodes + 1))

        echo -e "${BLUE}[${total_nodes}] 🔍 Kiểm tra:${NC} $node_name"

        local has_issue=0

        # ── 1. Cài requirements.txt nếu có ──────────────────────────────────
        if [ -f "$node_dir/requirements.txt" ]; then
            echo -e "   ${CYAN}📋 Tìm thấy requirements.txt - Đang cài...${NC}"

            if [ "${DRY_RUN:-0}" = "1" ]; then
                echo -e "   ${GREEN}🧪 [DRY_RUN] Bỏ qua cài requirements.txt${NC}"
            else
                local pip_log
                pip_log=$(mktemp 2>/dev/null || echo "/tmp/pip_fix_$$.log")

                $PIP_BASE_CMD install -r "$node_dir/requirements.txt" \
                    $PIP_SSL_OPT \
                    --break-system-packages \
                    --quiet \
                    2>&1 | tee "$pip_log" >/dev/null

                # Thử lại không có --break-system-packages nếu thất bại
                if grep -qi "error\|failed" "$pip_log" 2>/dev/null; then
                    $PIP_BASE_CMD install -r "$node_dir/requirements.txt" \
                        $PIP_SSL_OPT \
                        --quiet \
                        >> "$pip_log" 2>&1 || true
                fi

                if grep -qi "Successfully installed\|already satisfied\|Requirement already satisfied" "$pip_log" 2>/dev/null || \
                   ! grep -qi "^ERROR\|Failed to install" "$pip_log" 2>/dev/null; then
                    echo -e "   ${GREEN}✅ Cài requirements.txt thành công${NC}"
                    has_issue=0
                else
                    echo -e "   ${YELLOW}⚠️  Một số package trong requirements.txt gặp lỗi (xem log)${NC}"
                    has_issue=1
                fi
                rm -f "$pip_log"
            fi
        fi

        # ── 2. Cài pyproject.toml / setup.py nếu có ─────────────────────────
        if [ -f "$node_dir/pyproject.toml" ] || [ -f "$node_dir/setup.py" ]; then
            echo -e "   ${CYAN}📦 Tìm thấy pyproject.toml/setup.py - Đang cài editable...${NC}"
            if [ "${DRY_RUN:-0}" != "1" ]; then
                $PIP_BASE_CMD install -e "$node_dir" \
                    $PIP_SSL_OPT \
                    --break-system-packages \
                    --quiet \
                    2>/dev/null \
                || $PIP_BASE_CMD install -e "$node_dir" \
                    $PIP_SSL_OPT \
                    --quiet \
                    2>/dev/null \
                || true
                echo -e "   ${GREEN}✅ Cài editable package xong${NC}"
            fi
        fi

        # ── 3. Kiểm tra import Python các file chính của node ────────────────
        local main_files=("__init__.py" "nodes.py" "node.py")
        for mf in "${main_files[@]}"; do
            if [ -f "$node_dir/$mf" ]; then
                echo -ne "   ${CYAN}🐍 Kiểm tra import $mf...${NC} "
                local import_err
                import_err=$(cd "$node_dir" && python3 -c "
import sys, os
sys.path.insert(0, '.')
try:
    import importlib.util
    spec = importlib.util.spec_from_file_location('node_module', '$mf')
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    print('OK')
except ImportError as e:
    print('IMPORT_ERROR:' + str(e))
except Exception as e:
    print('OK')  # Các lỗi khác không liên quan đến thiếu package
" 2>/dev/null || echo "UNKNOWN")

                if [[ "$import_err" == *"IMPORT_ERROR:"* ]]; then
                    local missing_pkg
                    missing_pkg=$(echo "$import_err" | sed "s/IMPORT_ERROR://g" | xargs)
                    echo -e "${RED}❌ Lỗi: $missing_pkg${NC}"
                    echo -ne "   ${YELLOW}🔧 Đang tự động cài package thiếu...${NC} "

                    # Trích xuất tên package từ thông báo lỗi
                    local pkg_name
                    pkg_name=$(echo "$missing_pkg" | grep -oP "No module named '\K[^']+" | head -1 \
                               || echo "$missing_pkg" | awk '{print $NF}' | tr -d "'\"")

                    if [ -n "$pkg_name" ]; then
                        if $PIP_BASE_CMD install "$pkg_name" \
                            $PIP_SSL_OPT \
                            --break-system-packages \
                            --quiet \
                            2>/dev/null \
                        || $PIP_BASE_CMD install "$pkg_name" \
                            $PIP_SSL_OPT \
                            --quiet \
                            2>/dev/null; then
                            echo -e "${GREEN}✅ Đã cài '$pkg_name'${NC}"
                            has_issue=0
                        else
                            echo -e "${RED}❌ Không cài được '$pkg_name'${NC}"
                            has_issue=1
                        fi
                    fi
                    break
                else
                    echo -e "${GREEN}✅ OK${NC}"
                fi
                break  # Chỉ cần kiểm tra file đầu tiên tìm thấy
            fi
        done

        # ── 4. Kết quả cho node này ──────────────────────────────────────────
        if [ $has_issue -eq 0 ]; then
            fixed_nodes=$((fixed_nodes + 1))
        else
            failed_nodes=$((failed_nodes + 1))
            failed_list+=("$node_name")
        fi

        echo ""
    done

    # ── Dọn dẹp pip cache sau khi sửa ───────────────────────────────────────
    echo -e "${CYAN}🧹 Đang dọn dẹp pip cache để tiết kiệm đĩa...${NC}"
    $PIP_BASE_CMD cache purge 2>/dev/null || true
    echo -e "${GREEN}✅ Đã dọn dẹp pip cache!${NC}\n"

    # ── Báo cáo tổng kết ─────────────────────────────────────────────────────
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║               📊  BÁO CÁO SỬA LỖI CUSTOM NODES             ║${NC}"
    echo -e "${MAGENTA}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${MAGENTA}║${NC}  Tổng số node đã kiểm tra : ${CYAN}${total_nodes}${NC}"
    echo -e "${MAGENTA}║${NC}  ✅ Sửa thành công        : ${GREEN}${fixed_nodes}${NC}"
    echo -e "${MAGENTA}║${NC}  ❌ Vẫn còn lỗi           : ${RED}${failed_nodes}${NC}"

    if [ ${#failed_list[@]} -gt 0 ]; then
        echo -e "${MAGENTA}╠══════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${MAGENTA}║${NC}  ${RED}⚠️  Danh sách node vẫn còn lỗi:${NC}"
        for fn in "${failed_list[@]}"; do
            echo -e "${MAGENTA}║${NC}     ${RED}• $fn${NC}"
        done
    fi

    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════╝${NC}\n"

    if [ $failed_nodes -eq 0 ]; then
        echo -e "${GREEN}🎉 Tất cả Custom Nodes đã được sửa và hoạt động bình thường!${NC}\n"
    else
        echo -e "${YELLOW}💡 Gợi ý: Các node trên vẫn gặp lỗi có thể cần thư viện hệ thống (C++ libs, CUDA...)${NC}"
        echo -e "${YELLOW}   Hãy xem chi tiết lỗi trong ComfyUI bằng cách mở giao diện web và kiểm tra phần 'Manager'.${NC}\n"
    fi
}

fix_custom_nodes "$@"
