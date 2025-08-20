#!/bin/bash

# enable logging
exec > >(tee /dev/ttyS0 /var/log/stackscript.log) 2>&1

# modes
#DEBUG="NO"
if [[ -n ${DEBUG} ]]; then
  if [ "${DEBUG}" == "NO" ]; then
    trap "cleanup $? $LINENO" EXIT
  fi
else
  trap "cleanup $? $LINENO" EXIT
fi

# cleanup will always happen. If DEBUG is passed and is anything
# other than NO, it will always trigger cleanup. This is useful for
# ci testing and passing vars to the instance.

if [ "${MODE}" == "staging" ]; then
  trap "provision_failed $? $LINENO" ERR
else
  set -e
fi

# ELK PoC

## Linode/SSH Security Settings
#<UDF name="token_password" label="Your Linode API token" />
#<UDF name="clusterheader" label="Cluster Settings" default="Yes" header="Yes">
#<UDF name="user_name" label="The limited sudo user to be created for the Linode: *No Capital Letters or Special Characters*">
#<UDF name="disable_root" label="Disable root access over SSH?" oneOf="Yes,No" default="No">

## Domain Settings
#<UDF name="subdomain" label="Subdomain" example="The subdomain for the DNS record. `www` will be entered if no subdomain is supplied (Requires Domain)" default="">
#<UDF name="domain" label="Domain" example="The domain for the DNS record: example.com (Requires API token)" default="">

# ELK Settings #

# Cluster name
#<UDF name="cluster_name" label="Cluster Name">

# Kibana size
#<UDF name="cluster_size" label="Kinaba Size" oneOf="1,2" default="1">

# Cluster size ($prefix_cluster_size):
#<UDF name="elasticsearch_cluster_size" label="Elasticsearch Cluster Size" oneOf="2,3" default="2">
#<UDF name="logstash_cluster_size" label="Logstash Cluster Size" oneOf="2,4" default="2">

# Instance types($prefix_cluster_type):
#<UDF name="elasticsearch_cluster_type" label="Elasticsearch Instance Type" oneOf="Dedicated 4GB,Dedicated 8GB,Dedicated 16GB,Dedicated 32GB,Dedicated 64GB" default="Dedicated 4GB">
#<UDF name="logstash_cluster_type" label="Logstash Instance Type" oneOf="Dedicated 4GB,Dedicated 8GB,Dedicated 16GB,Dedicated 32GB,Dedicated 64GB" default="Dedicated 4GB">

# GIT REPO #

#GH_USER=""
#BRANCH=""
# git user and branch
if [[ -n ${GH_USER} && -n ${BRANCH} ]]; then
        echo "[info] git user and branch set.."
        export GIT_REPO="https://github.com/${GH_USER}/marketplace-clusters.git"
else
        export GH_USER="akamai-compute-marketplace"
        export BRANCH="main"
        export GIT_REPO="https://github.com/${GH_USER}/marketplace-clusters.git"
fi

export WORK_DIR="/tmp/marketplace-clusters" 
export MARKETPLACE_APP="apps/clusters/linode-marketplace-elk"
export UUID=$(uuidgen | awk -F - '{print $1}')

function provision_failed {
  echo "[info] Provision failed. Sending status.."

  # dep
  apt install jq -y

  # set token
  local token=($(curl -ks -X POST ${KC_SERVER} \
     -H "Content-Type: application/json" \
     -d "{ \"username\":\"${KC_USERNAME}\", \"password\":\"${KC_PASSWORD}\" }" | jq -r .token) )

  # send pre-provision failure
  curl -sk -X POST ${DATA_ENDPOINT} \
     -H "Authorization: ${token}" \
     -H "Content-Type: application/json" \
     -d "{ \"app_label\":\"${APP_LABEL}\", \"status\":\"provision_failed\", \"branch\": \"${BRANCH}\", \
        \"gituser\": \"${GH_USER}\", \"runjob\": \"${RUNJOB}\", \"image\":\"${IMAGE}\", \
        \"type\":\"${TYPE}\", \"region\":\"${REGION}\", \"instance_env\":\"${INSTANCE_ENV}\" }"
  
  exit $?
}

