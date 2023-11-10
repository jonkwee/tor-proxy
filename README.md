# tor-proxy

`tor-proxy` is a container based proxy that routes HTTP traffic through a set of Tor instances. The container will consists of 3 main services: Tor, HAProxy and Privoxy.

### [Tor](https://www.torproject.org/)
Tor is an open-source network that revolves around the idea of [The Onion Router](https://en.wikipedia.org/wiki/Onion_routing). Tor can act as a proxy by exposing Socks ports hence incoming traffic must use the SOCKS protocol and not HTTP.

### [HAProxy](https://www.haproxy.com/)
HAProxy is a load balancer which we will make use of to distribute SOCKS request to multiple Tor instances.

### [Privoxy](https://www.privoxy.org)
Privoxy will forward HTTP requests to SOCKS5 requests that will subsequently be used by Tor.

## How to Use
Clone this repository and build an image from the Dockerfile. When running the container from the image, it is crucial to set the network as `host`. Port `8118` is exposed that only takes HTTP requests.

An example `docker run` command will look like this:
```shell
docker run -it --network host -p 8118:8118 -d --name tor-proxy {image name}
```
Once the container is start up, allow Tor a couple minutes to connect securely to the Onion network. You can check the docker log using the `docker logs` command to check on the progress. When you see all the Tor instances start up, you can run the following command to check whether the proxy is working correctly.
```shell
curl -x http://127.0.0.1:8118 https://check.torproject.org
```

## Environment Variables
**TOR_INSTANCES** - The amount of tor instances you want the container to spin up. Default: 3
