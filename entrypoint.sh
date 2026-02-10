#!/usr/bin/env bash
set -euo pipefail

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

SE_CLIENTS=${SE_CLIENTS:-""}        # cert users
SE_ADMIN_USERS=${SE_ADMIN_USERS:-""} # password users

SE_CERT_YEARS=${SE_CERT_YEARS:-10}

DATA=/data
CA_DIR=$DATA/ca
CLIENT_DIR=$DATA/clients

mkdir -p $CA_DIR $CLIENT_DIR

log(){ echo "[$(date)] $*"; }

########################################
# Start server
########################################
/usr/vpnserver/vpnserver start
sleep 3

vpncmd localhost /SERVER /CMD ServerPasswordSet "$SE_ADMIN_PASSWORD" >/dev/null

########################################
# Hub + SSTP
########################################
vpncmd localhost /SERVER <<EOF >/dev/null
HubCreate $SE_HUB /PASSWORD:hubpass
exit
EOF

vpncmd localhost /SERVER /CMD SstpEnable yes >/dev/null
vpncmd localhost /SERVER /CMD ListenerDelete "$SE_PORT" >/dev/null 2>&1 || true
vpncmd localhost /SERVER /CMD ListenerCreate "$SE_PORT" >/dev/null

########################################
# SecureNAT + DHCP
########################################
GW="${SE_VPN_SUBNET%.*}.1"

vpncmd localhost /SERVER <<EOF >/dev/null
Hub $SE_HUB
SecureNatEnable
SecureNatHostSet /IP:$GW /MASK:$SE_VPN_MASK
DhcpSet /START:$SE_VPN_START /END:$SE_VPN_END
exit
EOF

########################################
# INTERNAL CA (once)
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

########################################
# CERT CLIENTS
########################################
create_cert_user() {

USER=$1
[[ -f "$CLIENT_DIR/$USER.p12" ]] && return

log "Creating cert client: $USER"

openssl genrsa -out $CLIENT_DIR/$USER.key 2048
openssl req -new -key $CLIENT_DIR/$USER.key -out $CLIENT_DIR/$USER.csr -subj "/CN=$USER"

openssl x509 -req \
  -in $CLIENT_DIR/$USER.csr \
  -CA $CA_DIR/ca.crt -CAkey $CA_DIR/ca.key -CAcreateserial \
  -out $CLIENT_DIR/$USER.crt \
  -days $((SE_CERT_YEARS*365))

openssl pkcs12 -export \
  -out $CLIENT_DIR/$USER.p12 \
  -inkey $CLIENT_DIR/$USER.key \
  -in $CLIENT_DIR/$USER.crt \
  -certfile $CA_DIR/ca.crt \
  -passout pass:

vpncmd localhost /SERVER <<EOF >/dev/null
Hub $SE_HUB
UserCreate $USER
UserCertSet $USER /LOADCERT:$CLIENT_DIR/$USER.crt
UserPolicySet $USER /MaxConnection:1
exit
EOF
}

IFS=',' read -ra USERS <<< "$SE_CLIENTS"
for u in "${USERS[@]}"; do
  create_cert_user "$u"
done

########################################
# PASSWORD ADMIN USERS
########################################
create_admin_user() {

PAIR=$1
USER=${PAIR%%:*}
PASS=${PAIR##*:}

log "Creating admin user: $USER"

vpncmd localhost /SERVER <<EOF >/dev/null
Hub $SE_HUB
UserCreate $USER
UserPasswordSet $USER /PASSWORD:$PASS
UserPolicySet $USER /MaxConnection:1
exit
EOF
}

IFS=',' read -ra ADMINS <<< "$SE_ADMIN_USERS"
for a in "${ADMINS[@]}"; do
  create_admin_user "$a"
done

########################################
# LETSENCRYPT TLS
########################################
until [[ -f "$SE_CERT_DIR/fullchain.pem" ]]; do sleep 5; done

reload_tls() {
  vpncmd localhost /SERVER /CMD ServerCertSet \
    "$SE_CERT_DIR/fullchain.pem" \
    "$SE_CERT_DIR/privkey.pem" >/dev/null
}

reload_tls

########################################
# Watch renewals
########################################
inotifywait -m -e close_write "$SE_CERT_DIR" |
while read -r _; do reload_tls; done
