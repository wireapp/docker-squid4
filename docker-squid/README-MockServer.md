# Why MockServer?

Placing mockserver in front of squid gives us flexibility when "lieing" to machines squid serves, allowing us to solve problems such as making fake redirects, and fake authentication services, and generally replaying content that is not cacheable by squid.

# General Architecture Overview:
We're assuming your setup currently sounds somewhat like the following:
'I use squid and haproxy on docker to intercept all ssl traffic from client machines on a given interface. Squid retrieves content from the real website, and gives it to clients. Iptables makes sure the clients talk to squid, while DNSMASQ tells clients the real IPs of services.'

We're going to change it to something that sounds somewhat like the following:
'I use squid and haproxy on docker to intercept all ssl traffic from client machines on a given interface. Squid retrieves content for most web sites from the real website, and gives it to clients. For some special exceptions, squid talks to mockserver instead. Iptables makes sure the clients talk to squid, while DNSMASQ tells clients the real IPs of most services, and tells both squid and clients that mockserver managed sites are really the local machine. mockserver listens on a port for traffic from squid, and proxys that traffic to the real website, memorizing the contents.'


# Setting up to run MockServer:

to aide in the configuration of mockserver, there is a Makefile in the same directory as this README. We'll be using it to perform automatable work.

* First, run 'make mockserver_setup' to install mockserver in docker, and install it's CA certificate.
```
```

* Next, edit mnt/squid.conf, so we can point it to mockserver, and so that it will accept mockserver's certificate:
 * Change dns_nameservers to point to 10.0.0.1(the address client machines see), instead of 8.8.8.8.
 * add 'flags=DONT_VERIFY_PEER' to the global tls_outgoing_options, to work around mockserver's cert being self-signed.

* Create /etc/dnsmasq.d/mockserver. This is the DNSMASQ configuration for 'lieing' to squid and our client machines about where a site is hosted.
```
#use dnsmasq to point your target site to resolve as 10.0.0.1.
#address=/faikvm.com/10.0.0.1
#address=/docker.com/10.0.0.1
```

# Training MockServer with a remote site:

## Gathering Data...

To point MockServer at a remote site, you need three things:
 * The IP of the site
 * The port of the service speaking http/https
 * If HTTPS, the certificate's CN.

Most sites are running on port 80 or port 443..

* To get a site's IP:
```
demo@boxtop:~/wireapp$ nslookup faikvm.com
Server:         192.168.2.1
Address:        192.168.2.1#53

Non-authoritative answer:
Name:   faikvm.com
Address: 205.166.94.162

```
In the case that it gives you multiple IPs, just pick any of them.

If the site you want to target speaks https, you're going to need to get the CN of the certificate the site uses to sign it's content.
* To get a site's certificate CN:
```
demo@boxtop:~/wireapp$ openssl s_client -host docker.com -port 443 2>&1 | grep subject
subject=CN = *.docker.com
```

## Using MockServer with HTTP:

For our first example, we're going to stick with a simple HTTP request.

### Pointing mockserver at a site:

* edit /etc/dnsmasq/mockserver to set DNSMASQ to tell both squid and your clients that the site is hosted locally:
```
#use dnsmasq to point your target site to resolve as 10.0.0.1.
address=/faikvm.com/10.0.0.1
```

* After any edit of /etc/dnsmasq.d/mockserver, re-start dnsmasq for your change to go into effect:
```
sudo service dnsmasq restart
```

* Launch Mockserver, with the information you collected:
```
./run_mockserver.sh 205.166.94.162 80
```

### Using MockServer:

At this point, DNSMASQ will tell you that faikvm.com is at the same IP as your local machine, and mockserver is running on that IP, proxying it's requests to the target (remote) server.

