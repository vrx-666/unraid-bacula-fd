# Builds a Slackware package of the Bacula file daemon for Unraid.
# Usage: docker build --output type=local,dest=out .
FROM aclemons/slackware:15.0 AS build

ARG BACULA_VERSION=15.0.3
ARG BACULA_SHA256=294afd3d2eb9d5b71c3d0e88fdf19eb513bfdb843b28d35c0552e4ae062827a1
ARG OPENSSL_VERSION=3.5.9
ARG OPENSSL_SHA256=603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a
ARG BUILD=1

RUN slackpkg -batch=on update gpg && slackpkg -batch=on update && \
    slackpkg -batch=on -default_answer=y install \
      ca-certificates gcc gcc-g++ binutils elfutils flex make kernel-headers glibc perl \
      zlib lzo acl attr libcap pkg-config guile gc libffi libunistring && \
    update-ca-certificates --fresh

WORKDIR /src
RUN wget -q -O bacula.tar.gz https://sourceforge.net/projects/bacula/files/bacula/${BACULA_VERSION}/bacula-${BACULA_VERSION}.tar.gz/download && \
    wget -q -O openssl.tar.gz https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz && \
    echo "${BACULA_SHA256}  bacula.tar.gz" | sha256sum -c - && \
    echo "${OPENSSL_SHA256}  openssl.tar.gz" | sha256sum -c - && \
    tar xf bacula.tar.gz && tar xf openssl.tar.gz && \
    removepkg openssl

# Static OpenSSL: Slackware 15.0 only ships 1.1, Unraid 7 ships 3.x.
RUN cd openssl-${OPENSSL_VERSION} && \
    ./Configure linux-x86_64 no-shared no-tests no-docs --prefix=/opt/openssl --libdir=lib && \
    make -j"$(nproc)" && make install_sw

RUN cd bacula-${BACULA_VERSION} && \
    CFLAGS="-O2" CXXFLAGS="-O2" LIBS="-lpthread -ldl" ./configure \
      --prefix=/usr --libdir=/usr/lib64 --sbindir=/usr/sbin \
      --sysconfdir=/etc/bacula --with-scriptdir=/usr/libexec/bacula \
      --with-plugindir=/usr/lib64/bacula --with-working-dir=/var/lib/bacula \
      --with-pid-dir=/var/run --with-subsys-dir=/var/lock \
      --enable-client-only --enable-smartalloc \
      --with-openssl=/opt/openssl && \
    make -j"$(nproc)" && make DESTDIR=/pkg install

RUN cd /pkg && \
    find . -type f \( -perm -u+x -o -name '*.so*' \) -exec strip --strip-unneeded {} + 2>/dev/null; \
    rm -rf usr/share etc usr/libexec usr/lib64/*.la && find usr/sbin -type f ! -name bacula-fd -delete && \
    mkdir -p /out && makepkg -l y -c n /out/bacula-fd-${BACULA_VERSION}-x86_64-${BUILD}_vrx.txz

FROM scratch
COPY --from=build /out/ /
