1. enable stats.log output with totals enabled in `/etc/suricata/suricata.yaml` and reload suricata
```
  - stats:
      enabled: yes
      filename: stats.log
      append: yes       # append to file (yes) or overwrite it (no)
      totals: yes       # stats for all threads merged together
      threads: no       # per thread stats
```

2. add suricata UserParameters to zabbix agent
```
cp suricata.conf /etc/zabbix/zabbix_agent2.d/
```

3. tune and deploy cron job responsible for filtering suricata stats.log to stats.last file
(makes everything go faster :P)
```
cp zabbix-suricata-cron /etc/cron.d/
```

4. import `zbx_export_templates.xml` to your zabbix 

