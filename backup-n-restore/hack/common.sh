#/usr/bin/env bash

ROOTDIR=$(git rev-parse --show-toplevel)

DEFAULTS3PROVIDER=aws
DEFAULTBUCKET=velero-backup-acm
DEFAULTS3REGION=us-east-1

################################################################################
# Check static prerequisites 
################################################################################
command -v oc >/dev/null 2>&1 || { echo >&2 "can't find oc.  Aborting."; exit 1; }


#check jq
command -v jq >/dev/null 2>&1 || { echo >&2 "can't find jq.  Aborting."; exit 1; }

#check velero (version tool)
command -v velero >/dev/null 2>&1 || { echo >&2 "can't find velero.  Aborting."; exit 1; }


veleroversion=$(velero version --client-only | awk '/Version/ {print $2}')
if [ "$veleroversion" != "v1.6.0-rc.2" ]; then
    echo "It appears you've velero $veleroversion. The environment has been tested with velero v1.6.0-rc.2"
    exit 1
fi


#check aws 
command -v aws >/dev/null 2>&1 || { echo >&2 "can't find aws.  Aborting."; exit 1; }

echo_red() {
  printf "\033[0;31m%s\033[0m" "$1"
}

echo_yellow() {
  printf "\033[1;33m%s\033[0m\n" "$1"
}

echo_green() {
  printf "\033[0;32m%s\033[0m\n" "$1"
}

wait_until() {
  local script=$1
  local wait=${2:-1}
  local timeout=${3:-10}
  local i

  script_pretty_name=${script//_/ }
  times=$(echo "($(bc <<< "scale=2;$timeout/$wait")+0.5)/1" | bc)
  for i in $(seq 1 "${times}"); do
      local out=$($script)
      if [ "$out" == "0" ]; then
	  echo_green "${script_pretty_name}: OK"
      return 0
      fi
      echo_yellow "${script_pretty_name}: Waiting...$wait second(s)"
      sleep $wait
  done
  echo_red "${script_pretty_name}: ERROR"
  return 1
}

namespace_active() {
  namespace=$1

  rv="1"
  phase=$(kubectl get ns "$namespace" -o jsonpath='{.status.phase}' 2> /dev/null)
  if [ "$phase" == "Active" ]; then
      rv="0"
  fi

  echo ${rv}
  
}


deployment_up_and_running() {
    namespace=$1
    deployment=$2
    
    rv="1"
    zero=0
    #TODO troubleshoot --ignore-not-found
    desiredReplicas=$(oc get deployment ${deployment} -n ${namespace} -ojsonpath="{.spec.replicas}" --ignore-not-found)
    readyReplicas=$(oc get deployment ${deployment} -n ${namespace} -ojsonpath="{.status.readyReplicas}" --ignore-not-found)
    if [ "${desiredReplicas}" == "${readyReplicas}" ] && [ "${desiredReplicas}" != "${zero}" ]; then
	    rv="0"
    fi

    echo ${rv}
}



deploy_velero() {
    local bucketname=$1
    local region=$2
    local s3credentials=$3

    [ -f ${s3credentials} ] || { echo_red "Unable to deploy velero... Credential file ${s3credentials} does not exist"; exit 1; }
    
    cat ${ROOTDIR}/backup-n-restore/artifacts/templates/install_velero_aws.yaml.tpl | \
	sed "s/BUCKET/${bucketname}/; s/BACKUPSTORAGELOCATIONREGION/${region}/; s/VOLUMESNAPSHOTLOCATIONREGION/${region}/; s/S3CREDENTIALS/$(cat ${s3credentials} | base64 -w 0)/" | oc  apply -f -

}




