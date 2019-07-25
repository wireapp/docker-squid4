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

## Pointing mockserver at the site:

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

## Using MockServer:

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


