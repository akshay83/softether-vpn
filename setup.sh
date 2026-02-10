#!/bin/sh
set -e

########################################
# CONFIG
########################################
HUB=VPN
DATA_DIR=/data
CLIENT_DIR=$DATA_DIR/clients
CA_DIR=$DATA_DIR/ca

mkdir -p "$CLIENT_DIR"

CMD=$1
USER=$2
PASS=$3

log() { echo "[setup] $*"; }

require_user() {
  [ -z "$USER" ] && { echo "User required"; exit 1; }
}

vpn() {
  vpncmd localhost /SERVER /HUB:$HUB /CMD "$@"
}

########################################
# CERTIFICATE USER (branch/device)
########################################
add_cert_user() {

  require_user

  log "Creating certificate user: $USER"

  KEY=$CLIENT_DIR/$USER.key
  CSR=$CLIENT_DIR/$USER.csr
  CRT=$CLIENT_DIR/$USER.crt
  P12=$CLIENT_DIR/$USER.p12

  # key
  openssl genrsa -out "$KEY" 2048 >/dev/null 2>&1

  # csr
  openssl req -new \
    -key "$KEY" \
    -out "$CSR" \
    -subj "/CN=$USER" >/dev/null 2>&1

  # sign
  openssl x509 -req \
    -in "$CSR" \
    -CA "$CA_DIR/ca.crt" -CAkey "$CA_DIR/ca.key" -CAcreateserial \
    -out "$CRT" \
    -days 3650 >/dev/null 2>&1

  # p12
  openssl pkcs12 -export \
    -out "$P12" \
    -inkey "$KEY" \
    -in "$CRT" \
    -certfile "$CA_DIR/ca.crt" \
    -passout pass: >/dev/null 2>&1

  # softether user
  vpn UserCreate "$USER"
  vpn UserCertSet "$USER" /LOADCERT:"$CRT"
  vpn UserPolicySet "$USER" /MaxConnection:1

  log "DONE -> $P12"
}

########################################
# PASSWORD USER (admin/travel)
########################################
add_password_user() {

  require_user

  [ -z "$PASS" ] && { echo "Password required"; exit 1; }

  log "Creating password user: $USER"

  vpn UserCreate "$USER"
  vpn UserPasswordSet "$USER" /PASSWORD:"$PASS"
  vpn UserPolicySet "$USER" /MaxConnection:1

  log "DONE -> password user created"
}

########################################
# REVOKE USER
########################################
revoke_user() {

  require_user

  log "Revoking user: $USER"

  vpn UserDelete "$USER" || true
  rm -f "$CLIENT_DIR/$USER".*

  log "DONE -> removed"
}

########################################
# LIST USERS
########################################
list_users() {
  vpn UserList
}

########################################
# USAGE
########################################
usage() {
  echo ""
  echo "Commands:"
  echo "  addcert  <user>          -> branch/device (.p12)"
  echo "  adduser  <user> <pass>   -> password admin"
  echo "  revoke   <user>"
  echo "  list"
  echo ""
}

########################################
# MAIN
########################################
case "$CMD" in
  addcert) add_cert_user ;;
  adduser) add_password_user ;;
  revoke)  revoke_user ;;
  list)    list_users ;;
  *)       usage ;;
esac