function cleanup {
  if [ -d "${WORK_DIR}" ]; then
    rm -rf ${WORK_DIR}
  fi

  # provisioner keys
  if [ -f "${HOME}/.ssh/id_ansible_ed25519{,.pub}" ]; then
    echo "[info] Removing provisioner keys.."
    rm ${HOME}/.ssh/id_ansible_ed25519{,.pub}
    destroy
  fi
}

# INSTANCE SETUP #

function add_privateip {
  echo "[info] Adding instance private IP"
  curl -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${TOKEN_PASSWORD}" \
      -X POST -d '{
        "type": "ipv4",
        "public": false
      }' \
      https://api.linode.com/v4/linode/instances/${LINODE_ID}/ips
}

function get_privateip {
  curl -s -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${TOKEN_PASSWORD}" \
   https://api.linode.com/v4/linode/instances/${LINODE_ID}/ips | \
   jq -r '.ipv4.private[].address'
}

function configure_privateip {
  LINODE_IP=$(get_privateip)
  if [ ! -z "${LINODE_IP}" ]; then
          echo "[info] Linode private IP present"
  else
          echo "[warn] No private IP found. Adding.."
          add_privateip
          LINODE_IP=$(get_privateip)
          ip addr add ${LINODE_IP}/17 dev eth0 label eth0:1
  fi
}

function rename_provisioner {
  INSTANCE_PREFIX=$(curl -sH "Authorization: Bearer ${TOKEN_PASSWORD}" "https://api.linode.com/v4/linode/instances/${LINODE_ID}" | jq -r .label)
  export INSTANCE_PREFIX="${INSTANCE_PREFIX}"
  echo "[info] renaming the provisioner"
  curl -s -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${TOKEN_PASSWORD}" \
      -X PUT -d "{
        \"label\": \"${INSTANCE_PREFIX}-${UUID}\"
      }" \
      https://api.linode.com/v4/linode/instances/${LINODE_ID}
}


# PROVISIONER SETUP

readonly ROOT_PASS=$(sudo cat /etc/shadow | grep root)
readonly TEMP_ROOT_PASS=$(openssl rand -base64 32)
readonly LINODE_PARAMS=($(curl -sH "Authorization: Bearer ${TOKEN_PASSWORD}" "https://api.linode.com/v4/linode/instances/${LINODE_ID}" | jq -r .type,.region,.image))
readonly TAGS=$(curl -sH "Authorization: Bearer ${TOKEN_PASSWORD}" "https://api.linode.com/v4/linode/instances/${LINODE_ID}" | jq -r .tags)
#readonly VARS_PATH="./group_vars/linode/vars"
readonly group_vars="${WORK_DIR}/${MARKETPLACE_APP}/group_vars/linode/vars"

# destroys all instances except provisioner node
function destroy {
  echo "[info] Destroying cluster nodes except provisioner..."
  ansible-playbook destroy.yml
}

function provisioner_sshkey {
  echo "[info] Creating provisioner SSH keys..."
  ssh-keygen -o -a 100 -t ed25519 -C "provisioner" -f "${HOME}/.ssh/id_ansible_ed25519" -q -N "" <<<y >/dev/null
  export PROVISIONER_SSH_PUB_KEY=$(cat ${HOME}/.ssh/id_ansible_ed25519.pub)
  export PROVISIONER_SSH_PRIV_KEY=$(cat ${HOME}/.ssh/id_ansible_ed25519)
  export SSH_KEY_PATH="${HOME}/.ssh/id_ansible_ed25519"
  chmod 700 ${HOME}/.ssh
  chmod 600 ${SSH_KEY_PATH}
  eval $(ssh-agent)
  ssh-add ${SSH_KEY_PATH}
  echo -e "\nprivate_key_file = ${SSH_KEY_PATH}" >> ansible.cfg
}

