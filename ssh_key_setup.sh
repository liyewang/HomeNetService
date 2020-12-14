#!/bin/bash

key_path="id_rsa.pub"

opt=1
echo '1. Create a key pair for this device'
echo '2. Import a public key from other device'
echo
read -p "Please input an option[${opt}]: " input
if [ "${input}" != "" ]; then opt=${input}; fi
if [ "${opt}" = "1" ]; then
    ssh-keygen
else
    read -p "Specify the public key[${key_path}]: " input
    if [ "${input}" != "" ]; then key_path=${input}; fi
    if [ ! -f ${key_path} ]; then
        echo "${key_path} not found."
        exit 1
    else
        if [ ! -d ~/.ssh ]; then mkdir ~/.ssh; fi
        if [ ! -f ~/.ssh/authorized_keys ]; then
            touch ~/.ssh/authorized_keys
            chmod 600 ~/.ssh/authorized_keys
        fi
        cat ${key_path} >> ~/.ssh/authorized_keys
        echo 'Success'
    fi
fi
exit 0
