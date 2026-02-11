#!/usr/bin/env bash
set -uo pipefail
echo "Entered"

########################################
# REQUIRED
########################################
: "${SE_DOMAIN:?Missing SE_DOMAIN}"
: "${SE_CERT_DIR:?Missing SE_CERT_DIR}"

########################################
# CONFIG
########################################
SE_HUB=${SE_HUB:-VPN}
SE_ADMIN_PASSWORD=${SE_ADMIN_PASSWORD:-admin}
SE_PORT=${SE_PORT:-443}

SE_VPN_SUBNET=${SE_VPN_SUBNET:-10.10.0.0}
SE_VPN_MASK=${SE_VPN_MASK:-255.255.255.0}
SE_VPN_START=${SE_VPN_START:-10.10.0.10}
SE_VPN_END=${SE_VPN_END:-10.10.0.200}

SE_CLIENTS=${SE_CLIENTS:-""}
SE_ADMIN_USERS=${SE_ADMIN_USERS:-""}
SE_CERT_YEARS=${SE_CERT_YEARS:-10}

DATA=/data
CA_DIR=$DATA/ca
CLIENT_DIR=$DATA/clients
VPN_DIR=/usr/local/vpnserver

mkdir -p "$CA_DIR" "$CLIENT_DIR"

log(){ echo "[$(date)] $*"; }

vpn() {
  vpncmd localhost /SERVER "$@" >/dev/null 2>&1 || true
}

log "Starting Server"

########################################
# Start server
########################################
#/usr/local/vpnserver start || true
#/usr/local/vpnserver start &
sleep 5

vpn /CMD ServerPasswordSet "$SE_ADMIN_PASSWORD"

log "Hub + SSTP"

########################################
# Hub + SSTP
########################################
vpn <<EOF
HubCreate $SE_HUB /PASSWORD:hubpass
exit
EOF

vpn /CMD SstpEnable yes
vpn /CMD ListenerDelete "$SE_PORT"
vpn /CMD ListenerCreate "$SE_PORT"

log "SecureNAT + DHCP"

########################################
# SecureNAT + DHCP
########################################
GW="${SE_VPN_SUBNET%.*}.1"

vpn <<EOF
Hub $SE_HUB
SecureNatEnable
SecureNatHostSet /IP:$GW /MASK:$SE_VPN_MASK
DhcpSet /START:$SE_VPN_START /END:$SE_VPN_END
exit
EOF

log "Internal CA"

########################################
# INTERNAL CA
########################################
if [[ ! -f "$CA_DIR/ca.key" ]]; then
  log "Creating internal CA"

  openssl genrsa -out $CA_DIR/ca.key 4096
  openssl req -x509 -new -nodes \
    -key $CA_DIR/ca.key \
    -days $((SE_CERT_YEARS*365)) \
    -out $CA_DIR/ca.crt \
    -subj "/CN=SoftEther-Internal-CA"
fi

log "TLS Installer"

########################################
# TLS INSTALLER (non-blocking)
########################################
reload_tls() {
  if [[ -f "$SE_CERT_DIR/fullchain.pem" ]]; then
    log "Installing TLS certificate"

    cp "$SE_CERT_DIR/fullchain.pem" /usr/local/server_cert.pem
    cp "$SE_CERT_DIR/privkey.pem"   /usr/local/server_key.pem

    "$VPN_DIR/vpnserver" stop || true
    #sleep 2
    "$VPN_DIR/vpnserver" start || true
  else
    log "TLS certificate not present yet"
  fi
}

# try once at startup
reload_tls


########################################
# Watch renewals (BACKGROUND!!)
########################################
(
  inotifywait -m -e close_write,create "$SE_CERT_DIR" |
  while read -r _; do
    reload_tls
  done
) &

########################################
# Start SoftEther FOREGROUND (PID 1)
########################################
log "Starting SoftEther server"
exec "$VPN_DIR/vpnserver"
