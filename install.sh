#!/bin/bash
# ==================================================================
# MevaPool - Script Idempotente v9
# Fix: apache2 reload→restart, wallet-rpc diagnosi, POOL_WALLET M...
# ==================================================================
set -euo pipefail

# --- CONFIGURAZIONE ---------------------------------------------
POOL_DOMAIN="pool.mevacoin.com"
POOL_EMAIL="support@mevacoin.com"

# FIX: indirizzo pool aggiornato al formato MevaCoin corrente (prefisso 120, M...)
# SOSTITUISCI con il tuo indirizzo M... generato dal wallet MevaCoin
POOL_WALLET="MCT8yaZmJu68Wk1ZeauyRh1r6DQ8HXhqNhXjpMDZEBQYNJ526gXAMpMYopxp59ovDchXx23jVGTcHc7mANuumdZm8JLEY6f"

WALLET_FILE="/root/.mevacoin/pool-wallet/pool"
WALLET_PASS="Desy2011"

MEVA_BIN_DIR="/root/mevacoin/build/Linux/mevacoin/release/bin"
MEVACOIND="${MEVA_BIN_DIR}/mevacoind"
MEVA_WALLET_RPC="${MEVA_BIN_DIR}/mevacoin-wallet-rpc"
MEVA_WALLET_CLI="${MEVA_BIN_DIR}/wallet-cli"
MEVA_DATA_DIR="/root/.mevacoin"

P2P_PORT=18080
RPC_PORT=18081
WALLET_RPC_PORT=18083

APP_DIR="/opt/mevapool"
REPO_URL="https://github.com/pasqualelembo78/mevapool.git"
WEB_DIR="/var/www/${POOL_DOMAIN}/html"

BLOCK_EXPLORER="https://explorer.mevacoin.com/block/{id}"
TX_EXPLORER="https://explorer.mevacoin.com/tx/{id}"

EXCLUSIVE_NODES="87.106.40.193:18080 87.106.233.72:18080"
REDIS_PASS="f436958355c2375ee687c7d6ebe79c13b1fc978dd02f9ef5"
# -----------------------------------------------------------------

ok()   { echo "  [OK] $1"; }
skip() { echo "  [SKIP]  $1 (gia' OK)"; }
warn() { echo "  [WARN]  $1"; }
fail() { echo "  [FAIL] $1"; exit 1; }
info() { echo "  [INFO]  $1"; }

echo "=================================================="
echo "  MevaPool - Installazione Idempotente v9"
echo "  Dominio: ${POOL_DOMAIN}"
echo "  Wallet:  ${POOL_WALLET:0:20}..."
echo "=================================================="

# == [1/10] PREREQUISITI ==
echo ""
echo "== [1/10] Prerequisiti =="
[ ! -f "${MEVACOIND}" ]      && fail "mevacoind non trovato in ${MEVACOIND}"
[ ! -f "${MEVA_WALLET_RPC}" ] && fail "wallet-rpc non trovato in ${MEVA_WALLET_RPC}"
ok "Binari trovati"

# == [2/10] DIPENDENZE ==
echo ""
echo "== [2/10] Dipendenze sistema =="
PKGS="curl git build-essential redis-server ufw apache2 certbot python3-certbot-apache libboost-all-dev libsodium-dev cmake python3 g++ make"
MISSING=""
for pkg in $PKGS; do
    dpkg -s "$pkg" &>/dev/null || MISSING="$MISSING $pkg"
done
if [ -n "$MISSING" ]; then
    apt update -qq && apt install -y -qq $MISSING
    ok "Pacchetti installati:$MISSING"
else
    skip "Pacchetti sistema"
fi

if command -v n &>/dev/null; then
    skip "n installato"
else
    npm install -g n --force 2>/dev/null || {
        curl -fsSL https://raw.githubusercontent.com/tj/n/master/bin/n -o /usr/local/bin/n
        chmod +x /usr/local/bin/n
    }
    ok "n installato"
fi
CURRENT_NODE=$(/usr/local/bin/node -v 2>/dev/null || echo "none")
if [[ "$CURRENT_NODE" == v16.* ]]; then
    skip "Node.js $CURRENT_NODE"
else
    n 16 && export PATH="/usr/local/bin:$PATH" && hash -r
    ok "Node.js switchato a $(/usr/local/bin/node -v)"
fi

