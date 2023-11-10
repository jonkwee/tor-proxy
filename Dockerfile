FROM ubuntu:23.10

ENV TOR_INSTANCES 3

COPY startup.sh /scripts/startup.sh
COPY configs/tor/tor.list /etc/apt/sources.list.d/tor.list

# Installing Tor, HAProxy and Privoxy
RUN apt update && \
    apt install -y gpg wget gettext-base && \
    wget -qO- https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | gpg --dearmor | tee /usr/share/keyrings/tor-archive-keyring.gpg >/dev/null && \
    apt update && \
    apt install -y tor deb.torproject.org-keyring haproxy privoxy && \
    chmod +x /scripts/startup.sh


# Replace default configs with custom config files 
COPY configs/tor/torrc.template /etc/tor/torrc.template
COPY configs/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg


EXPOSE 8118
CMD [ "/scripts/startup.sh" ]
