#!/bin/bash
# ================================================================================================================================
# SCRIPT TỰ ĐỘNG QUÉT VÀ SỬA LỖI CHO TẤT CẢ CUSTOM NODES CỦA COMFYUI
# ================================================================================================================================

set -euo pipefail
export LC_ALL=C

# Import thư viện dùng chung nếu có
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/scripts/common.sh" ]; then
    source "$SCRIPT_DIR/scripts/common.sh"
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Standalone Python dependency analyzer using non-executing importlib.util.find_spec across all node .py files
scan_node_dependencies() {
    local node_dir="$1"

    python3 - "$node_dir" <<'PY_SCAN_DEPS'
import sys, os, ast, importlib.util

node_dir = os.path.abspath(sys.argv[1])
modules_needed = set()

PKG_MAP = {
    'cv2': 'opencv-python',
    'PIL': 'Pillow',
    'skimage': 'scikit-image',
    'yaml': 'pyyaml',
    'scipy': 'scipy',
    'onnxruntime': 'onnxruntime',
    'numpy': 'numpy',
    'timm': 'timm',
    'einops': 'einops',
    'transformers': 'transformers',
    'safetensors': 'safetensors',
    'accelerate': 'accelerate',
    'kornia': 'kornia',
    'torchvision': 'torchvision',
    'torchaudio': 'torchaudio'
}

# Scan all python files in the node directory
for root, dirs, files in os.walk(node_dir):
    # Ignore git and cache dirs
    dirs[:] = [d for d in dirs if d not in {'.git', '__pycache__', 'venv', '.venv'}]
    for f in files:
        if f.endswith('.py'):
            fpath = os.path.join(root, f)
            try:
                with open(fpath, 'r', encoding='utf-8', errors='ignore') as py_f:
                    tree = ast.parse(py_f.read(), filename=fpath)
                for node in ast.walk(tree):
                    if isinstance(node, ast.Import):
                        for alias in node.names:
                            modules_needed.add(alias.name.split('.')[0])
                    elif isinstance(node, ast.ImportFrom):
                        if node.module:
                            modules_needed.add(node.module.split('.')[0])
            except Exception:
                pass

missing_pkgs = []
unresolved = []

for mod in sorted(modules_needed):
    if not mod or mod in sys.builtin_module_names:
        continue
    # Ignore local files/subpackages in the node directory
    if os.path.exists(os.path.join(node_dir, mod + '.py')) or os.path.isdir(os.path.join(node_dir, mod)):
        continue
    # Non-executing module resolution
    try:
        spec = importlib.util.find_spec(mod)
        if spec is None:
            if mod in PKG_MAP:
                missing_pkgs.append(PKG_MAP[mod])
            else:
                unresolved.append(mod)
    except Exception:
        if mod in PKG_MAP:
            missing_pkgs.append(PKG_MAP[mod])
        else:
            unresolved.append(mod)

out = []
if missing_pkgs:
    out.append('MISSING_PKGS:' + ','.join(sorted(set(missing_pkgs))))
if unresolved:
    out.append('UNRESOLVED:' + ','.join(sorted(set(unresolved))))

if out:
    print(' | '.join(out))
else:
    print('OK')
PY_SCAN_DEPS
}

export -f scan_node_dependencies 2>/dev/null || true