# == [3/10] REDIS ==
echo ""
echo "== [3/10] Redis =="
if systemctl is-active --quiet redis-server; then
    skip "Redis attivo"
else
    systemctl enable redis-server && systemctl start redis-server
    ok "Redis avviato"
fi

# == [4/10] FIREWALL ==
echo ""
echo "== [4/10] Firewall =="
for port in 22/tcp 80/tcp 443/tcp ${P2P_PORT}/tcp ${RPC_PORT}/tcp \
            3333/tcp 4444/tcp 5555/tcp 7777/tcp 8888/tcp 9999/tcp 8117/tcp 8119/tcp; do
    ufw allow "$port" >/dev/null 2>&1 || true
done
ufw status | grep -q "Status: active" && skip "Firewall attivo" || { ufw --force enable; ok "Firewall attivato"; }
ok "Porte: P2P:${P2P_PORT} RPC:${RPC_PORT} Mining:3333-9999 API:8117/8119"

# == [6/10] POOL WALLET ==
echo ""
echo "== [6/10] Pool wallet =="
WALLET_DIR="$(dirname ${WALLET_FILE})"
mkdir -p "${WALLET_DIR}"

if [ -f "${WALLET_FILE}.keys" ]; then
    skip "Wallet gia' esiste: ${WALLET_FILE}"
else
    info "Creazione nuovo pool wallet..."
    for i in 1 2 3 4 5; do
        curl -s --max-time 3 http://127.0.0.1:${RPC_PORT}/json_rpc \
            -d '{"jsonrpc":"2.0","method":"get_info"}' \
            -H 'Content-Type: application/json' | grep -q '"status"' && break
        info "Attesa daemon (tentativo $i/5)..."
        sleep 5
    done
    echo "1" | ${MEVA_WALLET_CLI} \
        --generate-new-wallet "${WALLET_FILE}" \
        --password "${WALLET_PASS}" \
        --daemon-address 127.0.0.1:${RPC_PORT} \
        --command exit
    if [ -f "${WALLET_FILE}.keys" ]; then
        ok "Wallet creato: ${WALLET_FILE}"
        warn "SALVA IL SEED! Esegui: ${MEVA_WALLET_CLI} --wallet-file ${WALLET_FILE} --password ${WALLET_PASS} --command seed"
    else
        fail "Creazione wallet fallita"
    fi
fi

# == [7/10] WALLET-RPC ==
echo ""
echo "== [7/10] Wallet-rpc =="
systemctl stop mevacoin-wallet-rpc.service 2>/dev/null || true
pkill -f "mevacoin-wallet-rpc" 2>/dev/null || true
sleep 2

# FIX: Aggiunti controlli pre-avvio con diagnosi chiara
# 1. Verifica che mevacoind risponda
info "Verifico che mevacoind sia raggiungibile..."
DAEMON_OK=false
for i in 1 2 3 4 5 6; do
    RPC_CHECK=$(curl -s --max-time 5 http://127.0.0.1:${RPC_PORT}/json_rpc \
        -d '{"jsonrpc":"2.0","method":"get_info"}' \
        -H 'Content-Type: application/json' 2>/dev/null || echo "")
    if echo "$RPC_CHECK" | grep -q '"height"'; then
        HEIGHT=$(echo "$RPC_CHECK" | grep -o '"height":[0-9]*' | head -1 | cut -d: -f2)
        info "Daemon risponde, blocco corrente: $HEIGHT"
        DAEMON_OK=true
        break
    fi
    info "Daemon non risponde (tentativo $i/6), attendo 10s..."
    sleep 10
done

if [ "$DAEMON_OK" = false ]; then
    warn "mevacoind non risponde dopo 60s - wallet-rpc potrebbe fallire"
    warn "Controlla: systemctl status mevacoind"
fi

cat > /etc/systemd/system/mevacoin-wallet-rpc.service <<EOF
[Unit]
Description=MevaCoin Wallet RPC
After=mevacoind.service network.target
Wants=mevacoind.service

[Service]
Type=simple
ExecStart=${MEVA_WALLET_RPC} \
    --rpc-bind-ip 127.0.0.1 \
    --rpc-bind-port ${WALLET_RPC_PORT} \
    --daemon-address 127.0.0.1:${RPC_PORT} \
    --wallet-file ${WALLET_FILE} \
    --password ${WALLET_PASS} \
    --disable-rpc-login \
    --log-file ${MEVA_DATA_DIR}/wallet-rpc.log \
    --log-level 2
