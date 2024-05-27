# Notes
- download original template from https://git.zabbix.com/projects/ZBX/repos/zabbix/raw/templates/app/squid_snmp/template_app_squid_snmp.yaml?at=refs%2Fheads%2Frelease%2F6.4
-  translation table from original yaml, and incorporate into script
```
grep -A1 oid zbx_export_templates.yaml | awk '{print $2}' | paste - - - | sed 's/squid\[\(.*\)\]/\1/' | tr -d "'"  > squid-item-oid.map
```
- get rid of `type: SNMP_AGENT`
- get rid of `snmp_oid:.*`
- get rid of `Squid: service ping`
- add trigger to run `squid.update-stats`