fix_custom_nodes() {
    if declare -f init_runtime_env >/dev/null 2>&1; then
        init_runtime_env || true
    fi

    local custom_nodes_dir="${CUSTOM_NODES:-${COMFY_BASE:-}/custom_nodes}"

    if [ ! -d "$custom_nodes_dir" ]; then
        echo -e "${RED}❌ Thư mục custom_nodes không tồn tại: $custom_nodes_dir${NC}"
        return 1
    fi

    echo -e "\n${MAGENTA}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}🛠️  Bắt đầu quét và tự động sửa lỗi cho tất cả Custom Nodes...${NC}"
    echo -e "${MAGENTA}📂 Thư mục: $custom_nodes_dir${NC}"
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════════${NC}\n"

    local total_nodes=0
    local fixed_nodes=0
    local unresolved_nodes=0
    local failed_nodes=0
    local unresolved_list=()
    local failed_list=()

    for node_dir in "$custom_nodes_dir"/*; do
        [ ! -d "$node_dir" ] && continue
        local node_name
        node_name=$(basename "$node_dir")
        total_nodes=$((total_nodes + 1))

        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}🔍 [${total_nodes}] Đang kiểm tra Node:${NC} ${GREEN}$node_name${NC}"

        local node_has_failure=0
        local node_has_unresolved=0

        # ── 1. Cài requirements.txt nếu có ───────────────────────────────────
        if [ -f "$node_dir/requirements.txt" ]; then
            echo -e "   ${CYAN}📄 Tìm thấy requirements.txt - Đang kiểm tra & cài đặt...${NC}"
            if [ "${DRY_RUN:-0}" = "1" ]; then
                echo -e "   ${GREEN}🧪 [DRY_RUN] Bỏ qua cài requirements.txt${NC}"
            else
                local pip_log
                pip_log=$(mktemp 2>/dev/null || echo "/tmp/pip_fix_$$.log")

                if $PIP_BASE_CMD install -r "$node_dir/requirements.txt" \
                    $PIP_SSL_OPT \
                    --break-system-packages \
                    --quiet \
                    2>&1 | tee "$pip_log" >/dev/null \
                   || $PIP_BASE_CMD install -r "$node_dir/requirements.txt" \
                    $PIP_SSL_OPT \
                    --quiet \
                    2>&1 | tee "$pip_log" >/dev/null; then
                    echo -e "   ${GREEN}✅ Cài requirements.txt thành công${NC}"
                else
                    echo -e "   ${RED}❌ Lỗi cài đặt requirements.txt${NC}"
                    node_has_failure=1
                fi
                rm -f "$pip_log"
            fi
        fi

        # ── 2. Cài pyproject.toml / setup.py nếu có (Kiểm tra exit code thật) ──
        if [ -f "$node_dir/pyproject.toml" ] || [ -f "$node_dir/setup.py" ]; then
            echo -e "   ${CYAN}📦 Tìm thấy pyproject.toml/setup.py - Đang cài editable...${NC}"
            if [ "${DRY_RUN:-0}" != "1" ]; then
                if $PIP_BASE_CMD install -e "$node_dir" \
                    $PIP_SSL_OPT \
                    --break-system-packages \
                    --quiet \
                    2>/dev/null \
                   || $PIP_BASE_CMD install -e "$node_dir" \
                    $PIP_SSL_OPT \
                    --quiet \
                    2>/dev/null; then
                    echo -e "   ${GREEN}✅ Cài editable package xong${NC}"
                else
                    echo -e "   ${RED}❌ Lỗi cài đặt editable package setup.py/pyproject.toml${NC}"
                    node_has_failure=1
                fi
            fi
        fi

        # ── 3. Quét static AST dependencies trên toàn bộ file python của node ──
        echo -ne "   ${CYAN}🐍 Phân tích imports qua AST & find_spec...${NC} "
        local scan_out
        scan_out=$(scan_node_dependencies "$node_dir")

        if [[ "$scan_out" == *"UNRESOLVED:"* ]]; then
            local unres
            unres=$(echo "$scan_out" | grep -oP "UNRESOLVED:\K[^|]+" | xargs)
            echo -e "${YELLOW}⚠️ Module chưa rõ nguồn gốc (bỏ qua không blind install): $unres${NC}"
            node_has_unresolved=1
        fi

        if [[ "$scan_out" == *"MISSING_PKGS:"* ]]; then
            local missing_pkgs
            missing_pkgs=$(echo "$scan_out" | grep -oP "MISSING_PKGS:\K[^|]+" | xargs)
            echo -e "${YELLOW}🔧 Thiếu package đã biết: $missing_pkgs${NC}"

            IFS=',' read -ra PKG_ARR <<< "$missing_pkgs"
            for pkg_name in "${PKG_ARR[@]}"; do
                pkg_name="$(echo -n "$pkg_name" | xargs)"
                [ -z "$pkg_name" ] && continue

                if [[ ! "$pkg_name" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
                    echo -e "${RED}❌ Tên package không hợp lệ: '$pkg_name'${NC}"
                    node_has_failure=1
                    continue
                fi

                echo -ne "   ${YELLOW}🔧 Đang cài đặt '$pkg_name'...${NC} "
                if [ "${DRY_RUN:-0}" != "1" ]; then
                    if "$PYTHON_CMD" -m pip install "$pkg_name" \
                        $PIP_SSL_OPT \
                        --break-system-packages \
                        --quiet \
                        2>/dev/null \
                       || "$PYTHON_CMD" -m pip install "$pkg_name" \
                        $PIP_SSL_OPT \
                        --quiet \
                        2>/dev/null; then
                        echo -e "${GREEN}✅ OK${NC}"
                    else
                        echo -e "${RED}❌ Lỗi cài $pkg_name${NC}"
                        node_has_failure=1
                    fi
                fi
            done
        else
            if [ $node_has_unresolved -eq 0 ]; then
                echo -e "${GREEN}✅ OK${NC}"
            fi
        fi

        # ── 4. Thống kê kết quả phân loại ────────────────────────────────────
        if [ $node_has_failure -eq 1 ]; then
            failed_nodes=$((failed_nodes + 1))
            failed_list+=("$node_name")
        elif [ $node_has_unresolved -eq 1 ]; then
            unresolved_nodes=$((unresolved_nodes + 1))
            unresolved_list+=("$node_name")
        else
            fixed_nodes=$((fixed_nodes + 1))
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
    echo -e "${MAGENTA}║${NC}  ✅ Hoạt động hoàn chỉnh  : ${GREEN}${fixed_nodes}${NC}"
    echo -e "${MAGENTA}║${NC}  ⚠️  Chứa module chưa rõ   : ${YELLOW}${unresolved_nodes}${NC}"
    echo -e "${MAGENTA}║${NC}  ❌ Cài đặt thất bại      : ${RED}${failed_nodes}${NC}"

    if [ ${#unresolved_list[@]} -gt 0 ]; then
        echo -e "${MAGENTA}╠══════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${MAGENTA}║${NC}  ${YELLOW}⚠️  Node có unresolved imports (cần cài thủ công nếu cần):${NC}"
        for un in "${unresolved_list[@]}"; do
            echo -e "${MAGENTA}║${NC}     ${YELLOW}• $un${NC}"
        done
    fi

    if [ ${#failed_list[@]} -gt 0 ]; then
        echo -e "${MAGENTA}╠══════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${MAGENTA}║${NC}  ${RED}❌ Node cài đặt thất bại:${NC}"
        for fn in "${failed_list[@]}"; do
            echo -e "${MAGENTA}║${NC}     ${RED}• $fn${NC}"
        done
    fi

    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════╝${NC}\n"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    fix_custom_nodes "$@"
fi
