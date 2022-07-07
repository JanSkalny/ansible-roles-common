#!/bin/bash

tcpdump -n -i any -w '{{ hole_dir }}/data/{{ hole_name }}_%Y%m%d%H%M%S.pcap' -G 300 'not arp and src net not {{ networking[hole_interface].address | ansible.utils.ipaddr("network/prefix") }} and host not {{ networking[hole_interface].address | ansible.utils.ipaddr("address")}}'
