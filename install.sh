#!/bin/bash
set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/scripts/common.sh"
source "$SCRIPT_DIR/scripts/01_env_setup.sh"
source "$SCRIPT_DIR/scripts/02_comfy_core.sh"
source "$SCRIPT_DIR/scripts/03_nodes_setup.sh"
source "$SCRIPT_DIR/scripts/04_models_dl.sh"
source "$SCRIPT_DIR/scripts/05_manifest.sh"

main() {
    run_stage_01 "$@"
    run_stage_02 "$@"
    run_stage_03 "$@"
    run_stage_04 "$@"
    run_stage_05 "$@"
}

main "$@"
