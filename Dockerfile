FROM siomiz/softethervpn:latest

RUN apk add --no-cache bash openssl inotify-tools

COPY entrypoint.sh /entrypoint.sh
COPY setup.sh /setup.sh

RUN chmod +x /entrypoint.sh /setup.sh

ENTRYPOINT ["/entrypoint.sh"]
