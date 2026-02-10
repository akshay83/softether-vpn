FROM siomiz/softethervpn:latest

RUN apk add --no-cache bash openssl inotify-tools nano

COPY entrypoint.sh /scripts/entrypoint.sh
COPY setup.sh /scripts/setup.sh

RUN chmod +x /scripts/entrypoint.sh /scripts/setup.sh

ENTRYPOINT ["/scripts/entrypoint.sh"]
