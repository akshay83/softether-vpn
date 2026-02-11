############################################
# STAGE 1 — BUILD
############################################
FROM alpine:3.20 AS builder

RUN apk add --no-cache \
    bash git build-base cmake \
    readline-dev ncurses-dev openssl-dev zlib-dev \
    libsodium-dev

WORKDIR /build

RUN git clone --depth 1 --recurse-submodules https://github.com/SoftEtherVPN/SoftEtherVPN.git \
 && cd SoftEtherVPN \
 && ./configure \
 && make -C build -j$(nproc)


############################################
# STAGE 2 — RUNTIME
############################################
FROM alpine:3.20

RUN apk add --no-cache \
    bash openssl readline ncurses-libs \
    zlib libsodium inotify-tools

COPY --from=builder /build/SoftEtherVPN/build/ /usr/local/vpnserver/
ENV LD_LIBRARY_PATH=/usr/local/vpnserver

WORKDIR /usr/local/vpnserver

RUN mkdir -p /scripts
COPY entrypoint.sh /scripts/entrypoint.sh
COPY setup.sh /scripts/setup.sh

RUN chmod +x /scripts/entrypoint.sh /scripts/setup.sh

EXPOSE 443 5555 500/udp 4500/udp 1701/udp 1194/udp 992

ENTRYPOINT ["/scripts/entrypoint.sh"]
