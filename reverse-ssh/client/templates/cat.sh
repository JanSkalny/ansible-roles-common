#!/bin/sh

exec > /dev/null 2>&1

sleep 5

ssh -tt \
	-o BatchMode=yes \
	-o ServerAliveInterval=15 \
	-o ServerAliveCountMax=3 \
	-o SetupTimeout=30 \
	-o ConnectTimeout=30 \
	-o ConnectionAttempts=1 \
	-l {{ reverse_ssh.user }} {{ reverse_ssh_server.server_addr }} -R 127.0.0.1:{{ 2000 + reverse_ssh.id }}:127.0.0.1:22 
