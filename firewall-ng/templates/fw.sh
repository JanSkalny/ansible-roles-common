#! /bin/sh
#
# {{ ansible_managed }}
# Template: fw.sh
#

{%- macro normalize_addrs(rule, attr, ip_ver=4) -%}
{% set firewallx_objects = firewall_objects if ip_ver == 4 else firewall6_objects %}
{% set results = [] %}
{% if attr in rule %}
{% set attrs = ( rule[attr].replace(' ','').split(',') if rule[attr] is string else rule[attr] ) %}
{% for name_or_addr in attrs %}
{% if name_or_addr in firewallx_objects %}
{% set xaddr = firewallx_objects[name_or_addr] %}
{% do results.append(xaddr.replace(' ','').split(',') if xaddr is string else xaddr) %}
{% else %}
{% if name_or_addr | ansible.utils.ipaddr %}
{% do results.append([name_or_addr]) %}
{% else %}
{{ xxx_invalid|mandatory("Object not found and direct DNS referencing not allowed: "+name_or_addr+" ip_ver="+ip_ver|string+" rule="+(rule|to_json)) }}
{% endif %}
{% endif %}
{% endfor %}
{% endif %}
{{ results | sort | flatten | join(",") }}
{%- endmacro -%}

{%- macro normalize_ports(rule, proto) -%}
{%- if 'proto' in rule -%}
{%- if proto in rule.proto -%}
{{ '' if not rule.proto[proto] else ( ( (rule.proto[proto]).replace(' ','').split(',') if rule.proto[proto] is string else ( [rule.proto[proto]] if rule.proto[proto] is number else rule.proto[proto] ) ) | sort | join(",")) }}
{%- endif -%}
{%- endif -%}
{%- endmacro -%}

{%- macro generate_rule(rule, chain, default_action='LOG_ACCEPT', ip_ver=4) -%}
# {{ rule | to_json }}
{% set src_addrs = normalize_addrs(rule, 'src', ip_ver).split(',') %}
{% set dest_addrs = normalize_addrs(rule, 'dest', ip_ver).split(',') %}
{% set src_list = " -m set --match-set "+rule.src_list+" src " if rule.src_list|default(False) else "" %}
{% for src_addr in src_addrs -%}
{%- for dest_addr in dest_addrs -%}
{% if 'proto' in rule %}
{% for rule_proto, rule_ports in rule.proto.items() %}
{% set rule_ports = normalize_ports(rule, rule_proto).split(',') | default([]) | difference(['']) | sort %}
{% set src = " -s "+src_addr if src_addr|length else "" %}
{% set dest = " -d "+dest_addr if dest_addr|length else "" %}
{% for port in rule_ports %}
$IT{{ ip_ver }} -A {{ chain }} -p {{ rule_proto }} --dport {{ port }}{{ src_list }}{{ src }}{{ dest }} -j {{ rule.rule | default(default_action) }}
{% endfor %}
{% if not rule_ports %}
$IT{{ ip_ver }} -A {{ chain }} -p {{ rule_proto }}{{src_list}}{{ " -s "+src_addr if src_addr|length else "" }}{{ " -d "+dest_addr if dest_addr|length else "" }} -j {{ rule.rule | default(default_action) }}
{% endif %}
{% endfor %}
{% else %}
$IT{{ ip_ver }} -A {{ chain }}{{ src_list }}{{ " -s "+src_addr if src_addr|length else "" }}{{ " -d "+dest_addr if dest_addr|length else "" }} -j {{ rule.rule | default(default_action) }}
{% endif %}
{% endfor %}
{% endfor %}
{%- endmacro -%}

{%- macro generate_interface_rules(firewall_iface_name, firewall_iface, ip_ver=4) -%}
{% set allow_nets = normalize_addrs(firewall_iface, 'allow', ip_ver).split(',') | difference(['']) | sort %}
{% set deny_nets = normalize_addrs(firewall_iface, 'deny', ip_ver).split(',') | difference(['']) | sort %}
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

  # interface specific configuration
{% for firewall_iface_name, firewall_iface in firewall_interfaces.items() %}
{{ generate_interface_rules(firewall_iface_name, firewall_iface) }}
{% endfor %}

  # everything else is dropped!
  $IT4 -A CHECK_IF -j {{ firewall_default_rule_checkif_global }}

$IT6 -N CHECK_IF
  # disable IPv6 source routing (and ping-pong)
  $IT6 -A CHECK_IF -m rt --rt-type 0 -j LOG_DROP_HACK

  # allow link-local addresses only with hl 255
  $IT6 -A CHECK_IF -s fe80::/10 -m hl --hl-eq 255 -j RETURN
  #TODO: replace following rule with DROP_HACK
  $IT6 -A CHECK_IF -s fe80::/10 -j RETURN
  #$IT6 -A CHECK_IF -s fe80::/10 -j LOG_DROP_HACK

  # per interface checkif rules
{% for firewall_iface_name, firewall_iface in firewall6_interfaces.items() | default([]) %}
{{ generate_interface_rules(firewall_iface_name, firewall_iface, 6) }}
{% endfor %}

  # everything else is dropped!
  $IT6 -A CHECK_IF -j {{ firewall_default_rule_checkif_global }}


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
{{ generate_rule(input_rule, 'INPUT') }}
{% endfor %}

# ignore broadcasts
$IT4 -A INPUT -m addrtype --dst-type BROADCAST -j DROP

# IPv4 ICMP rate limit
$IT4 -A INPUT -p icmp -m limit --limit {{ firewall_ping_rate | default(20) }}/second -j ACCEPT
$IT4 -A INPUT -p icmp -j LOG_DROP_RATELIMIT

# ignore junk from windows servers (samba)
for PORT in 137 138; do
  $IT4 -A INPUT -p udp --dport $PORT -j DROP
done

# default rule is
$IT4 -A INPUT -j {{ firewall_default_rule_input }}


############################################################
### INPUT ruleset (IPv6)

{% for input_rule in firewall6_input|default([]) %}
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
{{ generate_rule(output_rule, 'OUTPUT') }}
{% endfor %}

# default to drop
$IT4 -A OUTPUT -j {{ firewall_default_rule_output }}


############################################################
### OUTPUT ruleset (IPv6)

{% for output_rule in firewall6_output|default([]) %}
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
{{ generate_rule(forward_rule, 'FORWARD') }}
{% endfor %}

#TODO: odstranit z produkcie
# IPv4 ICMP rate limit
$IT4 -A FORWARD -p icmp -m limit --limit {{ firewall_ping_rate | default(20) }}/second -j ACCEPT
$IT4 -A FORWARD -p icmp -j LOG_DROP_RATELIMIT

# default rule
$IT4 -A FORWARD -j {{ firewall_default_rule_forward }}


############################################################
### FORWARD ruleset (IPv6)

{% for forward_rule in firewall6_forward|default([]) %}
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
