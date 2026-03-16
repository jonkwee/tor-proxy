#!/bin/bash
set -e

SOCKS_PORT=9060

# Remove default torrc to prevent a default Tor instance from starting
rm -f /etc/tor/torrc

for i in $(seq 1 "${TOR_INSTANCES}"); do
    export SOCKS_PORT
    export TOR_COUNT="$i"
    envsubst '${SOCKS_PORT} ${TOR_COUNT}' < /etc/tor/torrc.template > "/etc/tor/torrc.$i"
    mkdir -p "/var/lib/tor$i"
    chown debian-tor:debian-tor "/var/lib/tor$i"
    chmod 700 "/var/lib/tor$i"
    echo "    server tor$i 127.0.0.1:${SOCKS_PORT} check" >> /etc/haproxy/haproxy.cfg
    SOCKS_PORT=$((SOCKS_PORT + 1))
done

# Remove template so the tor run script glob doesn't pick it up
rm -f /etc/tor/torrc.template

# Append SOCKS5 forwarding to privoxy config
echo 'forward-socks5 / 127.0.0.1:1080 .' >> /etc/privoxy/config
# Ensure privoxy listens on all interfaces
sed -i 's/^listen-address  127.0.0.1:8118/listen-address  0.0.0.0:8118/' /etc/privoxy/config