To test this, let's use curl in it's verbose mode:
```
wire@proxybox:~/docker-squid4/docker-squid$ curl -v faikvm.com
* Rebuilt URL to: faikvm.com/
*   Trying 10.0.0.1...
* Connected to faikvm.com (10.0.0.1) port 80 (#0)
> GET / HTTP/1.1
> Host: faikvm.com
> User-Agent: curl/7.47.0
> Accept: */*
>
< HTTP/1.1 403 Forbidden
< Date: Mon, 22 Jul 2019 14:26:01 GMT
< Server: Apache/2.4.38 (Debian)
< Content-Length: 285
< Keep-Alive: timeout=5, max=100
< Content-Type: text/html; charset=iso-8859-1
< connection: keep-alive
<
<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML 2.0//EN">
<html><head>
<title>403 Forbidden</title>
</head><body>
<h1>Forbidden</h1>
<p>You don't have permission to access /
on this server.<br />
</p>
<hr>
<address>Apache/2.4.38 (Debian) Server at faikvm.com Port 80</address>
</body></html>
* Connection #0 to host faikvm.com left intact
```

The site we chose for a test gives an error page, which mockserver downloaded, and presented to us.

Let's take a look at what MockServer memorized for that page.

* MockServer has a REST API, that accepts JSON formatted requests, and can spit out JSON responses. We're going to ask it to show us all of the requests it has seen since it was started:
```
wire@proxybox:~/docker-squid4/docker-squid$ curl -v -X PUT "http://faikvm.com/mockserver/retrieve?type=REQUESTS"
*   Trying 10.0.0.1...
* Connected to faikvm.com (10.0.0.1) port 80 (#0)
> PUT /mockserver/retrieve?type=REQUESTS HTTP/1.1
> Host: faikvm.com
> User-Agent: curl/7.47.0
> Accept: */*
>
< HTTP/1.1 200 OK
< access-control-allow-origin: *
< access-control-allow-methods: CONNECT, DELETE, GET, HEAD, OPTIONS, POST, PUT, PATCH, TRACE
< access-control-allow-headers: Allow, Content-Encoding, Content-Length, Content-Type, ETag, Expires, Last-Modified, Location, Server, Vary, Authorization
< access-control-expose-headers: Allow, Content-Encoding, Content-Length, Content-Type, ETag, Expires, Last-Modified, Location, Server, Vary, Authorization
< access-control-max-age: 300
< x-cors: MockServer CORS support enabled by default, to disable ConfigurationProperties.enableCORSForAPI(false) or -Dmockserver.enableCORSForAPI=false
< version: 5.6.0
< connection: keep-alive
< content-type: application/json; charset=utf-8
< content-length: 231
<
[ {
  "method" : "GET",
  "path" : "/",
  "headers" : {
    "Host" : [ "faikvm.com" ],
    "User-Agent" : [ "curl/7.47.0" ],
    "Accept" : [ "*/*" ],
    "content-length" : [ "0" ]
  },
  "keepAlive" : true,
  "secure" : false
* Connection #0 to host faikvm.com left intact
} ]
```

This shows a single request, for '/', on the host 'faikvm.com'.

* Now, let's download the whole request and response:
```
wire@proxybox:~/docker-squid4/docker-squid$ curl -v -X PUT "http://faikvm.com/mockserver/retrieve?type=RECORDED_EXPECTATIONS" -d '{"path":"/"}'
*   Trying 10.0.0.1...
* Connected to faikvm.com (10.0.0.1) port 80 (#0)
> PUT /mockserver/retrieve?type=RECORDED_EXPECTATIONS HTTP/1.1
> Host: faikvm.com
> User-Agent: curl/7.47.0
> Accept: */*
> Content-Length: 12
> Content-Type: application/x-www-form-urlencoded
>
* upload completely sent off: 12 out of 12 bytes
< HTTP/1.1 200 OK
< access-control-allow-origin: *
< access-control-allow-methods: CONNECT, DELETE, GET, HEAD, OPTIONS, POST, PUT, PATCH, TRACE
< access-control-allow-headers: Allow, Content-Encoding, Content-Length, Content-Type, ETag, Expires, Last-Modified, Location, Server, Vary, Authorization
< access-control-expose-headers: Allow, Content-Encoding, Content-Length, Content-Type, ETag, Expires, Last-Modified, Location, Server, Vary, Authorization
< access-control-max-age: 300
< x-cors: MockServer CORS support enabled by default, to disable ConfigurationProperties.enableCORSForAPI(false) or -Dmockserver.enableCORSForAPI=false
< version: 5.6.0
< connection: keep-alive
< content-type: application/json; charset=utf-8
< content-length: 1127
<
[ {
  "httpRequest" : {
    "method" : "GET",
    "path" : "/",
    "headers" : {
      "Host" : [ "faikvm.com" ],
      "User-Agent" : [ "curl/7.47.0" ],
      "Accept" : [ "*/*" ],
      "content-length" : [ "0" ]
    },
    "keepAlive" : true,
    "secure" : false
  },
  "httpResponse" : {
    "statusCode" : 403,
    "reasonPhrase" : "Forbidden",
    "headers" : {
      "Date" : [ "Mon, 22 Jul 2019 14:26:01 GMT" ],
      "Server" : [ "Apache/2.4.38 (Debian)" ],
      "Content-Length" : [ "285" ],
      "Keep-Alive" : [ "timeout=5, max=100" ],
      "Content-Type" : [ "text/html; charset=iso-8859-1" ],
      "connection" : [ "keep-alive" ]
    },
    "body" : {
      "type" : "STRING",
      "string" : "<!DOCTYPE HTML PUBLIC \"-//IETF//DTD HTML 2.0//EN\">\n<html><head>\n<title>403 Forbidden</title>\n</head><body>\n<h1>Forbidden</h1>\n<p>You don't have permission to access /\non this server.<br />\n</p>\n<hr>\n<address>Apache/2.4.38 (Debian) Server at faikvm.com Port 80</address>\n</body></html>\n",
      "contentType" : "text/html; charset=iso-8859-1"
    }
  },
  "times" : {
    "remainingTimes" : 1
  }
* Connection #0 to host faikvm.com left intact
```
note that while we specified a path, specifying is not necessary, and will download every request this instance of mockserver has seen.