Restart=on-failure
RestartSec=15
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mevacoin-wallet-rpc.service
systemctl start mevacoin-wallet-rpc.service

# FIX: attesa più lunga (il wallet-rpc impega 10-20s per aprire il file wallet)
info "Attendo avvio wallet-rpc (max 30s)..."
for i in 1 2 3 4 5 6; do
    sleep 5
    if systemctl is-active --quiet mevacoin-wallet-rpc.service; then
        ok "wallet-rpc attivo (porta:${WALLET_RPC_PORT})"
        break
    fi
    if [ $i -eq 6 ]; then
        warn "wallet-rpc non partito dopo 30s"
        echo ""
        echo "  --- DIAGNOSI wallet-rpc ---"
        journalctl -u mevacoin-wallet-rpc -n 30 --no-pager 2>/dev/null || true
        echo "  ---------------------------"
        echo "  Possibili cause:"
        echo "  1. mevacoind non sincronizzato: controlla 'systemctl status mevacoind'"
        echo "  2. File wallet corrotto: ls -la ${WALLET_FILE}*"
        echo "  3. Argomenti sbagliati: controlla il log sopra"
        echo "  4. Prova: ${MEVA_WALLET_RPC} --help | head -40"
        warn "Il pool partira' ma i pagamenti non funzioneranno fino a che wallet-rpc non e' attivo"
    fi
done

# == [8/10] MEVAPOOL ==
echo ""
echo "== [8/10] MevaPool =="
systemctl stop mevapool.service 2>/dev/null || true

if [ -d "${APP_DIR}/.git" ]; then
    cd "${APP_DIR}"
    git fetch --all -q && git reset --hard origin/master -q
    npm install --silent 2>/dev/null
    npm install dateformat --silent 2>/dev/null
    ok "MevaPool aggiornato"
else
    rm -rf "${APP_DIR}"
    git clone "${REPO_URL}" "${APP_DIR}"
    cd "${APP_DIR}"
    npm install
    npm install dateformat
    ok "MevaPool installato"
fi

# == [9/10] CONFIG + SITO WEB ==
echo ""
echo "== [9/10] Config + sito web =="

