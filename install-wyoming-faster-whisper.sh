#!/bin/bash
# Description: Non-interactive installer for the Wyoming Faster Whisper Speech-to-Text (STT) service.

# ==============================================================================
#                 --- CONSTANTS (FIXED CONFIGURATION) ---
# ==============================================================================

# Git Repository (Source for configuration files/scripts)
REPO_URL="https://github.com/rhasspy/wyoming-faster-whisper.git"
SERVICE_NAME_BASE="wyoming-faster-whisper"
EXECUTABLE_NAME="wyoming-faster-whisper" 

# --- FIXED DEPLOYMENT RESOURCES ---
INSTALL_DIR="/opt/${SERVICE_NAME_BASE}" # Single installation directory
SERVICE_USER="${SERVICE_NAME_BASE}"      # Dedicated system user
SERVICE_PORT="10300"                     # Standard port for Whisper/STT

# PyPI package name (Confirmed via documentation)
PYTHON_PACKAGE="wyoming-faster-whisper" 

# --- MODEL/LANGUAGE CONFIGURATION ---
# Faster Whisper automatically downloads the model into the data directory.
WHISPER_MODEL="tiny-int8" # Recommended smallest model for testing
WHISPER_LANG="en"         # Default language
DATA_DIR="/opt/faster_whisper_models" # Directory where models will be stored

# Cache Directories (Located within INSTALL_DIR)
PIP_CACHE="${INSTALL_DIR}/.pip_cache"
HF_HOME="${INSTALL_DIR}/.hf_cache"

# Final service name
SERVICE_NAME="${SERVICE_NAME_BASE}" 

echo -e "\n--- Configuration Summary ---"
echo "Model: ${WHISPER_MODEL} (Language: ${WHISPER_LANG})"
echo "Installation Dir: ${INSTALL_DIR}"
echo "Service User: ${SERVICE_USER}"
echo "Service Name: ${SERVICE_NAME} on port **${SERVICE_PORT}**"
echo "Data Dir: ${DATA_DIR}"
echo "---------------------------\n"


# ==============================================================================
#                 --- EXECUTION FLOW ---
# ==============================================================================

set -e

echo "--- Step 1: PRE-REQUISITES & SYSTEM SETUP ---"

if [ "$(id -u)" -ne 0 ]; then
  echo "Must run as root."
  exit 1
fi

# Install core packages
apt update && apt install -y git python3 python3-venv adduser

# --- Step 2: INSTALLATION ---
echo "--- Step 2: Cloning repository and installing dependencies ---"

# 1. Create service user (using the proven adduser logic)
if ! id "$SERVICE_USER" &>/dev/null; then
    echo "Creating service user: $SERVICE_USER"
    adduser --system --group --disabled-login "$SERVICE_USER"
fi

# 2. Clone repository (Enforced clean install for idempotency)
echo "Removing old directory and cloning repository..."
rm -rf "$INSTALL_DIR"
git clone "$REPO_URL" "$INSTALL_DIR"

# 3. Fix ownership for the main installation and data directories
chown -R "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR"
mkdir -p "$DATA_DIR"
chown -R "$SERVICE_USER":"$SERVICE_USER" "$DATA_DIR"

# 4. Create cache directories
echo "Creating cache directories..."
mkdir -p "$PIP_CACHE" "$HF_HOME"
chown -R "$SERVICE_USER":"$SERVICE_USER" "$PIP_CACHE" "$HF_HOME"

# 5. Build virtualenv and install dependencies as service user
echo "Building VENV and installing Python package: $PYTHON_PACKAGE..."
su "$SERVICE_USER" -s /bin/bash -c "
  cd $INSTALL_DIR
  python3 -m venv .venv
  ./.venv/bin/pip install --upgrade pip --cache-dir $PIP_CACHE
  # Install the main package from PyPI
  ./.venv/bin/pip install --no-cache-dir $PYTHON_PACKAGE --cache-dir $PIP_CACHE
"

# --- Step 3: SYSTEMD SERVICE SETUP ---
echo "--- Step 3: Creating systemd service file ($SERVICE_NAME.service) ---"

cat <<EOF >/etc/systemd/system/${SERVICE_NAME}.service
[Unit]
Description=Wyoming Faster Whisper STT Service
After=network.target

[Service]
User=${SERVICE_USER}
Group=${SERVICE_USER}
WorkingDirectory=${INSTALL_DIR}
# HF_HOME is critical here as Whisper models use HuggingFace
Environment="HF_HOME=${HF_HOME}"
ExecStart=${INSTALL_DIR}/.venv/bin/${EXECUTABLE_NAME} \
  --model ${WHISPER_MODEL} \
  --language ${WHISPER_LANG} \
  --data-dir ${DATA_DIR} \
  --uri "tcp://0.0.0.0:${SERVICE_PORT}"
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# --- Step 4: START SERVICE & FINAL INSTRUCTIONS ---
echo "--- Step 4: Enabling, starting, and final instructions ---"

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl start "$SERVICE_NAME"

echo -e "\n--- Installation complete ---"
echo "Service: **${SERVICE_NAME}** installed."
echo "Monitor with: journalctl -u ${SERVICE_NAME} -f"
echo "Wyoming server exposed at: IP:${SERVICE_PORT}"
echo
echo "The service will download the **${WHISPER_MODEL}** model into **${DATA_DIR}** on the first run."
echo "⚠️ Re-running the script overwrites the installation."
