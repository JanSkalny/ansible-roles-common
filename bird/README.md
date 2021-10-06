## Sample configuration
```
bird_filters:
  accept_b_routes:
    accept:
      - 192.0.2.0/24
      - 10.10.10.0/24
  reject_b_routes:
    reject:
      - 192.0.2.0/24
      - 10.10.10.0/24
  accept_only_a_routes:
    accept:
      - 10.10.10.69/32
      - 10.10.10.70/32
      - 10.10.10.71/32
      - 10.10.10.72/32
      - 10.10.10.74/32
      - 10.10.10.73/32
      - 192.0.2.0/27
      - 192.0.2.128/27
      - 192.0.2.160/27
      - 10.10.10.65/32

bird6_filters:
  accept_b_routes:
    reject:
      - 2001:1:22:1::/64
      - 2001:1:22:110::/60
  reject_b_routes:
    reject:
      - 2001:1:22:1::/64
      - 2001:1:22:110::/60
  accept_only_a_routes:
    accept:
      - 2001:1:22:110::/60

bird_bgp_instances:
  core:
    asn: 65022
    peers:
      r1:
        asn: 65022
        addr: 192.0.2.161
        password: XXX
        export: filter accept_b_routes
        import: filter reject_b_routes
      r2: 
        asn: 65022
        addr: 192.0.2.165
        password: YYY
        export: filter accept_b_routes
        import: filter reject_b_routes

bird_ospf_instances:
  b:
    import: filter accept_only_a_routes
    export: all
    areas:
      - id: 0.0.0.0
        interfaces:
          - name: "ens225.*"
            stub: 1
          - name: "ens256.*"
            stub: 1
          - name: "ens193.*"
            stub: 1
          - name: "ens161.*"
            auth_md5: ZZZ

bird6_bgp_instances:
  core:
    asn: 65022
    peers:
      r1:
        asn: 65022
        addr: 2001:1:22:19::1
        password: XXX
        export: filter accept_b_routes
        import: filter reject_b_routes
      r2: 
        asn: 65022
        addr: 2001:1:22:20::1
        password: YYY
        export: filter accept_b_routes
        import: filter reject_b_routes

bird6_ospf_instances:
  b:
    import: filter accept_only_a_routes
    export: all
    areas:
      - id: 0.0.0.0
        interfaces:
          - name: "ens225.*"
            stub: 1
          - name: "ens256.*"
            stub: 1
          - name: "ens193.*"
            stub: 1
          - name: "ens161.*"
```
