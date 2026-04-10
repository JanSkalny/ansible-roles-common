#! /bin/sh
#
# {{ ansible_managed }}
# Template: fw-unified.sh
#

{%- macro format_addr(match,addr) -%}
  {%- set trimmed = addr.strip() %}
  {%- if trimmed == "ANY" %}
    {{- "" -}}
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
{% set src_addrs = rule | firewall_normalize_addrs('src', firewall_objects) %}
{% set dst_addrs = rule | firewall_normalize_addrs('dst', firewall_objects) %}
{#
# src addrs: {{ src_addrs }}
# dst addrs: {{ dst_addrs }}
#}
{# src ipset match #}
{% set src_list = " -m set --match-set "+rule.src_list+" src " if rule.src_list|default(False) else "" %}
{% for src_addr in src_addrs -%}
{%- for dst_addr in dst_addrs -%}
{# filter out IPv4 addressess from IPv6 rules and vice versa #}
{% set is_v4_addr = ip_ver == 4 and ('.' in src_addr or '.' in dst_addr) %}
{% set is_v6_addr = ip_ver == 6 and (':' in src_addr or ':' in dst_addr) %}
{% set is_any_any = src_addr == "ANY" and dst_addr == "ANY" %}
{% if is_v4_addr or is_v6_addr or is_any_any %}
{# format src/dst addresses using -s / -d #}
{% set src = format_addr("-s", src_addr) %}
{% set dst = format_addr("-d", dst_addr) %}
{% for rule_proto in (rule.proto | default({"ANY": "ANY"})).keys() %}
{% set rule_ports = rule|firewall_normalize_ports(rule_proto) %}
{% for port in rule_ports %}
{# format -p ... --dport ... filter #}
{% set proto = format_proto(rule_proto, port) %}
$IT{{ ip_ver }} -A {{ chain }}{{ proto }}{{ src_list }}{{ src }}{{ dst }} -j {{ rule.rule | default(default_action) }}
{% endfor %}
{% endfor %}
{% endif %}
{% endfor %}
{% endfor %}

{%- endmacro -%}

{%- macro generate_interface_rules(firewall_iface_name, firewall_iface, ip_ver=4) -%}
{% set allow_nets = normalize_addrs(firewall_iface, 'allow', ip_ver).split('\n') | difference(['','ANY']) | sort %}
{% set deny_nets = normalize_addrs(firewall_iface, 'deny', ip_ver).split('\n') | difference(['','ANY']) | sort %}
{% set allow_dst = '-d '+firewall_iface.allow_dst if 'allow_dst' in firewall_iface else '' %}
{% for deny_net in deny_nets %}
  $IT{{ ip_ver }} -A CHECK_IF -i {{ firewall_iface_name }} -s {{ deny_net }} -j {{ firewall_default_rule_checkif_deny }}
{% endfor %}
{% for allow_net in allow_nets %}
  $IT{{ ip_ver }} -A CHECK_IF -i {{ firewall_iface_name }} -s {{ allow_net }} {{ allow_dst }} -j RETURN
{% endfor %}
{% if firewall_iface.default | default('allow' if firewall_interfaces|length == 1 else 'deny') == 'allow' %}
  $IT{{ ip_ver }} -A CHECK_IF -i {{ firewall_iface_name }} {{ allow_dst }} -j RETURN
{% else %}
  $IT{{ ip_ver }} -A CHECK_IF -i {{ firewall_iface_name }} -j {{ firewall_default_rule_checkif }}
{% endif %}
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

# create lists
{% for firewall_list in firewall_lists|default([]) %}
ipset create {{ firewall_list.name }} hash:ip {{ 'timeout '+(firewall_list.ttl|string) if firewall_list.ttl | default(False) else '' }}
{% endfor %}


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

{% for firewall_iface_name, firewall_iface in firewall_interfaces.items() %}
{{ generate_interface_rules(firewall_iface_name, firewall_iface) }}
{% endfor %}

  # everything else is dropped!
  $IT4 -A CHECK_IF -j {{ firewall_default_rule_checkif_global }}


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
{{ firewall_final_patch }}
{% endif %}


############################################################

### fail2ban integration
[ -f /etc/init.d/fail2ban ] && /etc/init.d/fail2ban restart

exit 0