The JSON returned by mockserver is broken into three sections: the request, the response, and the number of times that MockServer saw that response.

Let's save this.
```
curl -v -X PUT "http://faikvm.com/mockserver/retrieve?type=RECORDED_EXPECTATIONS" -d '{"path":"/"}' -o faikvm.com-slash
```

Before we can force mockserver to regurgitate this result on command, we have to keep in mind that there are three unique identifiers in this request we need to remove: the User-Agent, as it contains the version of Curl, and might be different on our target machine, the Date, as that obviously changes, and the 'times' section, as we want to replay this result more than once.

* Using jq, and grep, remove User-Agent, Date, and 'times':
```
wire@proxybox:~/docker-squid4/docker-squid$ cat faikvm.com-slash | grep -v User-Agent | grep -v Date | jq '[.[0]|{httpRequest, httpResponse}]' > faikvm.com-slash-ready
```

* stop mockserver:
```
wire@proxybox:~/docker-squid4/docker-squid$ docker container ls | grep mockserver
f87e4ddc4a51        jamesdbloom/mockserver:mockserver-5.6.0   "/opt/mockserver/run…"   About an hour ago   Up About an hour    0.0.0.0:80->1080/tcp   vigorous_ardinghelli
wire@proxybox:~/docker-squid4/docker-squid$ docker container stop f87e4ddc4a51
f87e4ddc4a51
```

* Start a new mockserver.
```
./run_mockserver.sh 205.166.94.162 80
```

* Load our saved request/response into MockServer:
```
wire@proxybox:~/docker-squid4/docker-squid$ curl -v -X PUT "http://faikvm.com/mockserver/expectation" --data @faikvm.com-slash-ready
*   Trying 10.0.0.1...
* Connected to faikvm.com (10.0.0.1) port 80 (#0)
> PUT /mockserver/expectation HTTP/1.1
> Host: faikvm.com
> User-Agent: curl/7.47.0
> Accept: */*
> Content-Length: 1125
> Content-Type: application/x-www-form-urlencoded
> Expect: 100-continue
>
< HTTP/1.1 100 Continue
* We are completely uploaded and fine
< HTTP/1.1 201 Created
< access-control-allow-origin: *
< access-control-allow-methods: CONNECT, DELETE, GET, HEAD, OPTIONS, POST, PUT, PATCH, TRACE
< access-control-allow-headers: Allow, Content-Encoding, Content-Length, Content-Type, ETag, Expires, Last-Modified, Location, Server, Vary, Authorization
< access-control-expose-headers: Allow, Content-Encoding, Content-Length, Content-Type, ETag, Expires, Last-Modified, Location, Server, Vary, Authorization
< access-control-max-age: 300
< x-cors: MockServer CORS support enabled by default, to disable ConfigurationProperties.enableCORSForAPI(false) or -Dmockserver.enableCORSForAPI=false
< version: 5.6.0
< connection: keep-alive
< content-length: 0
<
* Connection #0 to host faikvm.com left intact
```

