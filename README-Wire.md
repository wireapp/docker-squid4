This repo (cloned from https://github.com/fgrehm/squid3-ssl-docker) contains two directories:

# mk-ca-cert

You'll want to run this to create your man-in-the-middle SSL certificate.
```
cd docker-squid4/mk-ca-cert
./mk-certs
cd ../docker-squid
mkdir -p ./mnt/cert
cp ../mk-ca-cert/certs/private.pem ./mnt/cert/local-mitm-cert.pem
cp ../mk-ca-cert/certs/wire.com.crt ./mnt/cert/local-mitm-key.pem
```

# docker-squid
docker-squid consains a modified docker-squid container. It has been modified to build an experimental version of docker from Measurement Factory, and to install and use haproxy.

It requires the use of host based networking by default, but does not assume any IPs (excepting lo at 127.0.0.1).

to build:

```sh
docker build .
```

When this completes, it will give you an image ID on the last line of output, which will look like ```Successfully built fd0a530f522a```. Set a tag refering to that image ID, so our run script can launch the image.
```
docker tag <image_id> squid
```

Alternatively, you can pull it from quay.io/wire:

```sh
export SQUID_SHA256=0df70cbcd1faa7876e89d65d215d86e1518cc45e24c7bf8891bc1b57563961fa
docker pull quay.io/wire/squid@sha256:$SQUID_SHA256
docker inspect --format='{{index .RepoDigests 0}}' quay.io/wire/squid@sha256:$SQUID_SHA256 \
  | grep -q $SQUID_SHA256 && echo 'OK!' || echo '*** error: wrong checksum!'
docker tag quay.io/wire/squid@sha256:$SQUID_SHA256 squid
```

You can now launch the image with run.sh

```
./run.sh
```

# interpreting squid's access.log to export info on cache.

docker-squid/mnt/log/access.log can be used to extract things like
domain lists and cache TOC.  basic info in json:

```bash
cat mnt/log/access.log | \
  perl -ne '/^\S+\s+\S+\s+\S+\s+\S+\s+(\S+)\s+(\S+)\s+(\S+)\s/; print "{\"size\":\"$1\",\"verb\":\"$2\",\"uri\":\"$3\"},\n"'
```
