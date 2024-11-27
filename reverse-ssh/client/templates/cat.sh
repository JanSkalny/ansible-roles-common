#!/bin/sh

exec > /dev/null 2>&1

sleep 5

ssh -tt \
	-o BatchMode=yes \
	-o ExitOnForwardFailure=yes \
	-o ServerAliveInterval=15 \
	-o ServerAliveCountMax=3 \
	-o SetupTimeout=30 \
	-o ConnectTimeout=30 \
	-o ConnectionAttempts=1 \
	-p {{ reverse_ssh_server_port | default(22) }} \
	-R 127.0.0.1:{{ 2000 + reverse_ssh_client_id }}:127.0.0.1:22 \
	-l {{ reverse_ssh_server_user }} \
	{{ reverse_ssh_server_addr }}
