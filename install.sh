#!/bin/bash

# Aggiorna sistema e installa pacchetti richiesti
apt update && apt upgrade -y
apt install -y curl git build-essential redis-server ufw apache2 certbot python3-certbot-apache

# Installa Node.js LTS
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt install -y nodejs

# Verifica installazione
node -v
npm -v

# Avvia e abilita Redis
systemctl enable redis-server
systemctl start redis-server

# Configura UFW (firewall)
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

# Imposta variabili progetto
APP_DIR="/opt/mevapool"
REPO_URL="https://github.com/pasqualelembo78/mevapool.git"

# Clona repository
rm -rf "$APP_DIR"
git clone "$REPO_URL" "$APP_DIR"

# Installa dipendenze Node.js
cd "$APP_DIR" || exit 1
npm install

# Crea directory del sito web
mkdir -p /var/www/melatv.it/html
cp -r "$APP_DIR/website_example/"* /var/www/melatv.it/html/
chown -R www-data:www-data /var/www/melatv.it

# Crea virtual host Apache per melatv.it
cat > /etc/apache2/sites-available/melatv.it.conf <<EOF
<VirtualHost *:80>
    ServerAdmin webmaster@melatv.it
    ServerName www.melatv.it
    DocumentRoot /var/www/melatv.it/html
    ErrorLog \${APACHE_LOG_DIR}/melatv.it_error.log
    CustomLog \${APACHE_LOG_DIR}/melatv.it_access.log combined
</VirtualHost>
EOF

# Abilita sito e riavvia Apache
a2ensite melatv.it.conf
a2enmod rewrite
systemctl reload apache2

# Ottieni certificato HTTPS con Let's Encrypt
certbot --apache -d www.melatv.it --non-interactive --agree-tos -m support@melatv.it

# Crea directory SSL pool
mkdir -p /var/www/melatv.it/ssl

# Copia certificati in posizione richiesta
cp /etc/letsencrypt/live/www.melatv.it/cert.pem     /var/www/melatv.it/ssl/cert.pem
cp /etc/letsencrypt/live/www.melatv.it/privkey.pem  /var/www/melatv.it/ssl/privkey.pem
cp /etc/letsencrypt/live/www.melatv.it/chain.pem    /var/www/melatv.it/ssl/chain.pem

# Crea servizio systemd per il mining pool
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

# Avvia servizio mining pool
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable mevapool.service
systemctl start mevapool.service