function provisioner_vars {
# Adds variables to configure cluster instances.
  sed 's/  //g' <<EOF > ${group_vars}
  # provisioner vars
  provisioner_ssh_pubkey: ${PROVISIONER_SSH_PUB_KEY}
  provisioner: ${INSTANCE_PREFIX}-${UUID}
  provisioner_prefix: ${INSTANCE_PREFIX}
  type: ${LINODE_PARAMS[0]}
  region: ${LINODE_PARAMS[1]}
  image: ${LINODE_PARAMS[2]}
  linode_tags: ${TAGS}
  uuid: ${UUID}
  token_password: ${TOKEN_PASSWORD}
  temp_root_pass: ${TEMP_ROOT_PASS}
  root_pass: "${ROOT_PASS}"
EOF
}

# UDF SETUP

function udf {
  sed 's/  //g' <<EOF >> ${group_vars}
  # sudo username
  username: ${USER_NAME}
EOF

  if [ "$DISABLE_ROOT" = "Yes" ]; then
    echo "disable_root: yes" >> ${group_vars};
  else echo "Leaving root login enabled";
  fi

  if [[ -n ${DOMAIN} ]]; then
    echo "domain: ${DOMAIN}" >> ${group_vars};
  else
    echo "default_dns: $(hostname -I | awk '{print $1}'| tr '.' '-' | awk {'print $1 ".ip.linodeusercontent.com"'})" >> ${group_vars};
  fi

  if [[ -n ${SUBDOMAIN} ]]; then
    echo "subdomain: ${SUBDOMAIN}" >> ${group_vars};
  else echo "subdomain: www" >> ${group_vars};
  fi

  # ELK vars

  if [[ -n ${CLUSTER_SIZE} ]]; then
    echo "kibana_cluster_size: ${CLUSTER_SIZE}" >> ${group_vars}
  fi
  if [[ -n ${ELASTICSEARCH_CLUSTER_SIZE} ]]; then
    echo "elasticsearch_cluster_size: ${ELASTICSEARCH_CLUSTER_SIZE}" >> ${group_vars}
  fi
  if [[ -n ${LOGSTASH_CLUSTER_SIZE} ]]; then
    echo "logstash_cluster_size: ${LOGSTASH_CLUSTER_SIZE}" >> ${group_vars}
  fi
  if [[ -n ${ELASTICSEARCH_CLUSTER_TYPE} ]]; then
    echo "elasticsearch_cluster_type: ${ELASTICSEARCH_CLUSTER_TYPE}" >> ${group_vars}
  fi
  if [[ -n ${LOGSTASH_CLUSTER_TYPE} ]]; then
    echo "logstash_cluster_type: ${LOGSTASH_CLUSTER_TYPE}" >> ${group_vars}
  fi      

  # staging or production mode (ci)
  if [[ "${MODE}" == "staging" ]]; then
    echo "[info] running in staging mode..."
    echo "mode: ${MODE}" >> ${group_vars}
  else
    echo "[info] running in production mode..."
    echo "mode: production" >> ${group_vars}
  fi  
}

# COMPLETE
function installation_complete {
  echo "Installation Complete!"
}

# MAIN

function run {
  # install dependencies
  export DEBIAN_FRONTEND=noninteractive
  apt-get update && apt-get upgrade -y
  apt-get install -y jq git python3 python3-pip python3-venv

  # add private IP address
  rename_provisioner
  configure_privateip

  # clone repo and set up Ansible environment
  echo "[info] Cloning ${BRANCH} branch from ${GIT_REPO}..."
  git -C /tmp clone -b ${BRANCH} ${GIT_REPO}
  cd ${WORK_DIR}/${MARKETPLACE_APP}
  python3 -m venv env
  source env/bin/activate
  pip install pip --upgrade
  pip install -r requirements.txt
  ansible-galaxy install -r collections.yml

  # populate group_vars
  provisioner_vars
  udf
  # run playbooks
  ansible-playbook -v provision.yml #&& ansible-playbook -v site.yml
}

# main
run
installation_complete