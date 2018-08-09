#!/bin/sh
#
# smartctl-disks.sh [<dev> <disk_type> [client_hostname_in_zabbix]]
# Example1: smartctl-disks.sh
# Example2: smartctl-disks.sh sda sat
#
# 20171130 v1.0 stas630
# sudo apt-get install smartmontools
#
# 20180214 johnny
# support for static device list and cciss,* devices
#
ZBX_CONFIG_AGENT="/etc/zabbix/zabbix_agentd.conf"
DEV_LIST="/etc/zabbix/smartctl-devices.json"
#LOG="/var/log/zabbix/smartctl-disks.log"
LOG=""


export PATH=/sbin:/usr/sbin:/bin:/usr/bin

DEV_NAME="$1"
DEV_TYPE="$2"
HOSTNAME="$3"

ESC_DEV_TYPE="$2"
echo $DEV_TYPE | grep ',' >/dev/null && ESC_DEV_TYPE="\"$DEV_TYPE\""

if [ -z ${DEV_NAME} ]; then
  if [ -f $DEV_LIST ]; then
    cat $DEV_LIST
    exit 0
  fi
  sudo /usr/sbin/smartctl --scan-open | awk 'BEGIN{print "{\"data\":["}{
    if(NR!=1){
      printf ","
    }
	printf "{ \"{#DEVNAME}\":\""substr($1,6)"\", \"{#VISNAME}\":\""substr($1,6)"\", \"{#DEVTYPE}\":\""$3"\" }\n"
  }END{
    print "]}"
  }'
  exit 0
fi

TMPS=`mktemp -t zbx-smart.XXXXXXXXXXXXXXXXXXX`

sudo /usr/sbin/smartctl -A -H -i -d ${DEV_TYPE} /dev/${DEV_NAME} | awk 'BEGIN{
  INFO_FIELDS=";Model Family;Device Model;Serial Number;Firmware Version;User Capacity;Sector Size;Rotation Rate;"
  ATTR_FIELDS=";1;3;4;5;7;9;10;11;12;177;190;192;193;194;196;197;198;199;200;233;241;242;"
}
function trim(s){
  sub(/^[ \t]+/,"",s)
  sub(/[ \t]+$/,"",s)
  return s;
}
function toattr(s){
  gsub(/ /,"_",s)
  return tolower(s);
}
{
  if($0=="=== START OF INFORMATION SECTION ==="){ type="info"; next
  }else if($0=="=== START OF READ SMART DATA SECTION ==="){ type="healf"; next
  }else if($1=="ID#"){ type="attr"; next
  }
  if(type=="info"){
    split($0,linearr,":")
    if(index(INFO_FIELDS,";"trim(linearr[1])";")){
      print "'$HOSTNAME' smartctl.info['${DEV_NAME}','${ESC_DEV_TYPE}',"toattr(trim(linearr[1]))"] \""trim(linearr[2])"\"" >"'${TMPS}'"
    }
    next
  }
  if(type=="healf"){
    split($0,linearr,":")
    if(linearr[1]=="SMART overall-health self-assessment test result"){
      print trim(linearr[2])
    }
    next
  }
  if(type=="attr"){
    if(NF<10||!index(ATTR_FIELDS,";"$1";")) next
    print "'$HOSTNAME' smartctl.smart['${DEV_NAME}','${ESC_DEV_TYPE}',"$1",value] "$4 >"'${TMPS}'"
    print "'$HOSTNAME' smartctl.smart['${DEV_NAME}','${ESC_DEV_TYPE}',"$1",worst] "$5 >"'${TMPS}'"
    print "'$HOSTNAME' smartctl.smart['${DEV_NAME}','${ESC_DEV_TYPE}',"$1",thresh] "$6 >"'${TMPS}'"
    print "'$HOSTNAME' smartctl.smart['${DEV_NAME}','${ESC_DEV_TYPE}',"$1",raw_value] "$10 >"'${TMPS}'"
  }
}'

if [ -z ${HOSTNAME} ]; then
  cat ${TMPS}
elif [ -s ${TMPS} ]; then
  if [ -z ${LOG} ]; then
    zabbix_sender -c ${ZBX_CONFIG_AGENT} -i ${TMPS}
  else
    zabbix_sender -c ${ZBX_CONFIG_AGENT} -i ${TMPS} -vv >> ${LOG} 2>&1
	cat ${TMPS} >> ${LOG}
  fi
fi

rm -f ${TMPS}
