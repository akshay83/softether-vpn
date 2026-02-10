#!/bin/bash

CMD=$1

case "$CMD" in
  addcert)
    USER=$2
    SE_CLIENTS=$USER /entrypoint.sh
    ;;

  addadmin)
    USER=$2
    PASS=$3
    vpncmd localhost /SERVER <<EOF
Hub VPN
UserCreate $USER
UserPasswordSet $USER /PASSWORD:$PASS
exit
EOF
    ;;

  revoke)
    USER=$2
    vpncmd localhost /SERVER /CMD UserDelete $USER
    rm -f /data/clients/$USER.*
    ;;
esac
