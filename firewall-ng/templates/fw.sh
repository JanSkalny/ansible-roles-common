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
{% if name_or_addr | ipaddr %}
{% do results.append([name_or_addr]) %}
{% else %}
{{ xxx_invalid|mandatory("Object not found and direct DNS referencing not allowed: "+name_or_addr+" ip_ver="+ip_ver|string+" rule="+(rule|to_json)) }}
{% endif %}
{% endif %}
{% endfor %}
{% endif %}
{{ results | flatten | join(",") }}
{%- endmacro -%}

{%- macro normalize_ports(rule, proto) -%}
{%- if 'proto' in rule -%}
{%- if proto in rule.proto -%}
{{ '' if not rule.proto[proto] else ( ( (rule.proto[proto]).replace(' ','').split(',') if rule.proto[proto] is string else ( [rule.proto[proto]] if rule.proto[proto] is number else rule.proto[proto] ) ) | join(",")) }}
{%- endif -%}
{%- endif -%}
{%- endmacro -%}

{%- macro generate_rule(rule, chain, default_action='LOG_ACCEPT', ip_ver=4) -%}
{% set src_addrs = normalize_addrs(rule, 'src', ip_ver).split(',') %}
{% set dest_addrs = normalize_addrs(rule, 'dest', ip_ver).split(',') %}
# {{ rule | to_json }}
{% for src_addr in src_addrs -%}
{%- for dest_addr in dest_addrs -%}
{% if 'proto' in rule %}
{% for rule_proto, rule_ports in rule.proto.items() %}
{% set rule_ports_norm = normalize_ports(rule, rule_proto).split(',') | default([]) | difference(['']) %}
{% set rule_port_ranges = rule_ports_norm | select('match', '^[0-9]*-[0-9]*$') | list %}
{% set rule_ports = rule_ports_norm | difference(rule_port_ranges) | list %}
{% for port in rule_ports|default([]) %}
$IT{{ ip_ver }} -A {{ chain }} -p {{ rule_proto }} --dport {{ port }}{{ " -s "+src_addr if src_addr|length else "" }}{{ " -d "+dest_addr if dest_addr|length else "" }} -j {{ rule.rule | default(default_action) }}
{% endfor %}
{% for port_range in rule_port_ranges|default([]) %}
$IT{{ ip_ver }} -A {{ chain }} -p {{ rule_proto }} -m multiport --dports {{ port_range | replace('-',':') }}{{ " -s "+src_addr if src_addr|length else "" }}{{ " -d "+dest_addr if dest_addr|length else "" }} -j {{ rule.rule | default(default_action) }}
{% endfor %}
{% if not rule_ports_norm %}
$IT{{ ip_ver }} -A {{ chain }} -p {{ rule_proto }}{{ " -s "+src_addr if src_addr|length else "" }}{{ " -d "+dest_addr if dest_addr|length else "" }} -j {{ rule.rule | default(default_action) }}
{% endif %}
{% endfor %}
{% else %}
$IT{{ ip_ver }} -A {{ chain }}{{ " -s "+src_addr if src_addr|length else "" }}{{ " -d "+dest_addr if dest_addr|length else "" }} -j {{ rule.rule | default(default_action) }}
{% endif %}
{% endfor %}
{% endfor %}
{%- endmacro -%}

{%- macro generate_interface_rules(firewall_iface_name, firewall_iface, ip_ver=4) -%}
{% set allow_nets = normalize_addrs(firewall_iface, 'allow', ip_ver).split(',') | difference(['']) %}
{% set deny_nets = normalize_addrs(firewall_iface, 'deny', ip_ver).split(',') | difference(['']) %}
{% set allow_dst = '-d '+firewall_iface.allow_dst if 'allow_dst' in firewall_iface else '' %}
{% for deny_net in deny_nets %}
  $IT{{ ip_ver }} -A CHECK_IF -i {{ firewall_iface_name }} -s {{ deny_net }} -j LOG_DROP
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

# load additional modules
for M in ip_conntrack ip_conntrack_ftp; do
  modprobe $M 2>/dev/null
done

echo {{ firewall_ip_forward | default(0) | int }} > /proc/sys/net/ipv4/ip_forward
echo {{ firewall_ip6_forward | default(0) | int }} > /proc/sys/net/ipv6/conf/all/forwarding
echo 1 > /proc/sys/net/ipv4/tcp_syncookies
echo 1 > /proc/sys/net/ipv4/conf/all/rp_filter
echo {{ firewall_log_martians | default(1) | int }} > /proc/sys/net/ipv4/conf/all/log_martians
echo 1 > /proc/sys/net/ipv4/icmp_echo_ignore_broadcasts
echo 1 > /proc/sys/net/ipv4/icmp_ignore_bogus_error_responses
echo 0 > /proc/sys/net/ipv4/conf/all/send_redirects
echo 0 > /proc/sys/net/ipv4/conf/all/accept_source_route

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

done
IT=""


############################################################
### verify source address of packet (RFC 2827, RFC 1918)

