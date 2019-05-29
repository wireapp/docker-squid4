#!/bin/bash

set -ex

# setup configs for squid, haproxy
rm -f /etc/squid4/squid.conf
ln -s /mnt/squid.conf /etc/squid4/

rm -f /etc/haproxy/haproxy.cfg
ln -s /mnt/haproxy.cfg /etc/haproxy

# Setup the ssl_cert directory
if [ ! -d /etc/squid4/ssl_cert ]; then
    mkdir /etc/squid4/ssl_cert
fi

chown -R proxy:proxy /etc/squid4
chmod 700 /etc/squid4/ssl_cert

# Setup the squid cache directory
if [ ! -d /mnt/cache ]; then
    mkdir -p /mnt/cache
fi
chown -R proxy: /mnt/cache
chmod -R 750 /mnt/cache

if [ -n "$MITM_PROXY" ]; then
    if [ -n "$MITM_KEY" ]; then
        echo "Copying \"$MITM_KEY\" as MITM key..."
        cp "$MITM_KEY" /etc/squid4/ssl_cert/mitm.pem
        chown root:proxy /etc/squid4/ssl_cert/mitm.pem
    fi

    if [ -n "$MITM_CERT" ]; then
        echo "Copying \"$MITM_CERT\" as MITM CA..."
        cp "$MITM_CERT" /etc/squid4/ssl_cert/mitm.crt
        chown root:proxy /etc/squid4/ssl_cert/mitm.crt
    fi

    if [ -z "$MITM_CERT" ] || [ -z "$MITM_KEY" ]; then
        echo "Must specify \"$MITM_CERT\" AND \"$MITM_KEY\"." 1>&2
        exit 1
    fi
fi

chown proxy: /dev/stdout
chown proxy: /dev/stderr

chown -R proxy: /mnt/log
chmod -R 750 /mnt/log

# Initialize the certificates database
/usr/libexec/security_file_certgen -c -s /var/spool/squid4/ssl_db -M1000000000
chown -R proxy: /var/spool/squid4/ssl_db

# TODO: what does this do?  aren't we going to miss it?  it doesn't
# appear to be installed anywhere in this docker image.
#ssl_crtd -c -s
#ssl_db

# Build the configuration directories if needed
squid -z -N

# start haproxy
service haproxy start

# run squid
squid -N
