#!/bin/sh

# deploy sudoers.d for setup user
echo -e "Defaults env_keep=SSH_AUTH_SOCK\n{{ virtual_setup_user }} ALL=NOPASSWD:ALL" > /target/etc/sudoers.d/setup 
chmod 0440 /target/etc/sudoers.d/setup 

# create ~/.ssh/authorized_keys
mkdir /target/home/{{ virtual_setup_user }}/.ssh 
echo -e "{{ lookup('file', root_dir+'/files/ssh-keys/'+virtual_setup_user).split('\n') | join('\\n') }}"  > /target/home/{{ virtual_setup_user }}/.ssh/authorized_keys 

# fix .ssh persmissions
TARGET_UID_GID=`grep '^{{ virtual_setup_user }}:' /target/etc/passwd | cut -f3,4 -d':'`
chown -R $TARGET_UID_GID "/target/home/{{ virtual_setup_user }}/.ssh"
chmod 700 /target/home/{{ virtual_setup_user }}/.ssh 
chmod 600 /target/home/{{ virtual_setup_user }}/.ssh/authorized_keys 