Shut off internet to your proxybox. for my setup, my proxybox is in a VM that is IP Masqueraded to the internet, so i can just:
```
julial@Ubuntu-1804-bionic-64-minimal:~$ sudo iptables -t nat -D POSTROUTING -s 172.16.0.0/24 -o eno1 -j MASQUERADE
```
Your method may vary.

Finally, i can perform the same request i did at the beginning, and get the same reply, even though the internet is offline:
```
wire@proxybox:~$ curl -v faikvm.com
* Rebuilt URL to: faikvm.com/
*   Trying 10.0.0.1...
* Connected to faikvm.com (10.0.0.1) port 80 (#0)
> GET / HTTP/1.1
> Host: faikvm.com
> User-Agent: curl/7.47.0
> Accept: */*
>
< HTTP/1.1 403 Forbidden
< Server: Apache/2.4.38 (Debian)
< Content-Length: 285
< Keep-Alive: timeout=5, max=100
< Content-Type: text/html; charset=iso-8859-1
< connection: keep-alive
<
<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML 2.0//EN">
<html><head>
<title>403 Forbidden</title>
</head><body>
<h1>Forbidden</h1>
<p>You don't have permission to access /
on this server.<br />
</p>
<hr>
<address>Apache/2.4.38 (Debian) Server at faikvm.com Port 80</address>
</body></html>
* Connection #0 to host faikvm.com left intact
```

## Using MockServer with HTTPS:

For our second example, we're going to dig into a complicated REST API, served over HTTPS. specifically, we're going to capture and playback the part of a registry API thats necessary for a 'docker manifest inspect'.

### Gathering Data:

In order to mock enough of the docker protocol to perform a 'docker manifest inspect', we first need to know all of the sites involved. to do this, start your squid-MITM, and let's look at the logs that are generated when our target command is run.

* Proxybox:
```
./run.sh
```

* Client machine:
```
wire@admin:~$ docker manifest inspect jamesdbloom/mockserver:mockserver-5.6.0
```

looking at the squid logs under mnt/log/access.log, we see the following:
```
1564054187.770    296 127.0.0.1 NONE_NONE/-/200 0 127.0.0.1:3130 34.199.77.19
1564054188.284    415 10.0.0.38 TCP_MISS/401/401 539 https://registry-1.docker.io/v2/ 34.199.77.19
1564054188.595    290 127.0.0.1 NONE_NONE/-/200 0 127.0.0.1:3130 34.233.151.211
1564054189.024    426 10.0.0.38 TCP_REFRESH_MODIFIED/200/200 4523 https://auth.docker.io/token? 34.233.151.211
1564054189.326    294 127.0.0.1 NONE_NONE/-/200 0 127.0.0.1:3130 34.206.236.31
1564054189.801    465 10.0.0.38 TCP_MISS/200/200 2548 https://registry-1.docker.io/v2/jamesdbloom/mockserver/manifests/mockserver-5.6.0 34.206.236.31
1564054190.106    296 127.0.0.1 NONE_NONE/-/200 0 127.0.0.1:3130 52.22.67.152
1564054190.511    400 10.0.0.38 TCP_REFRESH_MODIFIED/200/200 4525 https://auth.docker.io/token? 52.22.67.152
1564054190.804    288 127.0.0.1 NONE_NONE/-/200 0 127.0.0.1:3130 34.199.77.19
1564054190.957    143 10.0.0.38 TCP_MISS/307/307 824 https://registry-1.docker.io/v2/jamesdbloom/mockserver/blobs/sha256:dc2c6014c1ce28ad8a769259bb28a2bb36fa7ed5c2ceaf52fe8d57ece21a0309 34.199.77.19
1564054191.076     34 127.0.0.1 NONE_NONE/-/200 0 127.0.0.1:3130 104.18.121.25
1564054191.145     57 10.0.0.38 TCP_MISS/200/200 8391 https://production.cloudflare.docker.com/registry-v2/docker/registry/v2/blobs/sha256/dc/dc2c6014c1ce28ad8a769259bb28a2bb36fa7ed5c2ceaf52fe8d57ece21a0309/data? 104.18.121.25
```

