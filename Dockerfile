FROM ubuntu:24.04

ENV TOR_INSTANCES=3
ENV TOR_IP_REFRESH_INTERVAL=300
ENV S6_KEEP_ENV=1

# Install prerequisites first (ca-certificates needed for Tor repo HTTPS)
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates gpg wget && \
    rm -rf /var/lib/apt/lists/*

# Add Tor repo and signing key (after ca-certificates is available)
COPY configs/tor/tor.list /etc/apt/sources.list.d/tor.list
RUN wget -qO- https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc \
      | gpg --dearmor | tee /usr/share/keyrings/tor-archive-keyring.gpg >/dev/null && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      tor deb.torproject.org-keyring haproxy privoxy gettext-base curl xz-utils && \
    rm -rf /var/lib/apt/lists/*

# Ensure runtime directories exist with correct ownership
RUN mkdir -p /run/haproxy /run/tor && \
    chown haproxy:haproxy /run/haproxy && \
    chown debian-tor:debian-tor /run/tor

# Install s6-overlay (architecture-agnostic + architecture-specific)
ARG S6_OVERLAY_VERSION=3.2.0.2
ARG TARGETARCH
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz && rm /tmp/s6-overlay-noarch.tar.xz
RUN case "${TARGETARCH}" in \
      amd64) S6_ARCH="x86_64" ;; \
      arm64) S6_ARCH="aarch64" ;; \
      *) echo "Unsupported architecture: ${TARGETARCH}" && exit 1 ;; \
    esac && \
    wget -qO /tmp/s6-overlay-arch.tar.xz \
      "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz" && \
    tar -C / -Jxpf /tmp/s6-overlay-arch.tar.xz && rm /tmp/s6-overlay-arch.tar.xz

# Clean up build-only packages
RUN apt-get purge -y gpg wget xz-utils && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

# Copy configs
COPY configs/tor/torrc.template /etc/tor/torrc.template
COPY configs/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg

# Copy s6 service definitions and init script
COPY s6-overlay/s6-rc.d /etc/s6-overlay/s6-rc.d
COPY scripts/init-config.sh /etc/s6-overlay/scripts/init-config.sh
RUN chmod +x /etc/s6-overlay/scripts/init-config.sh

# Health check
COPY healthcheck.sh /scripts/healthcheck.sh
RUN chmod +x /scripts/healthcheck.sh

HEALTHCHECK --interval=60s --timeout=15s --start-period=120s --retries=3 \
    CMD /scripts/healthcheck.sh

EXPOSE 8118

ENTRYPOINT ["/init"]
