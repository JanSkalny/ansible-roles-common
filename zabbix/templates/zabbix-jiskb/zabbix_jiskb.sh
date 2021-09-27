#!/bin/bash
# V2.0

PROXY_SUFFIX=ingress
LOG=/var/log/zabbix/zabbix_jiskb.log

fail() {
	echo -e "$*" 1>&2
	exit 1
}

discovery() {
	jq -rRs "(. / \"\n\") - [\"\"] | {data: [ .[] | { \"{$1}\": . }] }"
}

web_instances() {
 ngnix_instances | xargs -n 1 -I {} docker exec {} sh -c 'cat /etc/nginx/conf.d/default.conf' |
	grep "server_name\ " | 
	awk '{print $NF}' | 
	sed 's/;//g' |
	sed 's/\r//g' | 
        grep -E '^www' |
        sed 's/www.//g' |
	sort -u	
}

ngnix_instances() {
 docker ps |
	grep -E ${PROXY_SUFFIX}$ |
	awk '{ print $NF }' 
}

ngnix_connections() {
 PROXY_INSTANCE=$1
 echo "PORT,STATUS"
 pid=`docker inspect -f '{{ .State.Pid }}' $PROXY_INSTANCE`
 nsenter -t $pid -n netstat -an | awk 'NF==6 {print $4 "," $6}' | cut -d: -f 2
 #nsenter -t $pid -n netstat -an | egrep ":$1\>" | grep $2 | wc -l
}

docker_containers() {
 docker ps | 
	grep 'jiskb' | 
	awk '{ print $NF }' 
}

docker_instances() {
 docker_containers  | 
	cut -d '_' -f 1 | 
	cut -d '-' -f 1 | 
 	sort -u 
}

docker_instance_containers() {
 docker_containers |
	grep -E "^$1" 
}

docker_container_status() {
 docker_containers |
	grep -E "^$1$" | 
 	xargs docker inspect |
	jq -r '.[0].State.Status'
}

docker_suffix_status() {
 docker_containers |
	grep -E "^$1" | 
	grep -E "$2$" |
 	xargs docker inspect |
	jq -r '.[0].State.Status'
}


#echo \$1=$1
#echo \$2=$2
#echo \$3=$3
#echo \$4=$4

echo `date` $0 $1 $2 $3 $4 >>$LOG

case "$1" in
	web.instances)
 		web_instances | discovery '#WEB_INSTANCE'
		;;
	ngnix.instances)
 		ngnix_instances | discovery '#NGNIX_INSTANCE'
		;;
	ngnix.connections)
	  [ $# -ne 2 ] && fail "usage: $0 ngnix_connections <NGNIX_INSTANCE>"
		ngnix_connections $2
		;;
	docker.instances)
		docker_instances | discovery '#DKR_INSTANCE' 
		;;
	docker.containers)
		docker_containers | discovery '#DKR_CONTAINER'
		;;
	docker.instance.containers)
 		[ $# -ne 2 ] && fail "usage: $0 docker.instance.containers <INSTANCE>"
		docker_instance_containers $2 | discovery '#DKR_CONTAINER'
		;;
	docker.suffix.status)
 		[ $# -ne 3 ] && fail "usage: $0 docker.suffix.status <INSTANCE> <suffix>"
		docker_suffix_status $2 $3
		;;
	docker.container.status)
 		[ $# -ne 2 ] && fail "usage: $0 docker.container.status <CONTAINER>"
		docker_container_status $2 
		;;
	*)
		fail "*** Unknown param
		Usage: $0  <option>
		<option> could be:
		  web.instances|
		  ngnix.instances|
		  ngnix.connections|
		  docker.instances|
		  docker.containers|
		  docker.instance.containers|
		  docker.suffix.status|
		  docker.container.status"
esac

