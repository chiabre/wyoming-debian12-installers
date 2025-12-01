#!/bin/bash
# Description: Installs wyoming-onnx-asr as a systemd service using CPU on Debian 12 LXC.
# Target OS: Debian 12 (Proxmox LXC)

# --- CONFIGURATION ---
REPO_URL="https://github.com/tboby/wyoming-onnx-asr.git"
INSTALL_DIR="/opt/wyoming-onnx-asr"
SERVICE_USER="wyoming-asr"
SERVICE_PORT="10400"
SERVICE_NAME="wyoming-onnx-asr"
EXECUTABLE_NAME="wyoming-nemo-asr" 

# Environment Variables for CPU deployment
ONNX_ASR_MODEL="nemo-parakeet-tdt-0.6b-v2" 
# CRITICAL: Set to "en" or "multilingual" to match the program's --model- flag
ONNX_ASR_LANGUAGE="en" 
ONNX_ASR_PROVIDER="CPUExecutionProvider"

# --- Step 1: PRE-REQUISITES & SYSTEM SETUP ---
echo "--- Step 1: Updating system and installing prerequisites ---"

if [ "$(id -u)" -ne 0 ]; then
  echo "Error: This script must be run as root."
  exit 1
fi

# Install core packages: git, python3, venv, and adduser
apt update && apt install -y git python3 python3-venv adduser

# Create dedicated service user with a home directory
if ! id "${SERVICE_USER}" &>/dev/null; then
    echo "Creating service user with home directory: /home/${SERVICE_USER}"
    # FIX: Use adduser to create the user and their home directory for stability
    adduser --system --group --disabled-login "${SERVICE_USER}"
fi

# Create installation directory and set ownership
mkdir -p "${INSTALL_DIR}"
chown -R "${SERVICE_USER}":"${SERVICE_USER}" "${INSTALL_DIR}"

# --- Step 2: INSTALLATION ---
echo "--- Step 2: Cloning repository and installing dependencies ---"
git clone "${REPO_URL}" "${INSTALL_DIR}"
chown -R "${SERVICE_USER}":"${SERVICE_USER}" "${INSTALL_DIR}" 

# Create dedicated cache directories for PIP and Hugging Face (HF)
PIP_CACHE_DIR="${INSTALL_DIR}/.pip_cache"
HF_HOME_DIR="${INSTALL_DIR}/.hf_cache"

mkdir -p "${PIP_CACHE_DIR}" "${HF_HOME_DIR}"
chown -R "${SERVICE_USER}":"${SERVICE_USER}" "${PIP_CACHE_DIR}" "${HF_HOME_DIR}"

# Execute VENV setup and package installation commands using 'su'
echo "Creating VENV and installing Python dependencies under user ${SERVICE_USER}..."

# FIX: Explicitly use --cache-dir to suppress the PIP warning, even though the user has a home.
su - "${SERVICE_USER}" -c "
  cd ${INSTALL_DIR} &&
  python3 -m venv .venv &&
  ./.venv/bin/pip install --upgrade pip --cache-dir ${PIP_CACHE_DIR} &&
  # Explicitly install the core dependency (onnxruntime)
  ./.venv/bin/pip install --no-cache-dir onnxruntime --cache-dir ${PIP_CACHE_DIR} &&
  # Install the main package from source ('.')
  ./.venv/bin/pip install --no-cache-dir . --cache-dir ${PIP_CACHE_DIR}
"

# --- Dynamic Model Argument Generation ---
echo "--- Dynamic Argument Generation ---"
# FIX: Dynamically construct the correct command-line flag (--model-en or --model-multilingual)
MODEL_ARGS="--model-${ONNX_ASR_LANGUAGE} \"${ONNX_ASR_MODEL}\""

# --- Step 3: SYSTEMD SERVICE SETUP ---
echo "--- Step 3: Creating systemd service file ---"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

cat <<EOF > ${SERVICE_FILE}
[Unit]
Description=Wyoming ONNX ASR Service (CPU)
After=network.target

[Service]
User=${SERVICE_USER}
Group=${SERVICE_USER}
WorkingDirectory=${INSTALL_DIR}
Environment="ONNX_ASR_PROVIDER=${ONNX_ASR_PROVIDER}"
# FIX: Override Hugging Face cache location to prevent 'Permission denied' errors on model load
Environment="HF_HOME=${HF_HOME_DIR}" 
# FIX: Using the correct executable name and dynamic model arguments
ExecStart=${INSTALL_DIR}/.venv/bin/${EXECUTABLE_NAME} ${MODEL_ARGS} --uri "tcp://0.0.0.0:${SERVICE_PORT}"
Restart=always
RestartSec=5

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# --- Step 4: START SERVICE & VERIFICATION ---
echo "--- Step 4: Enabling, and starting the service ---"

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"
systemctl start "${SERVICE_NAME}"

echo "To check the service status and troubleshoot, use the command below:"
echo "journalctl -u ${SERVICE_NAME} --since '1 minute ago' -e"
