#!/bin/bash

curl -XPUT http://localhost:9200/_snapshot/{{ backup_elastic_repository }}/snapshot-$(date +"%d.%m.%Y")?wait_for_completion=true
