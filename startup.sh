#!/bin/bash

TOR_CONFIG_PATH=/etc/tor
HAPROXY_CONFIG_FILE=/etc/haproxy/haproxy.cfg
SOCKS_PORT=9060
CONTROL_PORT=$((${SOCKS_PORT} + 1))

for i in $(seq 1 ${TOR_INSTANCES});
do
    TOR_COUNT=${i}
    export SOCKS_PORT CONTROL_PORT TOR_COUNT
    envsubst <${TOR_CONFIG_PATH}/torrc.template >${TOR_CONFIG_PATH}/torrc.${i}
    echo "    server server$((${i} - 1)) 127.0.0.1:${SOCKS_PORT}" >> ${HAPROXY_CONFIG_FILE}

    SOCKS_PORT=$((${CONTROL_PORT} + 1))
    CONTROL_PORT=$((${SOCKS_PORT} + 1))
done

# Starting all tor instances
for file in ${TOR_CONFIG_PATH}/torrc.*
do
    tor -f $file &
done

# Restart HAProxy
service haproxy restart

# Add forwarding socks5 config to privoxy
echo "forward-socks5   /               127.0.0.1:1080 ." >> /etc/privoxy/config

# Start privoxy
/etc/init.d/privoxy start


# Uninstall unnecessary packages
apt purge -y gpg wget gettext-base

/bin/bash
