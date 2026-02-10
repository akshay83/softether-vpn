FROM siomiz/softethervpn:latest

RUN apk add --no-cache bash openssl inotify-tools nano

COPY entrypoint.sh /entrypoint.sh
COPY setup.sh /scripts/setup.sh

RUN chmod +x /entrypoint.sh /scripts/setup.sh

ENTRYPOINT ["/entrypoint.sh"]
