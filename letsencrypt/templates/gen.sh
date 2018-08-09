#!/bin/bash

CMD="/root/ssl/certbot-auto certonly -c cli.ini"

$CMD -d {{ansible_domain}} -d www.{{ansible_domain}} -d {{inventory_hostname}} -d mail.{{ ansible_domain }}
