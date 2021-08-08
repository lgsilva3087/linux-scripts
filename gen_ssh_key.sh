#!/usr/bin/env sh
KEY_TYPE=ed25519
SSH_KEYGEN=$(which ssh-keygen)
[ $? -eq 0 ] || exit 1
COMMAND=$(echo ${SSH_KEYGEN} -o -a 256 -t ${KEY_TYPE} -f ~/.ssh/id_${KEY_TYPE} -C "${USER}@$(hostname)_$(date +'%Y%m%d')")
echo ${COMMAND}
${COMMAND}
chmod -R go-rwx,u=rwX ~/.ssh
