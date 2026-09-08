#!/bin/bash

while true; do
  clear
  iptables -t mangle -L -v -n
  sleep 1
done
