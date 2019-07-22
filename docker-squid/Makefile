# MockServer related makefile. to be run on a properly configured proxybox, per the instructions in README-MockServer.md

mockserver_setup:
        #grab mockserver with docker.
        docker pull jamesdbloom/mockserver:mockserver-snap
        #grab and install it's CA key.
        sudo mkdir /usr/local/share/ca-certificates/mockserver
        sudo curl https://raw.githubusercontent.com/jamesdbloom/mockserver/master/mockserver-core/src/main/resources/org/mockserver/socket/CertificateAuthorityCertificate.pem -o /usr/local/share/ca-certificates/mockserver/mockserver.crt
        sudo update-ca-certificates
