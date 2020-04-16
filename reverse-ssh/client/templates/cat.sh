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
	-l cat {{ reverse_ssh_server.server_addr }} -R {{ 2000 + reverse_ssh.id }}:127.0.0.{{ reverse_ssh.id }}:22 
