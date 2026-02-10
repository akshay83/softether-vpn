FROM alpine:3.20

RUN apk add --no-cache \
    bash openssl curl inotify-tools build-base cmake \
    openssl-dev readline-dev ncurses-dev zlib-dev

# build SoftEther from official source
WORKDIR /tmp
RUN curl -L https://github.com/SoftEtherVPN/SoftEtherVPN_Stable/archive/refs/tags/v4.43-9799.tar.gz -o se.tar.gz \
 && tar xzf se.tar.gz \
 && cd SoftEtherVPN_Stable-* \
 && cmake . \
 && make -j$(nproc) \
 && make install

WORKDIR /usr/local/vpnserver

COPY entrypoint.sh /entrypoint.sh
COPY setup.sh /setup.sh

RUN chmod +x /entrypoint.sh /setup.sh

EXPOSE 443

ENTRYPOINT ["/entrypoint.sh"]
