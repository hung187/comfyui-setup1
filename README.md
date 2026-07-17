# ComfyUI Setup

This repository contains a modular Bash installer for deploying ComfyUI on Google Colab/Ubuntu without using a virtual environment.

## Structure

- scripts/01_env_setup.sh: environment checks, core tools, pip setup, SSL toggle
- scripts/02_comfy_core.sh: token handling and ComfyUI core preparation
- scripts/03_nodes_setup.sh: custom node cloning/pulling from config
- scripts/04_models_dl.sh: model downloads with DRY_RUN and aria2c/wget support
- scripts/05_manifest.sh: manifest generation and reporting
- config/nodes_list.txt: custom node repository list
- config/models_list.csv: model download list

## Usage

```bash
bash install.sh
```

For dry run:

```bash
DRY_RUN=1 bash install.sh
```

For SSL bypass:

```bash
DISABLE_SSL_VERIFY=1 bash install.sh
```
