#!/bin/bash
find /opt/hole/data -name "*.pcap" -type f -mtime +90 -delete