cat > "${APP_DIR}/config.json" <<CONFIGEOF
{
    "poolHost": "${POOL_DOMAIN}",
    "coin": "mevacoin",
    "symbol": "MVC",
    "coinUnits": 1000000000000,
    "coinDecimalPlaces": 12,
    "coinDifficultyTarget": 120,
    "blockchainExplorer": "${BLOCK_EXPLORER}",
    "transactionExplorer": "${TX_EXPLORER}",

    "daemonType": "default",
    "cnAlgorithm": "randomx",
    "cnVariant": 0,
    "cnBlobType": 0,
    "isRandomX": true,
    "includeAlgo": "rx/0",
    "includeHeight": true,

    "logging": {
        "files": { "level": "info", "directory": "logs", "flushInterval": 5 },
        "console": { "level": "info", "colors": true }
    },
    "hashingUtil": false,
    "childPools": null,

    "poolServer": {
        "enabled": true,
        "mergedMining": false,
        "clusterForks": "auto",
        "poolAddress": "${POOL_WALLET}",
        "pubAddressPrefix": 120,
        "intAddressPrefix": 121,
        "subAddressPrefix": 126,
        "blockRefreshInterval": 1000,
        "minerTimeout": 900,
        "sslCert": "/etc/letsencrypt/live/${POOL_DOMAIN}/cert.pem",
        "sslKey": "/etc/letsencrypt/live/${POOL_DOMAIN}/privkey.pem",
        "sslCA": "/etc/letsencrypt/live/${POOL_DOMAIN}/chain.pem",
        "ports": [
            { "port": 3333, "difficulty": 10000,  "desc": "Low end hardware (Android, RPi)" },
            { "port": 4444, "difficulty": 50000,  "desc": "Mid range hardware" },
            { "port": 5555, "difficulty": 200000, "desc": "High end hardware" },
            { "port": 7777, "difficulty": 500000, "desc": "Cloud-mining / NiceHash" },
            { "port": 9999, "difficulty": 50000,  "desc": "SSL connection", "ssl": true }
        ],
        "varDiff": {
            "minDiff": 1000,
            "maxDiff": 200000000,
            "targetTime": 30,
            "retargetTime": 30,
            "variancePercent": 30,
            "maxJump": 100
        },
        "paymentId": { "addressSeparator": "+" },
        "separators": [{"value":"+","desc":"plus"}, {"value":".","desc":"dot"}],
        "fixedDiff": { "enabled": true, "addressSeparator": "." },
        "shareTrust": { "enabled": true, "min": 10, "stepDown": 3, "threshold": 10, "penalty": 30 },
        "banning": { "enabled": true, "time": 120, "invalidPercent": 80, "checkThreshold": 30 },
        "slushMining": { "enabled": false, "weight": 300, "blockTime": 120, "lastBlockCheckRate": 1 }
    },

    "payments": {
        "enabled": true,
        "interval": 600,
        "maxAddresses": 50,
        "mixin": 16,
        "priority": 0,
        "transferFee": 2000000000,
        "dynamicTransferFee": true,
        "minerPayFee": true,
        "minPayment": 100000000000,
        "maxTransactionAmount": 50000000000000,
        "denomination": 1000000000000
    },

    "blockUnlocker": {
        "enabled": true,
        "interval": 30,
        "depth": 60,
        "poolFee": 1.0,
        "devDonation": 0,
        "networkFee": 0.0,
        "fixBlockHeightRPC": false
    },

    "api": {
        "enabled": true,
        "hashrateWindow": 600,
        "updateInterval": 5,
        "bindIp": "0.0.0.0",
        "port": 8117,
        "blocks": 30,
        "payments": 30,
        "password": "your_password",
        "ssl": true,
        "sslPort": 8119,
        "sslCert": "/etc/letsencrypt/live/${POOL_DOMAIN}/cert.pem",
        "sslKey": "/etc/letsencrypt/live/${POOL_DOMAIN}/privkey.pem",
        "sslCA": "/etc/letsencrypt/live/${POOL_DOMAIN}/chain.pem",
        "trustProxyIP": false
    },

    "daemon": {
        "host": "127.0.0.1",
        "port": ${RPC_PORT}
    },

    "wallet": {
        "host": "127.0.0.1",
        "port": ${WALLET_RPC_PORT}
    },

    "redis": {
        "host": "127.0.0.1",
        "port": 6379,
        "auth": "${REDIS_PASS}",
        "db": 0,
        "cleanupInterval": 15
    },

    "monitoring": {
        "daemon": { "checkInterval": 60, "rpcMethod": "getblockcount" },
        "wallet": { "checkInterval": 60, "rpcMethod": "getbalance" }
    },

    "charts": {
        "pool": {
            "hashrate":   { "enabled": true, "updateInterval": 60,   "stepInterval": 1800,  "maximumPeriod": 86400 },
            "miners":     { "enabled": true, "updateInterval": 60,   "stepInterval": 1800,  "maximumPeriod": 86400 },
            "workers":    { "enabled": true, "updateInterval": 60,   "stepInterval": 1800,  "maximumPeriod": 86400 },
            "difficulty": { "enabled": true, "updateInterval": 1800, "stepInterval": 10800, "maximumPeriod": 604800 },
            "price":      { "enabled": false },
            "profit":     { "enabled": false }
        },
        "user": {
            "hashrate": { "enabled": true, "updateInterval": 180, "stepInterval": 1800, "maximumPeriod": 86400 },
            "payments": { "enabled": true }
        }
    }
}
CONFIGEOF
ok "config.json scritto"

# Sito web
rm -rf "${WEB_DIR}"
mkdir -p "${WEB_DIR}"
cp -r "${APP_DIR}/website_example/"* "${WEB_DIR}/"
cat > "${WEB_DIR}/config.js" <<WEBEOF
var parentCoin = "mevacoin";
var api = "https://${POOL_DOMAIN}:8119";
var poolHost = "${POOL_DOMAIN}";
var email = "${POOL_EMAIL}";
var telegram = "";
var discord = "";
var marketCurrencies = ["{symbol}-BTC", "{symbol}-USD", "{symbol}-EUR"];
var blockchainExplorer = "${BLOCK_EXPLORER}";
var transactionExplorer = "${TX_EXPLORER}";
var themeCss = "themes/default.css";
var defaultLang = "en";
WEBEOF
chown -R www-data:www-data "/var/www/${POOL_DOMAIN}"

