# firewall-ng++

Unified IPv4/IPv6 iptables fw.sh generator with docker/podman detection.

## Compatibility
Basic testing was done on:
- ubuntu22.04 
- ubuntu24.04
- debian13
- almalinux10
- centos-stream10


> [!WARNING]
> almalinux does not come with kernel-modules-extra package by default
> restart or installing older version my might required
> `dnf list installed | grep kernel-modules-extra` vs `uname -a`

## Usage

### Normal endpoints
1. Override default firewall LOG_DROP_DEFAULT actions *while testing*:
```
firewall_default_rule_input: "LOG_WILL_DROP"              # input rules without match
firewall_default_rule_output: "LOG_WILL_DROP"             # output rules without match
firewall_default_rule_checkif_global: "LOG_WILL_DROP"     # unmatched interface rule
firewall_default_rule_checkif: "LOG_WILL_DROP"     # matched interface, unmatched subnet rule
```
2. Define firewall objects in `firewall_objects_*` vars
3. Define firewall ruleset in `firewall_input_*` and `firewall_output_*` vars
4. (opt) Disable IPv6 using `firewall_enable_ipv6: False`
5. (opt) Allow broadcast traffic in INPUT using `firewall_ignore_broadcasts: False`
6. (opt) Drop ICMP/ICMP6 ping using `firewall_ping_rate: 0`

See `defaults/main.yml` for more examples and tunales.

### On docker/podman nodes

- fw.sh script detects docker presence on host by looking for `DOCKER-USER` chain
- after installing docker or podman, either
  - manualy run `fw.sh` to re-integrate firewall rules with docker, or
  - restart host to so systemd runs fwsh.service on startup

> [!WARNING]
> Docker: Don't use `firewall_forward_*` or `firewall_ip_forwarding`.
> Only INPUT and OUTPUT rulesets are evaluated.
> Traffic filtering rules between containers is managed by docker!

### On routers / VPN concentrators / etc.
0. See what to do on "Normal endpoints", additionaly...
1. Override default firewall `LOG_DROP_DEFAULT` action *while testing*.
```
firewall_default_rule_forward: "LOG_WILL_DROP"            # forward rules without match
```
2. Enable IP forwarding using `firewall_ip_forward: 1`
3. Define `firewall_interfaces` for `CHECK_IF` / BCP38 / RFC 2827 / RPF checks
4. Define `firewall_forward` rules using addressess/nets/objects
4. Enabled SNAT/DNAT using `masquerade` or `dnat` rules in `firewall_interfaces`

## Firewall object definitions
Firewall object can be either:
- single IPv4/IPv6 addr or net
- (mixed) list of IPv4/IPv6 addrs or nets
- list of exiseting firewall objects and/or IPv4/IPv6 addrs or nets

Examples:
```
firewall_objects__example:
   PUB: 10.0.0.0/24
   DMZ:
     - 10.0.1.0/24
     - 10.0.2.0/24
   foo.example.com: 1.1.1.1
   bar.example.com:
     - 10.0.1.34
   EXAMPLE:
     - foo.example.com
     - bar.example.com
   BAZ: 
     - EXAMPLE
     - 1.2.3.0/24
     - 1.1.1.1
```

## Firewall rules
Firewall input/output/forward rule can have:
 - one (str) or more (str[]) source (src) IPv4/IPv6 addresses / nets or named firewall objects
 - one (str) or more (str[]) destination (dst) IPv4/IPv6 addresses / nets or named firewall objects
 - optional object with L4 protocol and ports (codes), where 
   - key is either name or /etc/protocols number
   - value is either one or more (comma separated) port numbers

Examples:
```
firewall_input__example:
  - name: ssh from lan
    src: LAN
    proto:
      tcp: 22
  - name: specific host from DMZ can't access elastic
    src: bar.example.com
    dst: 10.10.10.0/24
    proto: 
      tcp: 9300
    rule: LOG_REJECT        # or LOG_DROP
  - name: elastic from DMZ segment (without logging)
    src: DMZ
    dst: 10.10.10.0/24
    proto: 
      tcp: 9200, 9300
      udp: 100:110
    rule: ACCEPT
  - src: 10.20.30.40
    proto:
      icmp: 13
      
```

## `firewall_interfaces` definitions

Examples:
```
firewall_interfaces:
   mngPhys:
     deny:
     - 10.0.0.128/26
     - 10.0.0.192/26
     default: allow
     masquerade:
     - 10.0.0.128/26
     - 10.0.0.192/26
   mngHw:
     allow: 10.0.0.64/26
     allow_dhcp: true
   iscsi0:
     allow: 10.0.0.128/26
   iscsi1:
     allow: 10.0.0.192/26
```


## Troubleshooting
- Web building ruleset, use `LOG_WILL_DROP` actions as `firewall_default_*` actions
- `dmesg -w | grep FW` or `journalct -f`
- manually run `fw.sh`...
