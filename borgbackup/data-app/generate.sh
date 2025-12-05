#!/bin/sh

while true; do
    echo "$(date): Hello, World!" >> /var/data/hello.log
    sleep 60
done
