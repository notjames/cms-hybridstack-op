#!/bin/bash

#set -x
workers()
{
  aws ec2 describe-instances \
    --filters "Name=tag:cms_id,Values=${CLUSTER_ID}" "Name=tag:role,Values=worker" \
    --query 'Reservations[].Instances[].PublicIpAddress'
}

chk_prereqs()
{
  [[ ! -x $(which jq) ]] && \
    {
      echo >&2 "Please install 'jq'. It is required for this script to work."
      return 25
    }

  [[ ! -x $(which aws) ]] && \
    {
      echo >&2 "Please install 'aws'. It is required for this script to work."
      return 25
    }

  if [ -z "${CLUSTER_ID}" ]; then
      echo "CLUSTER_ID must be set. Hint: export CLUSTER_ID=<cluster_id>"
      return 26
  fi

  if [ -z "${AVAILABILITY_ZONE}" ]; then
      echo "AVAILABILITY_ZONE must be set"
      return 27
  fi
}

aws_cf_status()
{
  aws cloudformation describe-stack-events \
    --stack-name "${CLUSTER_ID}" \
    --query 'StackEvents[0].ResourceStatus' \
    --output text
}

cloudform()
{
  [[ ! -f "$CLUSTER_TEMPLATE" ]] && \
    {
      echo >&2 """
  The template '${CLUSTER_TEMPLATE}' does not exist in ${TMPL_PATH}.
  Please fix your '\$INSTANCE_OS_NAME' and/or '\$INSTANCE_OS_VER' env variables
  to match a template in ${BASEDIR}.
      """
      exit 21
    }

  # Be opinionated about where CLUSTER_TYPE should be
  # currently in the front. If it's in the end, remove it.
  if echo "$CLUSTER_ID" | grep -Pq '[-_]manage[rd]$'; then
    CLUSTER_ID="$CLUSTER_TYPE-${CLUSTER_ID/[-_]manage[rd]$/}"
  fi

  # If CLUSTER_TYPE is not currently in the front, add it.
  if ! echo "$CLUSTER_ID" | grep -Pq '^manage[rd]'; then
    CLUSTER_ID="${CLUSTER_TYPE}-${CLUSTER_ID}"
  else
    # otherwise, if it's there, make sure it's correct
    CLUSTER_ID="${CLUSTER_ID/^manage[rd][-_]/${CLUSTER_TYPE}-}"
  fi

#  if ! aws s3 mb s3://${S3_BUCKET} > /dev/null 2>&1; then
#    aws s3 mb s3://${S3_BUCKET}
#  fi

#                               --s3-bucket "${S3_BUCKET}" \
  if ! aws cloudformation deploy --stack-name="${CLUSTER_ID}" \
                                 --template-file "${CLUSTER_TEMPLATE}" \
                                 --capabilities CAPABILITY_IAM \
                                 --parameter-overrides \
      CmsId="${CLUSTER_ID}"                   \
      KeyName="${key_name}"                   \
      username="${CLUSTER_USERNAME}"          \
      InstanceType="${INSTANCE_TYPE}"         \
      DiskSizeGb="${DISK_SIZE_GB}"            \
      AvailabilityZone="${AVAILABILITY_ZONE}" \
      SSHLocation="${SSH_LOCATION}"           \
      K8sNodeCapacity="${K8S_NODE_CAPACITY}" | tee "${CREATED}"; then
    return 1
  else
    while [[ "$(jq ". | length" <<< "$(workers)")" -lt "${K8S_NODE_CAPACITY}" ]]; do
      if [[ $(aws_cf_status) =~ ROLLBACK|DELETE ]]; then
        echo >&2 "CF Failed. Please check AWS console for reason of failure."
        return 1
      fi

      sleep "${S_TIME}"
      S_TIME=$((S_TIME * S_TIME))
    done
  fi
}

# courtesy of SO (/questions/630372/determine-the-path-of-the-executing-bash-script)
BASEDIR=$(cd -P -- "$(dirname -- "$0")" && cd ../ && pwd -P)
S3_BUCKET="${S3_BUCKET:-make-cluster-nodes}"
INSTANCE_TYPE=${INSTANCE_TYPE:-m4.large}
DISK_SIZE_GB=${DISK_SIZE_GB:-40}
SSH_LOCATION=${SSH_LOCATION:-0.0.0.0/0}
K8S_NODE_CAPACITY=${K8S_NODE_CAPACITY:-1}
INSTANCE_OS_NAME=${INSTANCE_OS_NAME:-centos}
CLUSTER_USERNAME=${CLUSTER_USERNAME:-$INSTANCE_OS_NAME}
INSTANCE_OS_VER=${INSTANCE_OS_VER:-7.4}
TMPL_PATH="$BASEDIR/templates"
CLUSTER_TEMPLATE="$TMPL_PATH/cluster-${INSTANCE_OS_NAME}-${INSTANCE_OS_VER}-cf.template"
CREATED=$(mktemp)
S_TIME=2
key_mgmt="bin/aws_key_management.sh"

if [[ -f $key_mgmt ]]; then
  # shellcheck disable=SC1091
  . "$key_mgmt"
else
  echo >&2 "Unable to continue. Cannot find aws_key_management.sh"
  exit 13
fi

if ! get_key_material; then
  echo >&2 """
  This script tries to use existing key material in ${KEY_HOME} based on the \$CLUSTER_ID.
  If key material doesn't exist, this script uses AWS to create new key material, which
  will be stored as ${private_key}. In some cases AWS may attempt to create a key that was
  neither able to be imported nor uniquely created. In these cases, you may need to run
  the following command and re-create the CF stack.

  To delete the AWS key use the command:
  aws ec2 delete-key-pair --key-name ${key_name}

  """

  exit 20
fi

if cloudform; then
  echo "Done"
else
  exit 20
fi
