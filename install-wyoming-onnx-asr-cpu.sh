#!/bin/bash
# Description: Installs wyoming-onnx-asr as a systemd service using CPU.
# Target OS: Debian 12 (Proxmox LXC)

# --- CONFIGURATION ---
REPO_URL="https://github.com/tboby/wyoming-onnx-asr.git"
INSTALL_DIR="/opt/wyoming-onnx-asr"
SERVICE_USER="wyoming-asr"
SERVICE_PORT="10400"
SERVICE_NAME="wyoming-onnx-asr"

# Environment Variables for CPU deployment
ONNX_ASR_MODEL="nemo-parakeet-tdt-0.6b-v2"       
ONNX_ASR_LANGUAGE="en"
ONNX_ASR_PROVIDER="CPUExecutionProvider"

# --- PRE-REQUISITES & SYSTEM SETUP ---
echo "--- Step 1: Updating system and installing prerequisites ---"
if [ "$(id -u)" -ne 0 ]; then
  echo "Error: This script must be run as root (use sudo)."
  exit 1
fi

# Install core packages: git, python3, venv
apt update && apt install -y git python3 python3-venv

# Create dedicated service user and installation directory
if ! id "${SERVICE_USER}" &>/dev/null; then
    echo "Creating service user: ${SERVICE_USER}"
    useradd --system --no-create-home "${SERVICE_USER}"
fi
mkdir -p "${INSTALL_DIR}"
chown -R "${SERVICE_USER}":"${SERVICE_USER}" "${INSTALL_DIR}"

# --- INSTALLATION ---
echo "--- Step 2: Cloning repository and installing dependencies ---"
git clone "${REPO_URL}" "${INSTALL_DIR}"
cd "${INSTALL_DIR}"

# Create and populate Python Virtual Environment
sudo -u "${SERVICE_USER}" python3 -m venv .venv
echo "Installing Python dependencies..."
sudo -u "${SERVICE_USER}" ./.venv/bin/pip install --upgrade pip
sudo -u "${SERVICE_USER}" ./.venv/bin/pip install --no-cache-dir -r requirements.txt

# --- SYSTEMD SERVICE SETUP ---
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
Environment="ONNX_ASR_MODEL=${ONNX_ASR_MODEL}"
Environment="ONNX_ASR_LANGUAGE=${ONNX_ASR_LANGUAGE}"
Environment="ONNX_ASR_PROVIDER=${ONNX_ASR_PROVIDER}"
ExecStart=${INSTALL_DIR}/.venv/bin/wyoming-onnx-asr --uri "tcp://0.0.0.0:${SERVICE_PORT}"
Restart=always
RestartSec=5

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# --- START SERVICE ---
echo "--- Step 4: Enabling and starting the service ---"
if [[ "${ONNX_ASR_MODEL}" == "REPLACE_ME_WITH_YOUR_MODEL" ]]; then
    echo "⚠️ WARNING: Service file created, but not started. Please configure variables."
else
    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}"
    systemctl start "${SERVICE_NAME}"
    echo "✅ Success! Service ${SERVICE_NAME} (CPU) is running."
fi
