#!/bin/bash

set -ex

#IMG_TAG=jamesdbloom/mockserver@sha256:90e5af20e34ecce94ec1ffa348fefc127aca59ac441100d89cfae93881f280ed
IMG_TAG=jamesdbloom/mockserver:mockserver-5.6.0

usage () {
    echo "mockserver docker launcher. \
Usage: \

$0: <target IP> <target PORT> <target CN> <target SANs>";
    exit -1;
}

targetport=80
if [ -z "$1" ]; then
    echo "WARNING: running in production (not proxy) mode! type '$0 help' for instructions on using this in proxy mode"
else
    OPTIONS="$OPTIONS -proxyRemoteHost $1"
    if [ "$1" == "help" ]; then
	usage
    fi
    if [ -n "$2" ]; then
	targetport=$2
    fi
    if [ -n "$3" ]; then
        targetcn="$3"
    else
	if [ "$targetport" != "80" ]; then
	    echo "WARNING: port other than 80 specified, but no SSL cert information provided?"
	fi
    fi
    if [ -n "$4" ]; then
	targetsans="$4"
    fi
    OPTIONS="$OPTIONS -proxyRemotePort $targetport"
fi

OPTIONS="$OPTIONS -serverPort 10$targetport -logLevel INFO"
# from the perspective of the docker image:
CAKEY="/mnt/cert/local-mitm-key.pem"
CACERT="/mnt/cert/local-mitm-cert.pem"


# change these out if you want bash in this container.
#RUN="--entrypoint /bin/bash ${IMG_TAG}"
RUN="-d --entrypoint /opt/mockserver/run_mockserver.sh ${IMG_TAG} ${OPTIONS}"

#NETWORKING="--network host"
NETWORKING="-p $targetport:10$targetport"


SETUP_TLS="
    -v /etc/ssl/certs:/etc/ssl/certs:ro
    -v /usr/share/ca-certificates:/usr/share/ca-certificates:ro
    -v /usr/local/share/ca-certificates:/usr/local/share/ca-certificates:ro"


mkdir -p ./mnt/
SETUP_CFG="
    -v $(pwd)/mnt/:/mnt/"

dockeropts=$( echo ${NETWORKING} ${SETUP_TLS} ${SETUP_CFG} )

docker run -it --rm $dockeropts --env JVM_OPTIONS="-Dlogback.configurationFile=/mnt/logback.xml -Dlog.dir=/mnt/ -Dmockserver.sslCertificateDomainName=$targetcn -Dmockserver.sslSubjectAlternativeNameDomains=$targetsans -Dmockserver.certificateAuthorityPrivateKey=$CAKEY -Dmockserver.certificateAuthorityCertificate=$CACERT" ${RUN}