$IT4 -N CHECK_IF
  # allow dhcp on specific interfaces
{% for firewall_iface_name, firewall_iface in firewall_interfaces.items() %}
{% if firewall_iface.allow_dhcp | default(false) %}
  $IT4 -A CHECK_IF -i {{ firewall_iface_name }} -s 0.0.0.0 -j RETURN # DHCP
{% endif %}
{% endfor %}

  # multicast shit...
  $IT4 -A CHECK_IF -s 0.0.0.0/8 -d 224.0.0.1 -p 2 -j DROP #IGMP

  # no-one can send from special address ranges!
  $IT4 -A CHECK_IF -s 127.0.0.0/8 -j LOG_DROP     # loopback
  $IT4 -A CHECK_IF -s 0.0.0.0/8 -j LOG_DROP       # DHCP
  $IT4 -A CHECK_IF -s 169.254.0.0/16 -j DROP      # APIPA
  $IT4 -A CHECK_IF -s 192.0.2.0/24 -j LOG_DROP    # RFC 3330
  $IT4 -A CHECK_IF -s 204.152.64.0/23 -j LOG_DROP # RFC 3330
  $IT4 -A CHECK_IF -s 224.0.0.0/3 -j DROP         # multicast

  # interface specific configuration
{% for firewall_iface_name, firewall_iface in firewall_interfaces.items() %}
{{ generate_interface_rules(firewall_iface_name, firewall_iface) }}
{% endfor %}

  # everything else is dropped!
  $IT4 -A CHECK_IF -j {{ firewall_default_rule_checkif }}

$IT6 -N CHECK_IF
  # disable IPv6 source routing (and ping-pong)
  $IT6 -A CHECK_IF -m rt --rt-type 0 -j LOG_DROP

  # ND stuff
  #FIXME: either...
  $IT6 -A CHECK_IF -p ipv6-icmp -s fe80::/64 -m hl --hl-eq 255 -j RETURN
  $IT6 -A CHECK_IF -s fe80::/64 -j RETURN

  # per interface filter
{% for firewall_iface_name, firewall_iface in firewall6_interfaces.items() | default([]) %}
{{ generate_interface_rules(firewall_iface_name, firewall_iface, 6) }}
{% endfor %}

  # everything else is dropped!
  $IT6 -A CHECK_IF -j {{ firewall_default_rule_checkif }}


############################################################
### allow loopbacks, check origin, and related/established

# everything is allowed on loopback
$IT4 -A INPUT -i lo -j ACCEPT
$IT6 -A INPUT -i lo -j ACCEPT
$IT4 -A OUTPUT -o lo -j ACCEPT
$IT6 -A OUTPUT -o lo -j ACCEPT

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
  $IT4 -A $CHAIN -m conntrack --ctstate INVALID -j LOG_DROP
  $IT6 -A $CHAIN -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  $IT6 -A $CHAIN -m conntrack --ctstate INVALID -j LOG_DROP
done


############################################################
### INPUT ruleset 

{% for input_rule in firewall_input %}
{{ generate_rule(input_rule, 'INPUT') }}
{% endfor %}

# ignore broadcasts
$IT4 -A INPUT -m addrtype --dst-type BROADCAST -j DROP

# IPv4 ICMP rate limit
$IT4 -A INPUT -p icmp -m limit --limit 20/second -j ACCEPT
$IT4 -A INPUT -p icmp -j LOG_DROP

# ignore junk from windows servers (samba)
for PORT in 137 138; do
  $IT4 -A INPUT -p udp --dport $PORT -j DROP
done

# default rule is
$IT4 -A INPUT -j {{ firewall_default_rule_input }}


############################################################
### INPUT ruleset (IPv6)

{% for input_rule in firewall6_input %}
{{ generate_rule(input_rule, 'INPUT', 'LOG_ACCEPT', 6) }}
{% endfor %}

# IPv6 service ICMPs (router advertisements, etc)
for TYPE in 133 134 135 136 137 ; do
  $IT6 -A INPUT -p ipv6-icmp --icmpv6-type $TYPE -j ACCEPT
done

# IPv6 ICMP ping
$IT6 -A INPUT -p ipv6-icmp --icmpv6-type 128 -m limit --limit 20/s -j ACCEPT
$IT6 -A INPUT -p icmp -j LOG_DROP

# ignore IGMP stuff...
#FIXME:
$IT6 -A INPUT -p ipv6-icmp --icmpv6-type 130 -d ff02::1 -j DROP
$IT6 -A INPUT -p ipv6-icmp --icmpv6-type 143 -d ff02::16 -j DROP

# default rule is
$IT6 -A INPUT -j {{ firewall_default_rule_input }}


############################################################
### OUTPUT ruleset

{% for output_rule in firewall_output %}
{{ generate_rule(output_rule, 'OUTPUT') }}
{% endfor %}

# default to drop
$IT4 -A OUTPUT -j {{ firewall_default_rule_output }}


############################################################
### OUTPUT ruleset (IPv6)

{% for output_rule in firewall6_output %}
{{ generate_rule(output_rule, 'OUTPUT', 'LOG_ACCEPT', 6) }}
{% endfor %}

# IPv6 ND
for TYPE in 133 134 135 136 137 ; do
  #FIXME: either...
  $IT6 -A OUTPUT -p ipv6-icmp --icmpv6-type $TYPE -j ACCEPT
  $IT6 -A OUTPUT -p ipv6-icmp --icmpv6-type $TYPE -m hl --hl-eq 255 -j ACCEPT
done

# default to drop
$IT6 -A OUTPUT -j {{ firewall_default_rule_output }}


############################################################
### FORWARD ruleset

{% for forward_rule in firewall_forward %}
{{ generate_rule(forward_rule, 'FORWARD') }}
{% endfor %}

# default rule
$IT4 -A FORWARD -j {{ firewall_default_rule_forward }}


############################################################
### FORWARD ruleset (IPv6)

{% for forward_rule in firewall6_forward %}
{{ generate_rule(forward_rule, 'FORWARD', 'LOG_ACCEPT', 6) }}
{% endfor %}

# default rule
$IT6 -A FORWARD -j {{ firewall_default_rule_forward }}


############################################################
### NAT ruleset

# TBD:

############################################################
### custom firewall patches

{% if firewall_final_patch is defined %}
{% for rule in firewall_final_patch %}
{{rule}}
{% endfor %}
{% endif %}


############################################################

### fail2ban integration
[ -f /etc/init.d/fail2ban ] && /etc/init.d/fail2ban restart

