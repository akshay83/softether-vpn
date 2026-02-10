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

########################################
# Helpers
########################################
log() { echo "[setup] $*"; }

require_user() {
  if [ -z "$USER" ]; then
    echo "User required"
    exit 1
  fi
}

########################################
# CERTIFICATE USER (branch/device)
########################################
add_cert_user() {

  require_user

  log "Creating certificate user: $USER"

  # generate key
  openssl genrsa -out $CLIENT_DIR/$USER.key 2048

  # csr
  openssl req -new \
    -key $CLIENT_DIR/$USER.key \
    -out $CLIENT_DIR/$USER.csr \
    -subj "/CN=$USER"

  # sign with internal CA
  openssl x509 -req \
    -in $CLIENT_DIR/$USER.csr \
    -CA $CA_DIR/ca.crt -CAkey $CA_DIR/ca.key -CAcreateserial \
    -out $CLIENT_DIR/$USER.crt \
    -days 3650

  # export p12 for Windows
  openssl pkcs12 -export \
    -out $CLIENT_DIR/$USER.p12 \
    -inkey $CLIENT_DIR/$USER.key \
    -in $CLIENT_DIR/$USER.crt \
    -certfile $CA_DIR/ca.crt \
    -passout pass:

  # register inside SoftEther
  vpncmd localhost /SERVER <<EOF >/dev/null
Hub $HUB
UserCreate $USER
UserCertSet $USER /LOADCERT:$CLIENT_DIR/$USER.crt
UserPolicySet $USER /MaxConnection:1
exit
EOF

  log "DONE -> $CLIENT_DIR/$USER.p12"
}

########################################
# PASSWORD USER (admin/travel)
########################################
add_password_user() {

  require_user

  if [ -z "$PASS" ]; then
    echo "Password required"
    exit 1
  fi

  log "Creating password user: $USER"

  vpncmd localhost /SERVER <<EOF >/dev/null
Hub $HUB
UserCreate $USER
UserPasswordSet $USER /PASSWORD:$PASS
UserPolicySet $USER /MaxConnection:1
exit
EOF

  log "DONE -> password user created"
}

########################################
# REVOKE USER
########################################
revoke_user() {

  require_user

  log "Revoking user: $USER"

  vpncmd localhost /SERVER /CMD UserDelete "$USER" >/dev/null 2>&1 || true
  rm -f $CLIENT_DIR/$USER.*

  log "DONE -> removed"
}

########################################
# LIST USERS
########################################
list_users() {

  vpncmd localhost /SERVER <<EOF
Hub $HUB
UserList
exit
EOF
}

########################################
# USAGE
########################################
usage() {
  echo ""
  echo "Usage:"
  echo "  setup.sh addcert  <user>           # branch/device (creates .p12)"
  echo "  setup.sh adduser  <user> <pass>    # admin/password"
  echo "  setup.sh revoke   <user>"
  echo "  setup.sh list"
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
