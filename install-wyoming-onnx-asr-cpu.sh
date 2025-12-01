#!/bin/bash
# Script to install wyoming-onnx-asr as a systemd service on Debian 12 LXC

# --- 1. CONFIGURATION ---
# IMPORTANT: Adjust these variables according to your desired model and hardware.
# You must set a valid model and language for the service to function.
REPO_URL="https://github.com/tboby/wyoming-onnx-asr.git"
INSTALL_DIR="/opt/wyoming-onnx-asr"
SERVICE_USER="wyoming-asr"
SERVICE_PORT="10400"
SERVICE_NAME="wyoming-onnx-asr"

# Environment Variables (SET THESE!)
# Example: ONNX_ASR_MODEL="onnx-community/whisper-tiny.en"
ONNX_ASR_MODEL="REPLACE_ME_WITH_YOUR_MODEL"
ONNX_ASR_LANGUAGE="REPLACE_ME_WITH_YOUR_LANGUAGE"
ONNX_ASR_PROVIDER="CPUExecutionProvider" # Use "CUDAExecutionProvider" if you have GPU support in the LXC

# --- 2. PREREQUISITES & SYSTEM SETUP ---
echo "--- Step 1: Updating system and installing prerequisites ---"
if [ "$(whoami)" != "root" ]; then
  echo "Error: This script must be run as root (use sudo)."
  exit 1
fi

apt update && apt install -y git python3 python3-venv

# Create a dedicated system user (no login shell, no home directory)
if ! id "${SERVICE_USER}" &>/dev/null; then
    echo "Creating service user: ${SERVICE_USER}"
    useradd --system --no-create-home "${SERVICE_USER}"
fi

# Create installation directory
mkdir -p "${INSTALL_DIR}"
chown -R "${SERVICE_USER}":"${SERVICE_USER}" "${INSTALL_DIR}"

# --- 3. INSTALLATION ---
echo "--- Step 2: Cloning repository and installing dependencies ---"
cd /tmp
if [ -d "${INSTALL_DIR}" ]; then
  echo "Installation directory ${INSTALL_DIR} already exists. Removing and cloning again..."
  rm -rf "${INSTALL_DIR}"
fi

git clone "${REPO_URL}" "${INSTALL_DIR}"
chown -R "${SERVICE_USER}":"${SERVICE_USER}" "${INSTALL_DIR}"
cd "${INSTALL_DIR}"

# Create and activate Python Virtual Environment
echo "Creating Python Virtual Environment..."
python3 -m venv .venv

# Install dependencies from requirements.txt
echo "Installing Python dependencies (This may take a few minutes)..."
# We run this as the service user to ensure correct permissions for model downloads
sudo -u "${SERVICE_USER}" ./.venv/bin/pip install --upgrade pip
sudo -u "${SERVICE_USER}" ./.venv/bin/pip install --no-cache-dir -r requirements.txt

# --- 4. SYSTEMD SERVICE SETUP ---
echo "--- Step 3: Creating systemd service file ---"

SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

cat <<EOF > ${SERVICE_FILE}
[Unit]
Description=Wyoming ONNX ASR Service
After=network.target

[Service]
# Run as the dedicated service user
User=${SERVICE_USER}
Group=${SERVICE_USER}

# Working directory where the package expects files
WorkingDirectory=${INSTALL_DIR}

# Map environment variables from compose.yaml
Environment="ONNX_ASR_MODEL=${ONNX_ASR_MODEL}"
Environment="ONNX_ASR_LANGUAGE=${ONNX_ASR_LANGUAGE}"
Environment="ONNX_ASR_PROVIDER=${ONNX_ASR_PROVIDER}"

# Use the command from the Dockerfile, binding to all interfaces (0.0.0.0)
ExecStart=${INSTALL_DIR}/.venv/bin/wyoming-onnx-asr --uri "tcp://0.0.0.0:${SERVICE_PORT}"

# Restart options
Restart=always
RestartSec=5s

# Standard output and error logging
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# --- 5. START SERVICE ---
echo "--- Step 4: Enabling and starting the service ---"

if [[ "${ONNX_ASR_MODEL}" == "REPLACE_ME_WITH_YOUR_MODEL" ]]; then
    echo ""
    echo "=========================================================================================="
    echo "⚠️ WARNING: Service not started!"
    echo "Please edit the script, replace 'REPLACE_ME_WITH_YOUR_MODEL' and 'REPLACE_ME_WITH_YOUR_LANGUAGE' "
    echo "with valid values (e.g., 'onnx-community/whisper-tiny.en' and 'en'), then rerun this script."
    echo "The service file is created at: ${SERVICE_FILE}"
    echo "=========================================================================================="
else
    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}"
    systemctl start "${SERVICE_NAME}"
    echo ""
    echo "✅ Success! The ${SERVICE_NAME} service is installed and running."
    echo "   - Status: systemctl status ${SERVICE_NAME}"
    echo "   - Logs: journalctl -u ${SERVICE_NAME}"
    echo "   - Access URI (if exposed): tcp://<LXC_IP>:${SERVICE_PORT}"

    # Model Download Test (runs once to trigger the model download)
    echo "Attempting to trigger model download for the first time..."
    sudo -u "${SERVICE_USER}" ${INSTALL_DIR}/.venv/bin/wyoming-onnx-asr --uri 'tcp://127.0.0.1:1' --model "${ONNX_ASR_MODEL}" --language "${ONNX_ASR_LANGUAGE}" --provider "${ONNX_ASR_PROVIDER}" --max-sentences 1 --max-read-size 1 > /dev/null 2>&1
    echo "Model download attempt finished. The service is already running and should now be initialized."
fi
