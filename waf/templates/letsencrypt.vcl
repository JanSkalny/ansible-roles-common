# Forward challenge-requests to certbot, which will listen to port 402
# when issuing letsencrypt requests

backend certbot {
	.host = "127.0.0.1";
	.port = "402";
}

sub vcl_recv {
	if (req.url ~ "^/.well-known/acme-challenge/") {
		set req.backend_hint = certbot;
		return(pass);
	}
}

