#!/bin/bash
gitlab-rake gitlab:backup:create STRATEGY=copy
cp {{ backup_gitlab_dir }}/$(ls -t {{ backup_gitlab_dir }}/ | head -1) /var/backups/gitlab_backup.tar