# Controlla se i cert SSL esistono
SSL_EXISTS=false
[ -f "/etc/letsencrypt/live/${POOL_DOMAIN}/cert.pem" ] && SSL_EXISTS=true

# Rimuovi vhost SSL di certbot SOLO per gli altri domini (non pool.mevacoin.com)
# I vecchi le-ssl di altri siti causano "Job for apache2.service failed"
for old_ssl in /etc/apache2/sites-enabled/*le-ssl*.conf \
               /etc/apache2/sites-available/*le-ssl*.conf; do
    [ -f "$old_ssl" ] || continue
    # Salta il vhost SSL del pool - lo gestiamo noi
    [[ "$old_ssl" == *"${POOL_DOMAIN}"* ]] && continue
    a2dissite "$(basename $old_ssl)" 2>/dev/null || true
    info "Disabilitato vecchio vhost SSL: $old_ssl"
done

# Scrivi vhost HTTP (con redirect a HTTPS se cert disponibile)
VHOST="/etc/apache2/sites-available/${POOL_DOMAIN}.conf"
if $SSL_EXISTS; then
    # Vhost HTTP → redirect tutto a HTTPS
    cat > "$VHOST" <<APACHEEOF
<VirtualHost *:80>
    ServerAdmin ${POOL_EMAIL}
    ServerName ${POOL_DOMAIN}
    ServerAlias www.${POOL_DOMAIN}
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^(.*)$ https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L]
</VirtualHost>
APACHEEOF
    # Scrivi vhost HTTPS direttamente (non ci affidiamo a certbot per mantenerlo)
    VHOST_SSL="/etc/apache2/sites-available/${POOL_DOMAIN}-le-ssl.conf"
    cat > "$VHOST_SSL" <<APACHESSLEOF
<IfModule mod_ssl.c>
<VirtualHost *:443>
    ServerAdmin ${POOL_EMAIL}
    ServerName ${POOL_DOMAIN}
    ServerAlias www.${POOL_DOMAIN}
    DocumentRoot ${WEB_DIR}
    <Directory ${WEB_DIR}>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/${POOL_DOMAIN}_ssl_error.log
    CustomLog \${APACHE_LOG_DIR}/${POOL_DOMAIN}_ssl_access.log combined
    SSLEngine on
    SSLCertificateFile    /etc/letsencrypt/live/${POOL_DOMAIN}/cert.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/${POOL_DOMAIN}/privkey.pem
    SSLCertificateChainFile /etc/letsencrypt/live/${POOL_DOMAIN}/chain.pem
    Include /etc/letsencrypt/options-ssl-apache.conf
</VirtualHost>
</IfModule>
APACHESSLEOF
    a2enmod ssl rewrite 2>/dev/null || true
    a2ensite "${POOL_DOMAIN}-le-ssl.conf" 2>/dev/null || true
    ok "Vhost HTTPS scritto e abilitato"
else
    # Nessun cert: solo HTTP con DocumentRoot
    cat > "$VHOST" <<APACHEEOF
<VirtualHost *:80>
    ServerAdmin ${POOL_EMAIL}
    ServerName ${POOL_DOMAIN}
    ServerAlias www.${POOL_DOMAIN}
    DocumentRoot ${WEB_DIR}
    <Directory ${WEB_DIR}>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/${POOL_DOMAIN}_error.log
    CustomLog \${APACHE_LOG_DIR}/${POOL_DOMAIN}_access.log combined
</VirtualHost>
APACHEEOF
fi

a2dissite 000-default.conf 2>/dev/null || true
a2dissite melatv.it.conf   2>/dev/null || true
a2ensite "${POOL_DOMAIN}.conf" 2>/dev/null || true
a2enmod rewrite 2>/dev/null || true

if apache2ctl configtest 2>&1 | grep -q "Syntax OK"; then
    systemctl restart apache2 && ok "Apache riavviato" || warn "Apache restart fallito"
else
    echo ""
    echo "  --- ERRORE configurazione Apache ---"
    apache2ctl configtest 2>&1 || true
    echo "  ------------------------------------"
    a2dissite --quiet '*' 2>/dev/null || true
    a2ensite "${POOL_DOMAIN}.conf" 2>/dev/null || true
    systemctl restart apache2 && ok "Apache riavviato (recovery)" || warn "Apache ancora non parte - vedi: journalctl -xeu apache2"
fi

# Ottieni SSL se non esiste ancora
if ! $SSL_EXISTS; then
    if systemctl is-active --quiet apache2; then
        if host "${POOL_DOMAIN}" >/dev/null 2>&1; then
            certbot --apache -d "${POOL_DOMAIN}" -d "www.${POOL_DOMAIN}" \
                --non-interactive --agree-tos -m "${POOL_EMAIL}" \
                && ok "SSL ottenuto - rilancia install.sh per attivarlo" \
                || warn "SSL fallito - riprova: certbot --apache -d ${POOL_DOMAIN}"
        else
            warn "DNS non risolve ${POOL_DOMAIN} - SSL saltato"
        fi
    else
        warn "Apache non attivo - SSL saltato"
    fi
fi

# FIX: se SSL non disponibile, disabilita ssl nella config API per evitare crash del pool
if ! $SSL_EXISTS && [ ! -f "/etc/letsencrypt/live/${POOL_DOMAIN}/cert.pem" ]; then
    info "Cert SSL non disponibile - disabilito SSL nell'API config..."
    python3 - <<PYEOF
import json
cfg_path = "${APP_DIR}/config.json"
with open(cfg_path) as f:
    cfg = json.load(f)
cfg['api']['ssl'] = False
cfg['api']['sslPort'] = 8117
with open(cfg_path, 'w') as f:
    json.dump(cfg, f, indent=4)
print("  [INFO]  API ssl=false (cert non disponibile)")
PYEOF
fi

# == [10/10] SERVIZIO POOL ==
echo ""
echo "== [10/10] Servizio MevaPool =="
cat > /etc/systemd/system/mevapool.service <<EOF
[Unit]
Description=MevaCoin Mining Pool
After=network.target mevacoind.service mevacoin-wallet-rpc.service
Requires=mevacoind.service

[Service]
ExecStart=/usr/local/bin/node ${APP_DIR}/init.js
WorkingDirectory=${APP_DIR}
Restart=always
RestartSec=10
User=root
Environment=NODE_ENV=production
Environment=PATH=/usr/local/bin:/usr/bin:/bin
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mevapool.service
systemctl restart mevapool.service
sleep 3

systemctl is-active --quiet mevapool.service && ok "mevapool attivo" || {
    warn "mevapool non partito"
    echo ""
    journalctl -u mevapool -n 20 --no-pager 2>/dev/null || true
}

# == RIEPILOGO ==
echo ""
echo "======================================================"
echo "  RIEPILOGO"
echo "======================================================"
for svc in mevacoind mevacoin-wallet-rpc mevapool redis-server apache2; do
    systemctl is-active --quiet "$svc" \
        && echo "  [OK] $svc: ATTIVO" \
        || echo "  [FAIL] $svc: NON ATTIVO"
done
echo ""
echo "  Node.js: $(node -v 2>/dev/null || echo 'n/a')"
echo "  Pool wallet: ${POOL_WALLET:0:30}..."
echo "  Wallet file: ${WALLET_FILE}"
echo "  Wallet-RPC: porta ${WALLET_RPC_PORT}"
echo ""

RPC_RESP=$(curl -s --max-time 5 http://127.0.0.1:${RPC_PORT}/json_rpc \
    -d '{"jsonrpc":"2.0","method":"get_info"}' -H 'Content-Type: application/json' 2>/dev/null || echo "")
if echo "$RPC_RESP" | grep -q '"height"'; then
    HEIGHT=$(echo "$RPC_RESP" | grep -o '"height":[0-9]*' | head -1 | cut -d: -f2)
    echo "  [OK] Daemon RPC - blocco: $HEIGHT"
else
    echo "  [WARN] Daemon RPC non risponde su :${RPC_PORT}"
fi

API_RESP=$(curl -s --max-time 5 http://127.0.0.1:8117/stats 2>/dev/null || echo "")
[ -n "$API_RESP" ] && echo "  [OK] Pool API risponde su :8117" || echo "  [WARN]  Pool API non risponde su :8117"

echo "======================================================"
echo ""
echo "  Se wallet-rpc non parte, esegui:"
echo "  journalctl -u mevacoin-wallet-rpc -n 50 --no-pager"
echo ""
echo "  Se apache non parte, esegui:"
echo "  apache2ctl configtest && journalctl -xeu apache2 -n 30"
echo "======================================================"
