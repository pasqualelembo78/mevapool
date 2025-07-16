#!/bin/bash

# Aggiorna sistema e installa pacchetti richiesti
apt update && apt upgrade -y
apt install -y curl git build-essential redis-server ufw

# Installa Node.js LTS (versione stabile raccomandata)
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt install -y nodejs

# Verifica installazione
node -v
npm -v

# Abilita e avvia Redis
systemctl enable redis-server
systemctl start redis-server

# Configura firewall (UFW)
ufw allow ssh
ufw allow 80/tcp     # HTTP
ufw allow 443/tcp    # HTTPS
ufw allow 3333/tcp   # Mining low diff
ufw allow 4444/tcp   # Mining mid diff
ufw allow 5555/tcp   # Mining high diff
ufw allow 7777/tcp   # NiceHash
ufw allow 8888/tcp   # Hidden port
ufw allow 9999/tcp   # SSL mining
ufw allow 8117/tcp   # Pool API HTTP
ufw allow 8119/tcp   # Pool API HTTPS
ufw --force enable

# Directory e repository
APP_DIR="/opt/mevapool"
REPO_URL="https://github.com/pasqualelembo78/mevapool.git"

# Clona repository
rm -rf "$APP_DIR"
git clone "$REPO_URL" "$APP_DIR"

# Entra nella directory del progetto
cd "$APP_DIR" || exit 1

# Installa dipendenze Node.js
npm install

# Crea servizio systemd
cat > /etc/systemd/system/mevapool.service <<EOF
[Unit]
Description=MevaCoin Mining Pool
After=network.target

[Service]
ExecStart=/usr/bin/node /opt/mevapool/init.js
WorkingDirectory=/opt/mevapool
Restart=always
RestartSec=10
User=root
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

# Ricarica systemd e avvia il servizio
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable mevapool.service
systemctl start mevapool.service
