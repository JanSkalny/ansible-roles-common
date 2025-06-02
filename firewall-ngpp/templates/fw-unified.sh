#! /bin/sh
#
# {{ ansible_managed }}
# Template: fw-unified.sh
#

{%- macro lookup_object(name) -%}
{% if name in firewall_objects %}
{# make sure object is array of names or addresses #}
{% set obj = firewall_objects[name] %}
{% set entries = obj if obj is iterable and obj is not string else[obj] %}
{% set results = [] %}
{% for name_or_addr in entries %}
{% set trimmed = name_or_addr.strip() %}
{% if trimmed in firewall_objects %}
{{ lookup_object(trimmed) }}
{% else %}
{% if trimmed | ansible.utils.ipaddr or trimmed.startswith('!') %}
{{ trimmed }}
{% else %}
{{ xxx_invalid|mandatory("Nested object not found and direct DNS referencing not allowed: "+trimmed) }}
{% endif %}
{% endif %}
{% endfor %}
{% else %}
{{ xxx_invalid|mandatory("Referenced invalid object and direct DNS referencing not allowed: "+name) }}
{% endif %}
{%- endmacro -%}

{%- macro normalize_addrs(rule, attr) -%}
{% if attr in rule %}
{% set attrs = ( rule[attr].replace(' ','').split(',') if rule[attr] is string else rule[attr] ) %}
{% for name_or_addr in attrs %}
{% set trimmed = name_or_addr.strip() %}
{% if trimmed in firewall_objects %}
{{ lookup_object(trimmed) }}
{% else %}
{% if trimmed | ansible.utils.ipaddr or trimmed.startswith('!') %}
{{ trimmed }}
{% else %}
{{ xxx_invalid|mandatory("Object not found and direct DNS referencing not allowed: "+name_or_addr+" rule="+(rule|to_json)) }}
{% endif %}
{% endif %}
{% endfor %}
{% endif %}
{%- endmacro -%}

{%- macro normalize_ports(rule, proto) -%}
{%- set ports = rule.proto[proto] if rule.get('proto', {}).get(proto) is not none else [] %}
{%- if ports is string %}
  {%- set ports = ports.replace(' ', '').split(',') %}
{%- elif ports is number %}
  {%- set ports = [ports] %}
{%- endif %}
{{ ports | sort | unique | join(',') }}
{%- endmacro -%}

{%- macro format_addr(match,addr) -%}
  {%- set trimmed = addr.strip() %}
  {%- if trimmed == "ANY" %}
  {%- elif trimmed.startswith('!') %}
    {%- set addrs = trimmed[1:].split() %}
    {%- for addr in addrs %}
 ! {{ match }} {{ addr }} 
    {%- endfor %}
  {%- else %}
 {{ match }} {{ trimmed }}
  {%- endif %}
{%- endmacro -%}

{%- macro format_proto(proto,param) -%}
{% set proto = proto.strip() %}
{% set param = param.strip() %}
{%- if proto != "ANY" %}
 -p {{ proto }}
{%- if param != "ANY" %}
{%- if proto in ['tcp','udp','sctp'] %}
 --dport {{ param }}
{%- elif proto == 'icmp' %}
 --icmp-type {{ param }}
{%- elif proto == 'icmp6' %}
 --icmpv6-type {{ param }}
{%- endif -%}
{%- endif -%}
{%- endif -%}
{%- endmacro -%}


{%- macro generate_rule(rule, chain, default_action='LOG_ACCEPT', ip_ver=4) -%}
# {{ rule | to_json }}
{% set src_raw = normalize_addrs(rule, 'src').split('\n') | difference(['']) | sort %}
{% set dst_raw = normalize_addrs(rule, 'dst').split('\n') | difference(['']) | sort %}
# src addrs: {{ src_raw }}
# dst addrs: {{ dst_raw }}
{% set src_addrs = src_raw if src_raw else ['ANY'] %}
{% set dst_addrs = dst_raw if dst_raw else ['ANY'] %}
{% set src_list = " -m set --match-set "+rule.src_list+" src " if rule.src_list|default(False) else "" %}
{% for src_addr in (src_addrs | sort ) -%}
{%- for dst_addr in (dst_addrs | sort ) -%}
{% set src = format_addr("-s", src_addr) %}
{% set dst = format_addr("-d", dst_addr) %}
{% if ((ip_ver == 4 and ('.' in src or '.' in dst)) or (ip_ver == 6 and (':' in src or ':' in dst)) or (src == "ANY" and dst == "ANY")) %}
{% for rule_proto, rule_ports in (rule.proto if rule.proto is defined else {"ANY": "ANY"}).items() %}
{% set raw_ports = normalize_ports(rule, rule_proto).split(',') | default([]) | difference(['']) | sort %}
{% set rule_ports = raw_ports if raw_ports else ['ANY'] %}
{% for port in rule_ports %}
{% set proto = format_proto(rule_proto, port) %}
$IT{{ ip_ver }} -A {{ chain }}{{ proto }}{{ src_list }}{{ src }}{{ dst }} -j {{ rule.rule | default(default_action) }}
{% endfor %}
{% endfor %}
{% endif %}
{% endfor %}
{% endfor %}
{%- endmacro -%}


#
# Simple iptables management script (fw.sh)

### BEGIN INIT INFO
# Provides:          fw.sh
# Required-Start:    $local_fs $network
# Required-Stop:     $local_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: fw.sh
# Description:       firewall
### END INIT INFO

IT4="{{ firewall_iptables }}"
IT6="{{ firewall6_iptables }}"

# flush nftables for fun and profit
nft flush ruleset

# load additional modules
for M in ip_conntrack ip_conntrack_ftp ip_conntrack_sip; do
  modprobe $M 2>/dev/null
done

echo {{ firewall_ip_forward | default(0) | int }} > /proc/sys/net/ipv4/ip_forward
echo {{ firewall6_ip_forward | default(0) | int }} > /proc/sys/net/ipv6/conf/all/forwarding
echo 1 > /proc/sys/net/ipv4/tcp_syncookies
echo {{ firewall_rp_filter | default(1) | int }} > /proc/sys/net/ipv4/conf/all/rp_filter
echo 0 > /proc/sys/net/ipv4/conf/all/log_martians
echo {{ firewall_log_martians | default(1) | int }} > /proc/sys/net/ipv4/conf/default/log_martians
echo 1 > /proc/sys/net/ipv4/icmp_echo_ignore_broadcasts
echo 1 > /proc/sys/net/ipv4/icmp_ignore_bogus_error_responses
echo 0 > /proc/sys/net/ipv4/conf/all/send_redirects
echo 0 > /proc/sys/net/ipv4/conf/all/accept_source_route
echo 0 > /proc/sys/net/ipv6/conf/all/accept_source_route

{% for iface in firewall_no_martians_ifaces | default([]) %}
echo 0 > /proc/sys/net/ipv4/conf/{{ iface }}/log_martians
{% endfor %}

for PROTO in 4 6; do
  IT=$( eval echo \$IT$PROTO )
  X=$( [ $PROTO -eq 6 ] && echo "6" )

  # flush tables
  for TABLE in filter nat mangle; do
    $IT -t $TABLE -F
    $IT -t $TABLE -X
  done

  # default rulesets
  $IT -P INPUT DROP
  $IT -P OUTPUT DROP
  $IT -P FORWARD DROP

  # custom REJECT action with logging
  $IT -N LOG_REJECT
    $IT -A LOG_REJECT -m limit --limit 10/sec --limit-burst 20 -j LOG \
      --log-ip-options --log-tcp-options --log-uid \
      --log-prefix "FW${PROTO}-REJECT " --log-level info
    $IT -A LOG_REJECT -m limit --limit 10/sec --limit-burst 20 -j REJECT \
      --reject-with icmp$X-port-unreachable
    $IT -A LOG_REJECT -j DROP

  # custom DROP action with logging
  $IT -N LOG_DROP
    $IT -A LOG_DROP -m limit --limit 10/sec --limit-burst 20 -j LOG \
      --log-ip-options --log-tcp-options --log-uid \
      --log-prefix "FW${PROTO}-DROP " --log-level info
    $IT -A LOG_DROP -j DROP

  # custom ACCEPT action with logging
  $IT -N LOG_ACCEPT
    $IT -A LOG_ACCEPT -m limit --limit 50/sec --limit-burst 100 -j LOG \
      --log-ip-options --log-tcp-options --log-uid \
      --log-prefix "FW${PROTO}-ACCEPT " --log-level info
    $IT -A LOG_ACCEPT -j ACCEPT

  # custom ACCEPT action with logging
  $IT -N LOG_WILL_DROP
    $IT -A LOG_WILL_DROP -m limit --limit 50/sec --limit-burst 100 -j LOG \
      --log-ip-options --log-tcp-options --log-uid \
      --log-prefix "FW${PROTO}-WILL-DROP " --log-level info
    $IT -A LOG_WILL_DROP -j ACCEPT

  # custom ACCEPT actions with special log messages
{% for rule in firewall_accept_rules|default([]) %}
  $IT -N LOG_ACCEPT_{{ rule | upper }}
    $IT -A LOG_ACCEPT_{{ rule | upper }} -m limit --limit 50/sec --limit-burst 100 -j LOG \
      --log-ip-options --log-tcp-options --log-uid \
      --log-prefix "FW${PROTO}-ACCEPT-{{ rule | upper }} " --log-level info
    $IT -A LOG_ACCEPT_{{ rule | upper }} -j ACCEPT
{% endfor %}

  # custom WILL-DROP actions with special log messages
{% for rule in firewall_will_drop_rules|default([]) %}
  $IT -N LOG_WILL_DROP_{{ rule | upper }}
    $IT -A LOG_WILL_DROP_{{ rule | upper }} -m limit --limit 50/sec --limit-burst 100 -j LOG \
      --log-ip-options --log-tcp-options --log-uid \
      --log-prefix "FW${PROTO}-WILL-DROP-{{ rule | upper }} " --log-level info
    $IT -A LOG_WILL_DROP_{{ rule | upper }} -j ACCEPT
{% endfor %}

  # custom DROP actions with special log messages
{% for rule in firewall_drop_rules|default([]) %}
  $IT -N LOG_DROP_{{ rule | upper }}
    $IT -A LOG_DROP_{{ rule | upper }} -m limit --limit 10/sec --limit-burst 20 -j LOG \
      --log-ip-options --log-tcp-options --log-uid \
      --log-prefix "FW${PROTO}-DROP-{{ rule | upper }} " --log-level info
    $IT -A LOG_DROP_{{ rule | upper }} -j DROP
{% endfor %}

done
IT=""


############################################################
### verify source address of packet (RFC 2827, RFC 1918)

$IT4 -N CHECK_IF
  # allow dhcp on specific interfaces
{% for firewall_iface_name, firewall_iface in firewall_interfaces.items() %}
{% if firewall_iface.allow_dhcp | default(False) %}
  $IT4 -A CHECK_IF -i {{ firewall_iface_name }} -s 0.0.0.0 -j RETURN # DHCP
{% endif %}
{% endfor %}

{% if not (firewall_iface.allow_igmp | default(True)) %}
  # IGMP
  $IT4 -A CHECK_IF -s 0.0.0.0/8 -d 224.0.0.1 -p 2 -j LOG_DROP_CHECKIF_IGMP
{% endif %}

  # don't accept APIPA addresses
  $IT4 -A CHECK_IF -s 169.254.0.0/16 -j DROP

  # no-one can send from special address ranges!
  $IT4 -A CHECK_IF -s 127.0.0.0/8 -j LOG_DROP_CHECKIF_SPOOF      # loopback
  $IT4 -A CHECK_IF -s 0.0.0.0/8 -j LOG_DROP_CHECKIF_DHCP         # DHCP
  $IT4 -A CHECK_IF -s 192.0.2.0/24 -j LOG_DROP_CHECKIF_SPOOF     # RFC 3330
  $IT4 -A CHECK_IF -s 204.152.64.0/23 -j LOG_DROP_CHECKIF_SPOOF  # RFC 3330
  $IT4 -A CHECK_IF -s 224.0.0.0/3 -j LOG_DROP_CHECKIF_SPOOF      # multicast

  #XXX: no per-interface rule evaluation yet
  $IT4 -A CHECK_IF -j RETURN

$IT6 -N CHECK_IF
  # disable IPv6 source routing (and ping-pong)
  $IT6 -A CHECK_IF -m rt --rt-type 0 -j LOG_DROP_HACK

  # allow link-local addresses only with hl 255
  $IT6 -A CHECK_IF -s fe80::/10 -m hl --hl-eq 255 -j RETURN
  #TODO: replace following rule with DROP_HACK
  $IT6 -A CHECK_IF -s fe80::/10 -j RETURN
  #$IT6 -A CHECK_IF -s fe80::/10 -j LOG_DROP_HACK

  #XXX: no check_if interface rules yet
  $IT6 -A CHECK_IF -j RETURN


############################################################
### allow loopbacks, check origin, and related/established

{% for iface in firewall_whitelisted_ifaces | default(['lo']) %}
  # everything is allowed on {{ iface }}
  $IT4 -A INPUT -i {{ iface }} -j ACCEPT
  $IT6 -A INPUT -i {{ iface }} -j ACCEPT
  $IT4 -A OUTPUT -o {{ iface }} -j ACCEPT
  $IT6 -A OUTPUT -o {{ iface }} -j ACCEPT
{% endfor %}

# check for spoofed addresses
for CHAIN in INPUT FORWARD; do
  $IT4 -A $CHAIN -j CHECK_IF
  $IT6 -A $CHAIN -j CHECK_IF
done

# connection tracking:
# - allow all related/established traffic
# - invalid packets MUST be dropped!
for CHAIN in INPUT FORWARD OUTPUT; do
  $IT4 -A $CHAIN -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  $IT4 -A $CHAIN -m conntrack --ctstate INVALID -j {{ firewall_default_rule_invalid }}
  $IT6 -A $CHAIN -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  $IT6 -A $CHAIN -m conntrack --ctstate INVALID -j {{ firewall_default_rule_invalid }}
done


############################################################
### INPUT ruleset

{% for input_rule in firewall_input|default([]) %}
{{ generate_rule(input_rule, 'INPUT', 'LOG_ACCEPT', 4) }}
{% endfor %}

# ignore broadcasts
{% if firewall_ignore_broadcasts %}
$IT4 -A INPUT -m addrtype --dst-type BROADCAST -j DROP
{% endif %}

# IPv4 ICMP rate limit
$IT4 -A INPUT -p icmp -m limit --limit {{ firewall_ping_rate | default(20) }}/second -j ACCEPT
$IT4 -A INPUT -p icmp -j LOG_DROP_RATELIMIT

# ignore junk from windows servers (samba)
#for PORT in 137 138; do
#  $IT4 -A INPUT -p udp --dport $PORT -j DROP
#done

# default rule is
$IT4 -A INPUT -j {{ firewall_default_rule_input }}


############################################################
### INPUT ruleset (IPv6)

{% for input_rule in firewall_input|default([]) %}
{{ generate_rule(input_rule, 'INPUT', 'LOG_ACCEPT', 6) }}
{% endfor %}

{% if firewall6_allow_all_icmp | default(False) %}
  $IT6 -A INPUT -p ipv6-icmp -j RETURN
{% else %}
  # IPv6 NDP only with hl 255 should be allowed (excpt RA on firewalls - they know how to route)
  $IT6 -A INPUT -p ipv6-icmp --icmpv6-type router-solicitation -m hl --hl-eq 255 -j LOG_ACCEPT
  {% if firewall6_allow_ra %}
  $IT6 -A INPUT -p ipv6-icmp --icmpv6-type router-advertisement -m hl --hl-eq 255 -j LOG_ACCEPT
  {% endif %}
  $IT6 -A INPUT -p ipv6-icmp --icmpv6-type neighbor-solicitation -m hl --hl-eq 255 -j LOG_ACCEPT
  $IT6 -A INPUT -p ipv6-icmp --icmpv6-type neighbor-advertisement -m hl --hl-eq 255 -j LOG_ACCEPT

  # NDP with bigger HL is consider malicious
  $IT6 -A INPUT -p ipv6-icmp --icmpv6-type router-solicitation -j LOG_DROP_HACK
  $IT6 -A INPUT -p ipv6-icmp --icmpv6-type router-advertisement -j LOG_DROP_HACK
  $IT6 -A INPUT -p ipv6-icmp --icmpv6-type neighbor-solicitation -j LOG_DROP_HACK
  $IT6 -A INPUT -p ipv6-icmp --icmpv6-type neighbor-advertisement -j LOG_DROP_HACK

  # IPv6 MLD
  $IT6 -A INPUT -p ipv6-icmp --icmpv6-type 130 -j LOG_ACCEPT
  $IT6 -A INPUT -p ipv6-icmp --icmpv6-type 131 -j LOG_ACCEPT
  $IT6 -A INPUT -p ipv6-icmp --icmpv6-type 132 -j LOG_ACCEPT
  $IT6 -A INPUT -p ipv6-icmp --icmpv6-type 143 -j LOG_ACCEPT

  # IPv6 ICMP PING (rate limited)
  $IT6 -A INPUT -p ipv6-icmp --icmpv6-type echo-request -m limit --limit {{ firewall_ping_rate | default(20) }}/second -j ACCEPT
  $IT6 -A INPUT -p ipv6-icmp --icmpv6-type echo-request -j LOG_DROP_RATELIMIT
{% endif %}

# default rule is
$IT6 -A INPUT -j {{ firewall_default_rule_input }}


############################################################
### OUTPUT ruleset

$IT4 -A OUTPUT -o lo -j ACCEPT
$IT6 -A OUTPUT -o lo -j ACCEPT

{% for output_rule in firewall_output|default([]) %}
{{ generate_rule(output_rule, 'OUTPUT', 'LOG_ACCEPT', 4) }}
{% endfor %}

# default to drop
$IT4 -A OUTPUT -j {{ firewall_default_rule_output }}


############################################################
### OUTPUT ruleset (IPv6)

{% for output_rule in firewall_output|default([]) %}
{{ generate_rule(output_rule, 'OUTPUT', 'LOG_ACCEPT', 6) }}
{% endfor %}

{% if firewall6_allow_all_icmp | default(False) %}
  $IT6 -A OUTPUT -p ipv6-icmp -j RETURN
{% else %}
  # IPv6 NDP only with hl 255 should be allowed
  $IT6 -A OUTPUT -p ipv6-icmp --icmpv6-type router-solicitation -m hl --hl-eq 255 -j LOG_ACCEPT
  $IT6 -A OUTPUT -p ipv6-icmp --icmpv6-type router-advertisement -m hl --hl-eq 255 -j LOG_ACCEPT
  $IT6 -A OUTPUT -p ipv6-icmp --icmpv6-type neighbor-solicitation -m hl --hl-eq 255 -j LOG_ACCEPT
  $IT6 -A OUTPUT -p ipv6-icmp --icmpv6-type neighbor-advertisement -m hl --hl-eq 255 -j LOG_ACCEPT

  # IPv6 MLD
  $IT6 -A OUTPUT -p ipv6-icmp --icmpv6-type 130 -j LOG_ACCEPT
  $IT6 -A OUTPUT -p ipv6-icmp --icmpv6-type 131 -j LOG_ACCEPT
  $IT6 -A OUTPUT -p ipv6-icmp --icmpv6-type 132 -j LOG_ACCEPT
  $IT6 -A OUTPUT -p ipv6-icmp --icmpv6-type 143 -j LOG_ACCEPT

  # IPv6 ICMP PING (rate limited)
  $IT6 -A OUTPUT -p ipv6-icmp --icmpv6-type echo-request -m limit --limit {{ firewall_ping_rate | default(20) }}/second -j ACCEPT
  $IT6 -A OUTPUT -p ipv6-icmp --icmpv6-type echo-request -j LOG_DROP_RATELIMIT
{% endif %}

# default to drop
$IT6 -A OUTPUT -j {{ firewall_default_rule_output }}


############################################################
### FORWARD ruleset

{% for forward_rule in firewall_forward|default([]) %}
{{ generate_rule(forward_rule, 'FORWARD', 'LOG_ACCEPT', 4) }}
{% endfor %}

#TODO: odstranit z produkcie
# IPv4 ICMP rate limit
$IT4 -A FORWARD -p icmp -m limit --limit {{ firewall_ping_rate | default(20) }}/second -j ACCEPT
$IT4 -A FORWARD -p icmp -j LOG_DROP_RATELIMIT

# default rule
$IT4 -A FORWARD -j {{ firewall_default_rule_forward }}


############################################################
### FORWARD ruleset (IPv6)

{% for forward_rule in firewall_forward|default([]) %}
{{ generate_rule(forward_rule, 'FORWARD', 'LOG_ACCEPT', 6) }}
{% endfor %}

{% if firewall6_allow_all_icmp | default(False) %}
  $IT6 -A FORWARD -p ipv6-icmp -j RETURN
{% else %}
  # IPv6 NDP should not be allowed
  $IT6 -A FORWARD -p ipv6-icmp --icmpv6-type router-solicitation -j LOG_DROP_HACK
  $IT6 -A FORWARD -p ipv6-icmp --icmpv6-type router-advertisement -j LOG_DROP_HACK
  $IT6 -A FORWARD -p ipv6-icmp --icmpv6-type neighbor-solicitation -j LOG_DROP_HACK
  $IT6 -A FORWARD -p ipv6-icmp --icmpv6-type neighbor-advertisement -j LOG_DROP_HACK

  # IPv6 MLD is not allowed (we don't need internet-wide multicast)
  $IT6 -A FORWARD -p ipv6-icmp --icmpv6-type 130 -j LOG_DROP_IPV6
  $IT6 -A FORWARD -p ipv6-icmp --icmpv6-type 131 -j LOG_DROP_IPV6
  $IT6 -A FORWARD -p ipv6-icmp --icmpv6-type 132 -j LOG_DROP_IPV6
  $IT6 -A FORWARD -p ipv6-icmp --icmpv6-type 142 -j LOG_DROP_IPV6

  # IPv6 ICMP PING (rate limited)
  $IT6 -A FORWARD -p ipv6-icmp --icmpv6-type echo-request -m limit --limit {{ firewall_ping_rate | default(20) }}/second -j ACCEPT
  $IT6 -A FORWARD -p ipv6-icmp --icmpv6-type echo-request -j LOG_DROP_RATELIMIT
{% endif %}

# default rule
$IT6 -A FORWARD -j {{ firewall_default_rule_forward6 | default(firewall_default_rule_forward) }}


############################################################
### NAT ruleset

{% for firewall_iface_name, firewall_iface in firewall_interfaces.items() %}
{% for net in firewall_iface.masquerade | default([]) %}
$IT4 -t nat -A POSTROUTING -o {{ firewall_iface_name }} -s {{ net }} -j MASQUERADE
{% endfor %}
{% endfor %}

{% for firewall_iface_name, firewall_iface in firewall_interfaces.items() %}
{% for dnat in firewall_iface.dnat | default([]) %}
$IT4 -t nat -A PREROUTING -i {{ firewall_iface_name }} -d {{ dnat.orig_to }} -j DNAT --to-destination {{ dnat.to }}
{% endfor %}
{% endfor %}

############################################################
### custom firewall patches

{% if firewall_final_patch is defined %}
{% for rule in firewall_final_patch %}
{{ rule }}
{% endfor %}
{% endif %}


############################################################

### fail2ban integration
[ -f /etc/init.d/fail2ban ] && /etc/init.d/fail2ban restart

exit 0
