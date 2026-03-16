#!/bin/bash
curl -sf --connect-timeout 5 -x http://127.0.0.1:8118 http://check.torproject.org/api/ip > /dev/null 2>&1