Because each request goes first through haproxy, it is generating exactly two log entries in squid. The first entry gives where squid saw the request coming from and going to, and the second entry takes the content given by haproxy and the http session into account. Let's filter out the first of the two entries.
```
1564054188.284    415 10.0.0.38 TCP_MISS/401/401 539 https://registry-1.docker.io/v2/ 34.199.77.19
1564054189.024    426 10.0.0.38 TCP_REFRESH_MODIFIED/200/200 4523 https://auth.docker.io/token? 34.233.151.211
1564054189.801    465 10.0.0.38 TCP_MISS/200/200 2548 https://registry-1.docker.io/v2/jamesdbloom/mockserver/manifests/mockserver-5.6.0 34.206.236.31
1564054190.511    400 10.0.0.38 TCP_REFRESH_MODIFIED/200/200 4525 https://auth.docker.io/token? 52.22.67.152
1564054190.957    143 10.0.0.38 TCP_MISS/307/307 824 https://registry-1.docker.io/v2/jamesdbloom/mockserver/blobs/sha256:dc2c6014c1ce28ad8a769259bb28a2bb36fa7ed5c2ceaf52fe8d57ece21a0309 34.199.77.19
1564054191.145     57 10.0.0.38 TCP_MISS/200/200 8391 https://production.cloudflare.docker.com/registry-v2/docker/registry/v2/blobs/sha256/dc/dc2c6014c1ce28ad8a769259bb28a2bb36fa7ed5c2ceaf52fe8d57ece21a0309/data? 104.18.121.25
```

Looking at that, we can see that this one command contacts three web sites over https, in order to request this one document:
```
registry-1.docker.io
auth.docker.io
production.cloudflare.docker.com
```

Let's look up the SSL CNs given by those three hosts:
```
wire@proxybox:~/docker-squid4/docker-squid$ openssl s_client -host registry-1.docker.io -port 443 2>&1 | grep subject
subject=/CN=*.docker.io
^C
wire@proxybox:~/docker-squid4/docker-squid$ openssl s_client -host auth.docker.io -port 443 2>&1 | grep subject
subject=/CN=*.docker.io
^C
wire@proxybox:~/docker-squid4/docker-squid$ openssl s_client -host production.cloudflare.docker.com -port 443 2>&1 | grep subject
subject=/OU=Domain Control Validated/OU=PositiveSSL Multi-Domain/CN=ssl870612.cloudflaressl.com
^C
wire@proxybox:~/docker-squid4/docker-squid$
```

### Pointing MockServer, and gathering results:

Because this is three separate sites, we're going to have to point mockserver's proxy mode to each one, one at a time.

#### First Site: registry-1.docker.io:

As in our HTTP example, edit /etc/dnsmasq/mockserver to point registry-1.docker.io to mockserver:
```
address=/registry-1.docker.io/10.0.0.1
```

* After any edit of /etc/dnsmasq.d/mockserver, re-start dnsmasq for your change to go into effect:
```
sudo service dnsmasq restart
```

* Launch mockserver in proxy mode, pointing to the real registry-1.docker.io:
```
./run_mockserver.sh 34.199.77.19 443 '*.docker.io'
```
Note that we used the IP from the squid log, along with the default port for https, and the CN that we got back from our openssl query.

* Run our target command on a client machine again:
```
wire@admin:~$ docker manifest inspect jamesdbloom/mockserver:mockserver-5.6.0
```

* Save the content that mockserver proxied:
```
curl -v -X PUT "https://registry-1.docker.io/mockserver/retrieve?type=RECORDED_EXPECTATIONS" -o registry-1.docker.io-all
```

#### Second site: auth.docker.io:

* update dnsmasq for the new domain name, removing the last one we used:
```
address=/auth.docker.io/10.0.0.1
```

* restart dnsmasq for the change to go into effect:
```
sudo service dnsmasq restart
```

