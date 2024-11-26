#!/bin/bash

for RES in $( crm conf show | grep 'cli-prefer' | awk '{print $3}' ); do
  echo "unmove $RES"
  #read -p "Press Enter to continue..."
  crm res clear $RES
done
