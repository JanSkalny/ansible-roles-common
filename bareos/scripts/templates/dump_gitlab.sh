#!/bin/bash
set -euo pipefail

gitlab-backup create STRATEGY=copy BACKUP=dump
mv -f -- /var/opt/gitlab/backups/dump_gitlab_backup.tar \
          /var/backups/gitlab_backup.tar