* shut down the old mockserver, and launch a new one, pointing to the new site:
```
wire@proxybox:~/docker-squid4/docker-squid$ docker container ls
CONTAINER ID        IMAGE                                     COMMAND                  CREATED             STATUS              PORTS                              NAMES
4ec99df446a4        jamesdbloom/mockserver:mockserver-5.6.0   "/opt/mockserver/run…"   2 seconds ago       Up 1 second         1080/tcp, 0.0.0.0:443->10443/tcp   pedantic_allen
wire@proxybox:~/docker-squid4/docker-squid$ docker container stop 4ec99df446a4
4ec99df446a4
wire@proxybox:~/docker-squid4/docker-squid$ ./run_mockserver.sh 34.233.151.211 443 '*.docker.io'
```

* Run our target command on a client machine again:
```
wire@admin:~$ docker manifest inspect jamesdbloom/mockserver:mockserver-5.6.0
```

* Save the content that mockserver proxied:
```
curl -v -X PUT "https://auth.docker.io/mockserver/retrieve?type=RECORDED_EXPECTATIONS" -o auth.docker.io-all
```

#### Final site: production.cloudflare.docker.com:

* update dnsmasq for the new domain name, removing the last one we used:
```
address=/production.cloudflare.docker.com/10.0.0.1
```

* restart dnsmasq for the change to go into effect:
```
sudo service dnsmasq restart
```

* shut down the old mockserver, and launch a new one, pointing to the new site:
```
wire@proxybox:~/docker-squid4/docker-squid$ docker container ls
CONTAINER ID        IMAGE                                     COMMAND                  CREATED             STATUS              PORTS                              NAMES
4210b04c5ce9        jamesdbloom/mockserver:mockserver-5.6.0   "/opt/mockserver/run…"   2 hours ago         Up 2 hours          1080/tcp, 0.0.0.0:443->10443/tcp   youthful_cori
wire@proxybox:~/docker-squid4/docker-squid$ docker container stop 4210b04c5ce9
4210b04c5ce9
wire@proxybox:~/docker-squid4/docker-squid$ ./run_mockserver.sh 104.18.121.25 443 "ssl870612.cloudflaressl.com"
```
NOTE: something's funky about cloudflare. sometimes this works, sometimes it doesn't. needs more analysis. MockServer thinks everything's fine, squid aborts? maybe docker networking again?


* Run our target command on a client machine again:
```
wire@admin:~$ docker manifest inspect jamesdbloom/mockserver:mockserver-5.6.0
```

* Save the content that mockserver proxied:
```
curl -k -v -X PUT "https://production.cloudflare.docker.com/mockserver/retrieve?type=RECORDED_EXPECTATIONS" -o production.cloudflace.docker.com-all
```
NOTE: we added '-k' to the CURL command line, so that curl would ignore the fact that the SSL cert does not match the DNS name.

### Cleaning results:

There's two things we need to worry about when converting from our saved expectations to expectaitions ready to use: unnecessary unique identifiers, and removing the 'times' blocks so that requests are responded to more than once.

#### First Site: registry-1.docker.io:

From looking at our output file, we can see there are three URLs requested from this site: /v2/, /v2/jamesdbloom/mockserver/manifests/mockserver-5.6.0, and /v2/jamesdbloom/mockserver/blobs/sha256:<sha256sum>. Each one is requested exactly once.

Since MockServer's output is reasonably "key : walue", we can use grep -v to remove entries.

* cat registry-1.docker.io-all, remove the following entries with 'grep -v', and store the results in registry-1.docker.io-all-postgrep:
```
User-Agent
Via
Date
Authorization
```
```
cat registry-1.docker.io-all | grep -v '"User-Agent"' | grep -v '"Via"' | grep -v '"Date"' | grep -v '"Authorization"' > registry-1.docker.io-all-postgrep
```

For removing the markers mockserver uses to tell how many times it saw a specific request, we can use jq. instead of telling it to remove things, we're just going to tell it to display the things that are not in 'times' blocks. note that jq tries to pretty print the file, removing the 'key : value' on a single that we depended on to abuse grep in the last step.
```
cat registry-1.docker.io-all-postgrep | jq '[.[]|{httpRequest,httpResponse}]' > registry-1.docker.io-all-postjq
```

#### Second Site: auth.docker.io:

Looking at our output file, you can see that '/token' is hit twice, and recieves two almost identical tokens. We're just going to repeat the first token given, even if the token is expired... because we know docker is going to use that token to talk to us.

