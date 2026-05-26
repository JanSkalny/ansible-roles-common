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
 -m conntrack --ctstate NEW --ctorigdstport {{ param }}
{%- elif proto == 'icmp' %}
 --icmp-type {{ param }}
{%- elif proto == 'icmp6' %}
 --icmpv6-type {{ param }}
{%- endif -%}
{%- endif -%}
{%- endif -%}
{%- endmacro -%}


{%- macro generate_rule(rule, chain, default_action='LOG_ACCEPT', ip_ver=4, orig_chain=1) -%}
# {{ rule | to_json }}
{% set src_addrs = rule | firewall_normalize_addrs('src', firewall_objects) %}
{% set dst_addrs = rule | firewall_normalize_addrs('dst', firewall_objects) %}
# src addrs: {{ src_addrs }}
# dst addrs: {{ dst_addrs }}
{# src ipset match #}
{% set src_list = " -m set --match-set %sv%s src " | format(rule.src_list, ip_ver) if rule.src_list | default(False) else "" %}
{% set dst_list = " -m set --match-set %sv%s dst " | format(rule.dst_list, ip_ver) if rule.dst_list | default(False) else "" %}
{% for src_addr in src_addrs -%}
{%- for dst_addr in dst_addrs -%}
{# filter out IPv4 addressess from IPv6 rules and vice versa #}
{% set is_v4_addr = ip_ver == 4 and (('.' in src_addr or src_addr=='ANY') and ('.' in dst_addr or dst_addr=='ANY')) %}
{% set is_v6_addr = ip_ver == 6 and ((':' in src_addr or src_addr=='ANY') and (':' in dst_addr or dst_addr=='ANY')) %}
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
{% if not(chain.startswith("DOCKER-USER")) %}
{# regular hosts #}
$IT{{ ip_ver }} -A {{ chain }}{{ proto }}{{ src_list }}{{ dst_list }}{{ src }}{{ dst }} -j {{ rule.rule | default(default_action) }}
{% else %}
{# dockerized hosts #}
{% set action = rule.rule | default(default_action) %}
{% set is_log = action.startswith('LOG_') %}
{% set base = action[4:] if is_log else action %}
{% set docker_addr = src if chain == 'DOCKER-USER-INPUT' else dst %}
{% set docker_list = src_list if chain == 'DOCKER-USER-INPUT' else dst_list %}
{% set docker_action = 'RETURN' if action == 'ACCEPT' else action %}
{% if base == 'ACCEPT' %}
$IT{{ ip_ver }} -A {{ chain }} -m mark --mark 0x0/0xf {{ proto }}{{ docker_addr }}{{ docker_list }} -j MARK --set-xmark 0x2/0xf
$IT{{ ip_ver }} -A {{ chain }} -m mark --mark 0x2/0xf -j RETURN
{% elif base.startswith('WILL_') %}
$IT{{ ip_ver }} -A {{ chain }} -m mark --mark 0x0/0xf {{ proto }}{{ docker_addr }}{{ docker_list }} -j MARK --set-xmark 0x3/0xf
$IT{{ ip_ver }} -A {{ chain }} -m mark --mark 0x3/0xf -j RETURN
{% else %}
$IT{{ ip_ver }} -A {{ chain }}{{ proto }}{{ docker_addr }}{{ docker_list }} -j {{ docker_action }}
{% endif %}
{% endif %}
{% endfor %}
{% endfor %}
{% endif %}
{% endfor %}
{% endfor %}

{%- endmacro -%}

{%- macro generate_interface_rules(firewall_iface_name, firewall_iface, ip_ver=4) -%}
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
IT6="{{ firewall_ip6tables }}"

# load additional modules
for M in xt_conntrack nf_conntrack nf_conntrack_ftp nf_conntrack_sip; do
  modprobe $M 2>/dev/null
done

# check if DOCKER-USER chain is present
iptables -nL DOCKER-USER >/dev/null 2>&1 && DOCKER=1 || DOCKER=0

# check if iptables tool is present
command -v iptables >/dev/null 2>&1 && IPT=1 || IPT=0

# check if iptables tool is present
command -v ip6tables >/dev/null 2>&1 && IPT6=1 || IPT6=0

# check if ipset tool is present
command -v ipset >/dev/null 2>&1 && IPSET=1 || IPSET=0

# check if nftables are present
command -v nft >/dev/null 2>&1 && NFT=1 || NFT=0

# check if iptables support conntrack
modprobe -n -q xt_conntrack && MODS=1 || MODS=0

# write discovery to syslog/journal
logger -t fw.sh "reload DOCKER=$DOCKER IPSET=$IPSET NFT=$NFT IPT=$IPT IPT6=$IPT6 MODS=$MODS" 2>/dev/null

# xt_conntrack module is mandatory!
if [ $MODS -eq 0 ]; then
  echo "missing xt_conntrack module! make sure correct kernel is running and kernel-modules-extra is installed" 1>&2
  logger -t fw.sh "missing xt_conntrack module! make sure correct kernel is running and kernel-modules-extra is installed"
  exit 1
fi

# iptables / ip6tables are required
if [ $IPT -eq 0 ] || [ $IPT6 -eq 0 ]; then
  echo "missing iptables/ip6tables" 1>&2
  logger -t fw.sh "missing iptables/ip6tables"
  exit 1
fi

# flush nftables, if docker is not present, but nft is
[ $DOCKER -eq 0 ] && [ $NFT -eq 1 ] && nft flush ruleset

# create lists, if ipset is present
if [ $IPSET -eq 1 ]; then
  :
{% for firewall_list in firewall_lists %}
  ipset create {{ firewall_list.name }}v4 hash:net {{ 'timeout '+(firewall_list.ttl|string) if firewall_list.ttl | default(False) else '' }} family inet hashsize 4096 maxelem 262144 -exist
  ipset create {{ firewall_list.name }}v6 hash:net {{ 'timeout '+(firewall_list.ttl|string) if firewall_list.ttl | default(False) else '' }} family inet6 hashsize 4096 maxelem 262144 -exist


{% if firewall_list.load is defined and firewall_list.load %}
# LOAD {{ firewall_list }}
ipset flush {{ firewall_list.name }}v4
ipset flush {{ firewall_list.name }}v6
{% set addrs = firewall_list | firewall_normalize_addrs('load', firewall_objects) %}
{% for addr in addrs %}
{% if ':' in addr %}
ipset add {{ firewall_list.name }}v6 {{ addr }} -exist
{% else %}
ipset add {{ firewall_list.name }}v4 {{ addr }} -exist
{% endif %}
{% endfor %}
{% endif %}
{% endfor %}
fi

if [ $DOCKER -eq 0 ] ; then
	echo {{ firewall_ip_forward | int }} > /proc/sys/net/ipv4/ip_forward
	echo {{ firewall_ip6_forward | int }} > /proc/sys/net/ipv6/conf/all/forwarding
else
	echo 1 > /proc/sys/net/ipv4/ip_forward
	echo 1 > /proc/sys/net/ipv6/conf/all/forwarding
fi
echo 1 > /proc/sys/net/ipv4/tcp_syncookies
echo {{ firewall_rp_filter | int }} > /proc/sys/net/ipv4/conf/all/rp_filter
echo {{ firewall_rp_filter | int }} > /proc/sys/net/ipv4/conf/default/rp_filter
echo {{ firewall_log_martians | int }} > /proc/sys/net/ipv4/conf/all/log_martians
echo {{ firewall_log_martians | int }} > /proc/sys/net/ipv4/conf/default/log_martians
echo 1 > /proc/sys/net/ipv4/icmp_echo_ignore_broadcasts
echo 1 > /proc/sys/net/ipv4/icmp_ignore_bogus_error_responses
echo 0 > /proc/sys/net/ipv4/conf/all/accept_redirects
echo 0 > /proc/sys/net/ipv4/conf/default/accept_redirects
echo 0 > /proc/sys/net/ipv6/conf/all/accept_redirects
echo 0 > /proc/sys/net/ipv6/conf/default/accept_redirects
echo 0 > /proc/sys/net/ipv4/conf/all/secure_redirects
echo 0 > /proc/sys/net/ipv4/conf/default/secure_redirects
echo 0 > /proc/sys/net/ipv4/conf/all/send_redirects
echo 0 > /proc/sys/net/ipv4/conf/default/send_redirects
echo 0 > /proc/sys/net/ipv4/conf/all/accept_source_route
echo 0 > /proc/sys/net/ipv4/conf/default/accept_source_route
echo 0 > /proc/sys/net/ipv6/conf/all/accept_source_route
echo 0 > /proc/sys/net/ipv6/conf/default/accept_source_route
echo 0 > /proc/sys/net/ipv6/conf/all/accept_ra
echo 0 > /proc/sys/net/ipv6/conf/default/accept_ra
echo {{ (not firewall_enable_ipv6) | int }} > /proc/sys/net/ipv6/conf/lo/disable_ipv6
echo {{ (not firewall_enable_ipv6) | int }} > /proc/sys/net/ipv6/conf/all/disable_ipv6
echo {{ (not firewall_enable_ipv6) | int }} > /proc/sys/net/ipv6/conf/default/disable_ipv6

{% for iface in firewall_slaac_ifaces %}
echo 1 > /proc/sys/net/ipv6/conf/{{ iface }}/accept_ra
{% endfor %}

{% for iface in firewall_no_martians_ifaces %}
echo 0 > /proc/sys/net/ipv4/conf/{{ iface }}/log_martians
{% endfor %}


for PROTO in 4 6; do
  IT=$( eval echo \$IT$PROTO )
  X=$( [ $PROTO -eq 6 ] && echo "6" )

  if [ $DOCKER -eq 0 ]; then
    # flush all tables tables if no docker is present
    for TABLE in filter nat mangle; do
      $IT -t $TABLE -F
      $IT -t $TABLE -X
    done
  else
    # cleanup mangle table
    $IT -t mangle -F
    $IT -t mangle -X

    # manually cleanup filter table from previous fw.sh run
    for CHAIN in INPUT OUTPUT FORWARD DOCKER-USER DOCKER-USER-INPUT DOCKER-USER-OUTPUT; do
      $IT -F $CHAIN 2>/dev/null
    done
    # flush and remove all custom CHECK_IF and LOG_* chains
    for CHAIN in $( $IT -n -L | grep '^Chain \(LOG_\|CHECK_IF\)' | awk '{print $2}' ); do
      $IT -F $CHAIN
      $IT -X $CHAIN
    done

    #XXX: any pre-planted nat/filter rules will surivive!
    # don't forget to audit those...
  fi

  # default is DROP
  $IT -P INPUT DROP
  $IT -P OUTPUT DROP
  $IT -P FORWARD DROP

  # custom REJECT action with logging
  $IT -N LOG_REJECT
    $IT -A LOG_REJECT -m limit --limit 20/sec --limit-burst 20 -j LOG \
      --log-ip-options --log-tcp-options --log-uid --log-level info \
      --log-prefix "FW${PROTO}-REJECT "
    $IT -A LOG_REJECT -m limit --limit 10/sec --limit-burst 20 -j REJECT \
      --reject-with icmp$X-port-unreachable
    $IT -A LOG_REJECT -j DROP

  # custom DROP action with logging
  $IT -N LOG_DROP
    $IT -A LOG_DROP -m limit --limit 20/sec --limit-burst 20 -j LOG \
      --log-ip-options --log-tcp-options --log-uid --log-level info \
      --log-prefix "FW${PROTO}-DROP "
    $IT -A LOG_DROP -j DROP

  # custom ACCEPT action with logging
  $IT -N LOG_ACCEPT
    $IT -A LOG_ACCEPT -m limit --limit 20/sec --limit-burst 100 -j LOG \
      --log-ip-options --log-tcp-options --log-uid --log-level info \
      --log-prefix "FW${PROTO}-ACCEPT "
    $IT -A LOG_ACCEPT -j ACCEPT

  # custom ACCEPT action with logging
  $IT -N LOG_WILL_DROP
    $IT -A LOG_WILL_DROP -m limit --limit 10/sec --limit-burst 100 -j LOG \
      --log-ip-options --log-tcp-options --log-uid --log-level info \
      --log-prefix "FW${PROTO}-WILL-DROP "
    $IT -A LOG_WILL_DROP -j ACCEPT

  # custom WILL-DROP actions with special log messages
{% for rule in firewall_custom_actions %}
  $IT -N LOG_WILL_DROP_{{ rule | upper }}
    $IT -A LOG_WILL_DROP_{{ rule | upper }} -m limit --limit 10/sec --limit-burst 100 -j LOG \
      --log-ip-options --log-tcp-options --log-uid --log-level info \
      --log-prefix "FW${PROTO}-WILL-DROP-{{ rule | upper }} "
{% if not ('CHECKIF' in (rule | upper)) %}
{# WILL_DROP iniside CHECKIF needs to be RETURN and not accept... #}
    $IT -A LOG_WILL_DROP_{{ rule | upper }} -j ACCEPT
{% endif %}
{% endfor %}

  # custom DROP actions with special log messages
{% for rule in firewall_custom_actions %}
  $IT -N LOG_DROP_{{ rule | upper }}
    $IT -A LOG_DROP_{{ rule | upper }} -m limit --limit 10/sec --limit-burst 20 -j LOG \
      --log-ip-options --log-tcp-options --log-uid --log-level info \
      --log-prefix "FW${PROTO}-DROP-{{ rule | upper }} "
    $IT -A LOG_DROP_{{ rule | upper }} -j DROP
{% endfor %}

{% if firewall_enable_docker %}
  if [ $DOCKER -eq 1 ]; then
    # custom "RETURN" action with logging
    $IT -N LOG_DOCKER_ACCEPT
      $IT -A LOG_DOCKER_ACCEPT -m limit --limit 50/sec --limit-burst 100 -j LOG \
        --log-ip-options --log-tcp-options --log-uid --log-level info \
        --log-prefix "FW${PROTO}-ACCEPT "
      #$IT -A LOG_DOCKER_ACCEPT -j "RETURN 2" :F
    $IT -N LOG_DOCKER_WILL_DROP
      $IT -A LOG_DOCKER_WILL_DROP -m limit --limit 50/sec --limit-burst 100 -j LOG \
        --log-ip-options --log-tcp-options --log-uid --log-level info \
        --log-prefix "FW${PROTO}-WILL-DROP "
  fi
{% endif %}
done
IT=""


############################################################
### verify source address of packet (RFC 2827, RFC 1918)

$IT4 -N CHECK_IF
{% if firewall_enable_docker %}
  # docker containers and bridges can spoof anything (rely on rp-filter)
  $IT4 -A CHECK_IF -i veth+ -j RETURN
  $IT4 -A CHECK_IF -i br-+ -j RETURN
  $IT4 -A CHECK_IF -i docker0 -j RETURN

{% endif %}
  # interface specific exclusions
{% for firewall_iface_name, firewall_iface in firewall_interfaces.items() %}
{% if firewall_iface.allow_dhcp | default(False) %}
  $IT4 -A CHECK_IF -i {{ firewall_iface_name }} -s 0.0.0.0 -j RETURN # DHCP
{% endif %}
{% if firewall_iface.allow_igmp | default(False) %}
  $IT4 -A CHECK_IF -i {{ firewall_iface_name }} -s 0.0.0.0/8 -d 224.0.0.1 -p 2 -j RETURN # IGMP
{% endif %}
{% endfor %}

  # deny IGMP
  $IT4 -A CHECK_IF -s 0.0.0.0/8 -d 224.0.0.1 -p 2 -j {{ firewall_rule_checkif_igmp }}

  # don't accept APIPA addresses
  $IT4 -A CHECK_IF -s 169.254.0.0/16 -j {{ firewall_rule_checkif_apipa }}

  # no-one can send from special address ranges!
  $IT4 -A CHECK_IF -s 127.0.0.0/8      -j {{ firewall_rule_checkif_spoof }} # loopback
  $IT4 -A CHECK_IF -s 0.0.0.0/8        -j {{ firewall_rule_checkif_dhcp }}  # DHCP
  #XXX: this might screw up PCP/TURN/NAT traversal anycast
  $IT4 -A CHECK_IF -s 192.0.0.0/24     -j {{ firewall_rule_checkif_spoof }} # IETF protocol assignments
  $IT4 -A CHECK_IF -s 192.0.2.0/24     -j {{ firewall_rule_checkif_spoof }} # RFC 6890 TEST-NET-1
  $IT4 -A CHECK_IF -s 198.51.100.0/24  -j {{ firewall_rule_checkif_spoof }} # RFC 6890 TEST-NET-2
  $IT4 -A CHECK_IF -s 203.0.113.0/24   -j {{ firewall_rule_checkif_spoof }} # RFC 6890 TEST-NET-3
  $IT4 -A CHECK_IF -s 224.0.0.0/3      -j {{ firewall_rule_checkif_spoof }} # multicast and reserved E

{% if firewall_interfaces|length == 0 %}
  #FIXME: no firewall_interfaces defined. CHECK_IF defaults to RETURN
  $IT4 -A CHECK_IF -j RETURN
{% else %}
{% for firewall_iface_name, firewall_iface in firewall_interfaces.items() %}
{{ generate_interface_rules(firewall_iface_name, firewall_iface, 4) }}
{% endfor %}

  # everything else is dropped!
  $IT4 -A CHECK_IF -j {{ firewall_rule_checkif_default }}
{% endif %}

$IT6 -N CHECK_IF
{% if firewall_enable_docker %}
  # docker containers and bridges can spoof anything (rely on rp-filter)
  $IT6 -A CHECK_IF -i veth+ -j RETURN
  $IT6 -A CHECK_IF -i br-+ -j RETURN
  $IT6 -A CHECK_IF -i docker0 -j RETURN

{% endif %}
  # disable IPv6 source routing (and ping-pong)
  $IT6 -A CHECK_IF -m rt --rt-type 0 -j {{ firewall_rule_checkif_sourceroute }}

  # allow link-local addresses only with hl 255
  $IT6 -A CHECK_IF -s fe80::/10 -m hl --hl-eq 255 -j RETURN
  $IT6 -A CHECK_IF -s fe80::/10 -j {{ firewall_rule_checkif_linklocal }}
  $IT6 -A CHECK_IF -s fe80::/10 -j RETURN #XXX: return if previous rule was log only

{% if firewall_interfaces|length == 0 %}
  #FIXME: no firewall_interfaces defined. CHECK_IF defaults to RETURN
  $IT6 -A CHECK_IF -j RETURN
{% else %}
{% for firewall_iface_name, firewall_iface in firewall_interfaces.items() %}
{{ generate_interface_rules(firewall_iface_name, firewall_iface, 6) }}
{% endfor %}

  # everything else is dropped!
  $IT6 -A CHECK_IF -j {{ firewall_rule_checkif_default }}
{% endif %}

############################################################
### allow loopbacks, check origin, and related/established

for PROTO in 4 6; do
  IT=$( eval echo \$IT$PROTO )

  # everything is allowed on lo
  $IT -A INPUT -i lo -j ACCEPT
  $IT -A OUTPUT -o lo -j ACCEPT

{% if firewall_enable_docker %}
  if [ $DOCKER -eq 1 ]; then
    # root (uid 0) can do everything to docker containers and bridges :(
    $IT -A OUTPUT -m owner --uid-owner 0 -o br+ -j ACCEPT
    $IT -A OUTPUT -m owner --uid-owner 0 -o veth+ -j ACCEPT
    $IT -A OUTPUT -m owner --uid-owner 0 -o docker0 -j ACCEPT
  fi

{% endif %}
  # connection tracking:
  # - allow all related/established traffic
  # - invalid packets MUST be dropped!
  for CHAIN in INPUT OUTPUT FORWARD; do
    $IT -A $CHAIN -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    $IT -A $CHAIN -m conntrack --ctstate INVALID -j {{ firewall_rule_invalid_conntrack }}
  done

  # check for spoofed addresses (rfc2827)
  for CHAIN in INPUT FORWARD; do
    $IT -A $CHAIN -j CHECK_IF
  done

{% if firewall_enable_docker %}
  if [ $DOCKER -eq 1 ]; then
    # re-create DOCKER-USER and DOCKER-FORWARD in FORWARD
    $IT -t filter -A FORWARD -j DOCKER-USER
    $IT -t filter -A FORWARD -j DOCKER-FORWARD
  fi
{% endif %}
done

{% if firewall_enable_docker %}
############################################################
### DOCKER-USER
if [ $DOCKER -eq 1 ]; then
  # make sure DOCKER-USER chain exists and is empty (when using docker)
  for C in DOCKER-USER-INPUT DOCKER-USER-OUTPUT DOCKER-USER; do
    $IT4 -N $C 2>/dev/null
    $IT4 -F $C
  done

  # log traffic between docker containers?
  #$IT4 -A DOCKER-USER -i veth+ -o veth+ -j LOG_DOCKER_ACCEPT
  #$IT4 -A DOCKER-USER -i veth+ -o br-+ -j LOG_DOCKER_ACCEPT
  #$IT4 -A DOCKER-USER -i veth+ -o docker0 -j LOG_DOCKER_ACCEPT
  #$IT4 -A DOCKER-USER -i br-+ -o veth+ -j LOG_DOCKER_ACCEPT
  #$IT4 -A DOCKER-USER -i br-+ -o br-+ -j LOG_DOCKER_ACCEPT
  #$IT4 -A DOCKER-USER -i docker0 -o docker0 -j LOG_DOCKER_ACCEPT
  #$IT4 -A DOCKER-USER -i docker0 -o veth+ -j LOG_DOCKER_ACCEPT

  # everything between docker-containers is handled by docker
  $IT4 -A DOCKER-USER -i veth+   -o veth+   -j RETURN
  $IT4 -A DOCKER-USER -i veth+   -o br-+    -j RETURN
  $IT4 -A DOCKER-USER -i veth+   -o docker0 -j RETURN
  $IT4 -A DOCKER-USER -i br-+    -o veth+   -j RETURN
  $IT4 -A DOCKER-USER -i br-+    -o br-+    -j RETURN
  $IT4 -A DOCKER-USER -i docker0 -o docker0 -j RETURN
  $IT4 -A DOCKER-USER -i docker0 -o veth+   -j RETURN

  # traffic from docker
  $IT4 -A DOCKER-USER -i veth+   -j DOCKER-USER-OUTPUT
  $IT4 -A DOCKER-USER -i br-+    -j DOCKER-USER-OUTPUT
  $IT4 -A DOCKER-USER -i docker0 -j DOCKER-USER-OUTPUT

  # traffic to docker
  $IT4 -A DOCKER-USER -o veth+   -j DOCKER-USER-INPUT
  $IT4 -A DOCKER-USER -o br-+    -j DOCKER-USER-INPUT
  $IT4 -A DOCKER-USER -o docker0 -j DOCKER-USER-INPUT

  # mark 2 => LOG_DOCKER_ACCEPT
  # mark 3 => LOG_DOCKER_WILL_DROP
  # no mark => DEFAULT
  $IT4 -A DOCKER-USER -m mark --mark 0x2/0xf -j LOG_DOCKER_ACCEPT
  $IT4 -A DOCKER-USER -m mark --mark 0x2/0xf -j RETURN
  $IT4 -A DOCKER-USER -m mark --mark 0x3/0xf -j LOG_DOCKER_WILL_DROP
  $IT4 -A DOCKER-USER -m mark --mark 0x3/0xf -j RETURN

  # everything else is dropped
  # XXX: this should not match anythign
  $IT4 -A DOCKER-USER -j {{ firewall_rule_input_default }}

# allow only traffic defined in firewall_input
{% for rule in firewall_input %}
{{ generate_rule(rule, 'DOCKER-USER-INPUT', 'LOG_ACCEPT', 4)  | indent(2, true) }}
{% endfor %}

# allow outgoing traffic defined in firewall_output
{% for rule in firewall_output %}
{{ generate_rule(rule, 'DOCKER-USER-OUTPUT', 'LOG_ACCEPT', 4)  | indent(2, true) }}
{% endfor %}

  # everything else is dropped
  # XXX: these should be translated to docker rules :/
  $IT4 -A DOCKER-USER-INPUT -j {{ firewall_rule_input_default }}
  $IT4 -A DOCKER-USER-OUTPUT -j {{ firewall_rule_output_default }}

fi

{% endif %}


############################################################
### INPUT ruleset

{% for input_rule in firewall_input %}
{{ generate_rule(input_rule, 'INPUT', 'LOG_ACCEPT', 4) }}
{% endfor %}

{% if firewall_drop_broadcasts %}
# IPv4 ignore broadcasts
$IT4 -A INPUT -m addrtype --dst-type BROADCAST -j DROP
{% endif %}

{% if firewall_ping_rate > 0 %}
# IPv4 ICMP ping
$IT4 -A INPUT -p icmp --icmp-type echo-request -m limit --limit {{ firewall_ping_rate }}/second -j ACCEPT
$IT4 -A INPUT -p icmp --icmp-type echo-request -j {{ firewall_rule_ping_ratelimit }}
{% endif %}

# default rule
$IT4 -A INPUT -j {{ firewall_rule_input_default }}


############################################################
### INPUT ruleset (IPv6)

{% for input_rule in firewall_input %}
{{ generate_rule(input_rule, 'INPUT', 'LOG_ACCEPT', 6) }}
{% endfor %}

# NDP with HL 255 is always allowed
$IT6 -A INPUT -p ipv6-icmp --icmpv6-type neighbor-solicitation -m hl --hl-eq 255 -j {{ firewall_rule_input_ndp }}
$IT6 -A INPUT -p ipv6-icmp --icmpv6-type neighbor-advertisement -m hl --hl-eq 255 -j {{ firewall_rule_input_ndp }}
{% if firewall_allow_ipv6_slaac %}
$IT6 -A INPUT -p ipv6-icmp --icmpv6-type router-solicitation -m hl --hl-eq 255 -j {{ firewall_rule_input_slaac }}
$IT6 -A INPUT -p ipv6-icmp --icmpv6-type router-advertisement -m hl --hl-eq 255 -j {{ firewall_rule_input_slaac }}
{% endif %}

# NDP with bigger HL is consider malicious
$IT6 -A INPUT -p ipv6-icmp --icmpv6-type router-solicitation -j {{ firewall_rule_invalid_ndp }}
$IT6 -A INPUT -p ipv6-icmp --icmpv6-type router-advertisement -j {{ firewall_rule_invalid_ndp }}
$IT6 -A INPUT -p ipv6-icmp --icmpv6-type neighbor-solicitation -j {{ firewall_rule_invalid_ndp }}
$IT6 -A INPUT -p ipv6-icmp --icmpv6-type neighbor-advertisement -j {{ firewall_rule_invalid_ndp }}

# IPv6 MLD
$IT6 -A INPUT -p ipv6-icmp --icmpv6-type 130 -j {{ firewall_rule_input_mld }}
$IT6 -A INPUT -p ipv6-icmp --icmpv6-type 131 -j {{ firewall_rule_input_mld }}
$IT6 -A INPUT -p ipv6-icmp --icmpv6-type 132 -j {{ firewall_rule_input_mld }}
$IT6 -A INPUT -p ipv6-icmp --icmpv6-type 143 -j {{ firewall_rule_input_mld }}

{% if firewall_ping_rate > 0 %}
# IPv6 ICMP ping
$IT6 -A INPUT -p ipv6-icmp --icmpv6-type echo-request -m limit --limit {{ firewall_ping_rate }}/second -j ACCEPT
$IT6 -A INPUT -p ipv6-icmp --icmpv6-type echo-request -j {{ firewall_rule_ping_ratelimit }}
{% endif %}

# default rule
$IT6 -A INPUT -j {{ firewall_rule_input_default }}


############################################################
### OUTPUT ruleset

$IT4 -A OUTPUT -o lo -j ACCEPT
$IT6 -A OUTPUT -o lo -j ACCEPT

{% for output_rule in firewall_output %}
{{ generate_rule(output_rule, 'OUTPUT', 'LOG_ACCEPT', 4) }}
{% endfor %}

{% if firewall_ping_rate > 0 %}
# IPv4 ICMP ping
$IT4 -A OUTPUT -p icmp --icmp-type echo-request -m limit --limit {{ firewall_ping_rate }}/second -j ACCEPT
$IT4 -A OUTPUT -p icmp --icmp-type echo-request -j {{ firewall_rule_ping_ratelimit }}
{% endif %}

# default rule
$IT4 -A OUTPUT -j {{ firewall_rule_output_default }}


############################################################
### OUTPUT ruleset (IPv6)

{% for output_rule in firewall_output %}
{{ generate_rule(output_rule, 'OUTPUT', 'LOG_ACCEPT', 6) }}
{% endfor %}

# IPv6 NDP only with hl 255 should be allowed
$IT6 -A OUTPUT -p ipv6-icmp --icmpv6-type neighbor-solicitation -m hl --hl-eq 255 -j {{ firewall_rule_output_ndp }}
$IT6 -A OUTPUT -p ipv6-icmp --icmpv6-type neighbor-advertisement -m hl --hl-eq 255 -j {{ firewall_rule_output_ndp }}
{% if firewall_allow_ipv6_slaac %}
$IT6 -A OUTPUT -p ipv6-icmp --icmpv6-type router-solicitation -m hl --hl-eq 255 -j {{ firewall_rule_output_slaac }}
$IT6 -A OUTPUT -p ipv6-icmp --icmpv6-type router-advertisement -m hl --hl-eq 255 -j {{ firewall_rule_output_slaac }}
{% endif %}

# NDP with bigger HL is consider malicious
$IT6 -A OUTPUT -p ipv6-icmp --icmpv6-type router-solicitation -j {{ firewall_rule_invalid_ndp }}
$IT6 -A OUTPUT -p ipv6-icmp --icmpv6-type router-advertisement -j {{ firewall_rule_invalid_ndp }}
$IT6 -A OUTPUT -p ipv6-icmp --icmpv6-type neighbor-solicitation -j {{ firewall_rule_invalid_ndp }}
$IT6 -A OUTPUT -p ipv6-icmp --icmpv6-type neighbor-advertisement -j {{ firewall_rule_invalid_ndp }}

# IPv6 MLD
$IT6 -A OUTPUT -p ipv6-icmp --icmpv6-type 130 -j {{ firewall_rule_output_mld }}
$IT6 -A OUTPUT -p ipv6-icmp --icmpv6-type 131 -j {{ firewall_rule_output_mld }}
$IT6 -A OUTPUT -p ipv6-icmp --icmpv6-type 132 -j {{ firewall_rule_output_mld }}
$IT6 -A OUTPUT -p ipv6-icmp --icmpv6-type 143 -j {{ firewall_rule_output_mld }}

{% if firewall_ping_rate > 0 %}
# IPv6 ICMP ping
$IT6 -A OUTPUT -p ipv6-icmp --icmpv6-type echo-request -m limit --limit {{ firewall_ping_rate }}/second -j ACCEPT
$IT6 -A OUTPUT -p ipv6-icmp --icmpv6-type echo-request -j {{ firewall_rule_ping_ratelimit }}
{% endif %}

# default rule
$IT6 -A OUTPUT -j {{ firewall_rule_output_default }}


############################################################
### FORWARD ruleset

#XXX: don't touch FORWARD when docker is in use, so no docker on routers pls :)

if [ $DOCKER -eq 0 ]; then
{% for forward_rule in firewall_forward %}
  {{ generate_rule(forward_rule, 'FORWARD', 'LOG_ACCEPT', 4) }}
{% endfor %}

{% if firewall_ping_rate > 0 %}
  # IPv4 ICMP ping
  $IT4 -A FORWARD -p icmp --icmp-type echo-request -m limit --limit {{ firewall_ping_rate }}/second -j ACCEPT
  $IT4 -A FORWARD -p icmp --icmp-type echo-request -j {{ firewall_rule_ping_ratelimit }}
{% endif %}

  # default rule
  $IT4 -A FORWARD -j {{ firewall_rule_forward_default }}
fi

############################################################
### FORWARD ruleset (IPv6)

{% for forward_rule in firewall_forward %}
{{ generate_rule(forward_rule, 'FORWARD', 'LOG_ACCEPT', 6) }}
{% endfor %}

# IPv6 NDP should not be forwarded
$IT6 -A FORWARD -p ipv6-icmp --icmpv6-type router-solicitation -j {{ firewall_rule_forward_ndp }}
$IT6 -A FORWARD -p ipv6-icmp --icmpv6-type router-advertisement -j {{ firewall_rule_forward_ndp }}
$IT6 -A FORWARD -p ipv6-icmp --icmpv6-type neighbor-solicitation -j {{ firewall_rule_forward_ndp }}
$IT6 -A FORWARD -p ipv6-icmp --icmpv6-type neighbor-advertisement -j {{ firewall_rule_forward_ndp }}

# IPv6 MLD should not be forwarded (we don't need internet-wide multicast)
$IT6 -A FORWARD -p ipv6-icmp --icmpv6-type 130 -j {{ firewall_rule_forward_mld }}
$IT6 -A FORWARD -p ipv6-icmp --icmpv6-type 131 -j {{ firewall_rule_forward_mld }}
$IT6 -A FORWARD -p ipv6-icmp --icmpv6-type 132 -j {{ firewall_rule_forward_mld }}
$IT6 -A FORWARD -p ipv6-icmp --icmpv6-type 142 -j {{ firewall_rule_forward_mld }}

{% if firewall_ping_rate > 0 %}
# IPv6 ICMP ping
$IT6 -A FORWARD -p ipv6-icmp --icmpv6-type echo-request -m limit --limit {{ firewall_ping_rate }}/second -j ACCEPT
$IT6 -A FORWARD -p ipv6-icmp --icmpv6-type echo-request -j {{ firewall_rule_ping_ratelimit }}
{% endif %}

# default rule
$IT6 -A FORWARD -j {{ firewall_rule_forward_default }}


############################################################
### NAT ruleset

if [ $DOCKER -eq 0 ]; then
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

  true
fi


############################################################
### custom firewall patches

{% if firewall_final_patch is defined %}
{{ firewall_final_patch }}
{% endif %}

############################################################

### fail2ban integration
systemctl --no-block try-restart fail2ban.service || true

logger -t fw.sh "done" 2>/dev/null

exit 0
