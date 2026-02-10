FROM alpine:3.20

RUN apk add --no-cache \
    bash git inotify-tools \
    build-base readline-dev ncurses-dev openssl-dev zlib-dev cmake \
    libsodium-dev

# build SoftEther from official source
WORKDIR /usr/src

RUN git clone --depth 1 --recurse-submodules https://github.com/SoftEtherVPN/SoftEtherVPN.git \
 && cd SoftEtherVPN \
 && ./configure \
 && make -C build -j$(nproc) \
 && make -C build install

WORKDIR /usr/local/vpnserver

COPY entrypoint.sh /entrypoint.sh
COPY setup.sh /setup.sh

RUN chmod +x /entrypoint.sh /setup.sh

EXPOSE 443 5555 500/udp 4500/udp 1701/udp 1194/udp 992

ENTRYPOINT ["/entrypoint.sh"]