* cat auth.docker.io-all, remove the following fields with 'grep -v', and store the results in auth.docker.io-all-postgrep
```
User-Agent
Via
Date
If-Modified-Since
```
```
cat auth.docker.io-all | grep -v '"User-Agent"' | grep -v '"If-Modified-Since"' | grep -v '"Via"' | grep -v '"Date"' > auth.docker.io-all-postgrep
```

* Use jq to only display the first entry (we do not need different tokens), and drop the 'times' section on the floor:
```
cat auth.docker.io-all-postgrep | jq '[.[0]|{httpRequest,httpResponse}]' > auth.doker.io-all-postjq
```

#### Third site: production.cloudflace.docker.com:

This site only recieved one request as well, two times. it was to /registry-v2/docker/registry/v2/blobs/sha256/<first two of shasum>/<shasum>/data , and is where the actual manifest is stored.

This is a cloudflare site, so there are a lot of cloudflare specific headers in the response that we're going to filter out.

* cat production.cloudflare.docker.com-all, and use 'grep -v' to remove the following header entries, storing the results in production.cloudflare.docker.com-all-postgrep
```
User-Agent
Via
Date
Set-Cookie
CF-Cache-Status
CF-Ray
Expect-CT
Expires
x-amz-id-2
x-amz-request-id
x-amz-version-id
Server
```
```
cat production.cloudflare.docker.com-all | grep -v '"User-Agent"' | grep -v '"Via"' | grep -v '"Date"' | grep -v '"Set-Cookie"' | grep -v '"CF-Cache-Status"' | grep -v '"CF-Ray"' | grep -v '"Expect-CT"' | grep -v '"Expires"' | grep -v '"x-amz-id-2"' | grep -v '"x-amz-request-id"' | grep -v '"x-amz-version-id"' | grep -v '"Server"' > production.cloudflare.docker.com-all-postgrep
```

* Use jq to only display the first entry (we do not need different responses), and drop the 'times' section on the floor:
```
cat production.cloudflare.docker.com-all-postgrep | jq '[.[0]|{httpRequest,httpResponse}]' > production.cloudflare.docker.com-all-postjq
```

### Putting it all together:

* Edit /etc/dnsmasq/mockserver to redirect all three sites to point to mockserver:
```
address=/registry-1.docker.io/10.0.0.1
address=/auth.docker.io/10.0.0.1
address=/production.cloudflare.docker.com/10.0.0.1
```

* Restart dnsmasq for the changes to go into effect:
```
sudo service dnsmasq restart
```

* stop mockserver.
```
wire@proxybox:~/docker-squid4/docker-squid$ docker container ls
CONTAINER ID        IMAGE                                     COMMAND                  CREATED             STATUS              PORTS                              NAMES
41cec4af78ee        jamesdbloom/mockserver:mockserver-5.6.0   "/opt/mockserver/run…"   5 days ago          Up 5 days           1080/tcp, 0.0.0.0:443->10443/tcp   cocky_feynman
wire@proxybox:~/docker-squid4/docker-squid$ docker container stop 41cec4af78ee
```

* Start a new mockserver, with a clearly fake upstream to forward to. since we saw multiple ssl certificates, we're asking mockserver to create one cert, with a SAN of the second cert:
```
./run_mockserver.sh 169.254.0.1 443 "*.docker.io" "ssl870612.cloudflaressl.com"
```

* Upload all of our "-postjq" files into mockserver:
```
curl -v -X PUT "https://auth.docker.io/mockserver/expectation" --data @auth.docker.io-all-postjq
curl -v -X PUT "https://auth.docker.io/mockserver/expectation" --data @production.cloudflare.docker.com-all-postjq
curl -v -X PUT "https://auth.docker.io/mockserver/expectation" --data @registry-1.docker.io-all-postjq
```

* shut down internet to the proxybox. for my setup, this is:
```
julial@Ubuntu-1804-bionic-64-minimal:~$ sudo iptables -t nat -D POSTROUTING -s 172.16.0.0/24 -o eno1 -j MASQUERADE
```
Your method may vary.


* try the docker manifest command again, from the client machine. should work, and show you the version of the manifest now saved in our postjq files:
```
wire@admin:~$ docker manifest inspect jamesdbloom/mockserver:mockserver-5.6.0
```

Success!


