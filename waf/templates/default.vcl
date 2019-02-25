# Marker to tell the VCL compiler that this VCL has been adapted to the
# new 4.0 format.
vcl 4.0;

include "/etc/varnish/security/vsf.vcl";
{% if waf_letsencrypt == true %}
include "/etc/varnish/letsencrypt.vcl";
{% endif %}

import directors;

## backends
{% for backend in waf_backends %}
backend {{backend.name}} {
  .host = "{{backend.host}}";
  .port = "80";
{% if 'probe' in backend %}
  .probe = {
    .url = "{{backend.probe.url}}";
    .interval = {{backend.probe.interval}}s;
    .timeout = 1s;
    .window = 5;
    .threshold = 3;
  }
{% endif %}
}
{% endfor %}

## haproxy to ssl backends
backend tls {
  .host = "127.0.0.1";
  .port = "10444";
}

sub vcl_init {
## directors
{% for director in waf_directors %}
  new {{ director.name }} = directors.{{ director.mode }}();
{% for backend in director.backends %}
  {{ director.name }}.add_backend({{ backend }});
{% endfor %}

{% endfor %}
}


## rules
sub vcl_recv {
  # cleanup incoming request
  unset req.http.X-Redir-Url;
  unset req.http.X-Varnish;
  unset req.http.X-VMOD-PARSEREQ-PTR;

  # require Host header
  if (! req.http.Host) {
    return (synth(404, "Need a host header"));
  }

  # normalize request domain (or not :D)
  ###set req.http.Host = regsub(req.http.Host, "^www\.", "");
  set req.http.Host = regsub(req.http.Host, ":[0-9]*$", "");

  # SSL vs non-SSL connection
  if (client.ip == "127.0.0.1" || client.ip == "::1") {
    # X-Forwarded-For is trusted, when it comes from haproxy
    set req.http.X-Forwarded-For = regsub(req.http.X-Forwarded-For, "^([^,]+),?.*$", "\1");
  } else {
    # use clients IP address
    unset req.http.X-Forwarded-For;
    set req.http.X-Forwarded-For = regsub(client.ip, "^([^,]+),?.*$", "\1");
    set req.http.X-Redir-Url = "https://" + req.http.host + req.url;
  }

{% for domain in waf_domains %}
{% with %}
{% set backend = ( waf_backends | selectattr("name", "match", domain.backend) | first ) %}
  # domain={{ domain }}
  # backend={{ backend }}
  if (req.http.host ~ "^(www.)?{{ domain.domain }}$") {
{% if 'https' in domain and domain.https %}
    {% if 'https_redirect' not in backend or backend.https_redirect %}
    if (req.http.X-Redir-Url) {
      return(synth(750, "Redirect to HTTPS"));
    }
    {% endif %}
    {% if 'https' not in backend or backend.https %} 
    set req.backend_hint = tls;
    {% else %}
    set req.backend_hint = {{ domain.backend }};
    {% endif %}
{% else %}
    set req.backend_hint = {{ domain.backend }};
{% endif %}
    return(pass);
  }
{% endwith %}
{% endfor %}

  return (synth(404, "Unknown host"));
}

sub vcl_backend_response {
}

sub vcl_deliver {
}

sub vcl_synth {
  # redirect to X-Redir-Url (perma)
  if (resp.status == 750) {
    set resp.http.Location = req.http.X-Redir-Url;
    set resp.status = 301;
    return(deliver);
  }

  # hacking attempt redirected to rickroll
  if (resp.status == 777) {
    set resp.http.Location = "https://www.youtube.com/watch?v=DLzxrzFCyOs";
    set resp.status = 302;
    return (deliver);
  }
}
