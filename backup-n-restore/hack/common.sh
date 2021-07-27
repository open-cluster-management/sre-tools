#/usr/bin/env bash

ROOTDIR=$(git rev-parse --show-toplevel)
VELERO_BIN_PATH=~/bin
VELERO_INSTALL_URL=https://github.com/vmware-tanzu/velero/releases/download/v1.6.0/velero-v1.6.0-linux-amd64.tar.gz

DEFAULT_BACKUPNAME=backup-acm-sre
DEFAULT_S3PROVIDER=aws
DEFAULT_BUCKET=velero-backup-acm
DEFAULT_S3REGION=us-east-1

if [[ "$OSTYPE" == "darwin"* ]]; then
    BASE64_ENCODE=base64
else
    BASE64_ENCODE=base64 -w0
fi


################################################################################
# Check static prerequisites 
################################################################################
command -v oc >/dev/null 2>&1 || { echo >&2 "can't find oc.  Aborting."; exit 1; }

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

    #create CRDs first
    oc create -f ${ROOTDIR}/backup-n-restore/artifacts/crds/velero.yaml

    local CRDS=("backups.velero.io"
      "backupstoragelocations.velero.io"
      "deletebackuprequests.velero.io"
      "downloadrequests.velero.io"
      "podvolumebackups.velero.io"
      "podvolumerestores.velero.io"
      "resticrepositories.velero.io"
      "restores.velero.io"
      "schedules.velero.io"
      "serverstatusrequests.velero.io"
      "volumesnapshotlocations.velero.io"
    )

    local CRDS_FOUND=0

   
    while [[ $CRDS_FOUND == 0 ]];
    do
      for i in ${!CRDS[@]}
      do
        oc get crd ${CRDS[$i]} >/dev/null 2>&1

        if [[ $? == 0 ]]; then
          echo_green "Found CRD: ${CRDS[$i]}"
          CRDS_FOUND=1
          continue
        else
          echo_yellow "Did not find CRD:${CRDS[$i]}"
          CRDS_FOUND=0
          break
        fi
      done

      if [[ $CRDS_FOUND == 1 ]];
      then
        echo_green "Found all CRDs..."
        break
      fi
    done
    
    cat ${ROOTDIR}/backup-n-restore/artifacts/templates/install_velero_aws.yaml.tpl | \
	sed "s/BUCKET/${bucketname}/" | \
	sed "s/BACKUPSTORAGELOCATIONREGION/${region}/" | \
	sed "s/VOLUMESNAPSHOTLOCATIONREGION/${region}/" | \
	sed "s/S3CREDENTIALS/$(cat ${s3credentials} | ${BASE64_ENCODE} )/" | \
	oc  apply -f -
}


backup_finished() {
    local namespace=$1
    local backupname=$2
    rv="1"
    backupphase=$(oc get backup $backupname -n $namespace --ignore-not-found -o jsonpath='{.status.phase}')
    if [ "${backupphase}" == "Completed" ] || [ "${backupphase}" == "PartiallyFailed" ] || [ "${backupphase}" == "Failed" ]
    then
	rv="0"
    fi
    echo ${rv}
}



restore_finished() {
    local namespace=$1
    local restorename=$2

    rv="1"
    restorephase=$(oc get restore $restorename -n $namespace -o jsonpath='{.status.phase}')
    if [ "${restorephase}" == "Completed" ] || [ "${restorephase}" == "PartiallyFailed" ] || [ "${restorephase}" == "Failed" ]
    then
	rv="0"
    fi
    echo ${rv}
}


# register_managed_clusters modifies the boostrap kubeconfig in every managed cluster. It also creates 
# creates clusterrole and clusterrolebdings for the <managed cluster name> in th new hub
#
register_managed_clusters() {
    server=$(oc config view -o jsonpath='{.clusters[0].cluster.server}')
    echo_green "Server -> $server"

    for managedclustername in $(oc get ns -lcluster.open-cluster-management.io/managedCluster -o jsonpath='{.items[*].metadata.name}');
    do managed_kubeconfig_secret=$(oc get secret -o name -n $managedclustername | grep admin-kubeconfig);
       if [ -z "${managed_kubeconfig_secret}" ]; then #this will skip local-cluster as well
	   echo "skipping $managedclustername"
	   continue
       fi

       managed_kubeconfig_secret=$(basename $managed_kubeconfig_secret)
       managedclusterkubeconfig=$(mktemp)
       oc get secret $managed_kubeconfig_secret -n $managedclustername -o jsonpath={.data.kubeconfig} | base64 -d > $managedclusterkubeconfig
       
       server=$(oc config view -o jsonpath='{.clusters[0].cluster.server}')
       secretname=$(oc get secret -o name -n $managedclustername | grep ${managedclustername}-bootstrap-sa-token)
       ca=$(kubectl get ${secretname} -n ${managedclustername} -o jsonpath='{.data.ca\.crt}')
       token=$(kubectl get ${secretname} -n ${managedclustername} -o jsonpath='{.data.token}' | base64 --decode)
   
       newbootstraphubkubeconfig=$(mktemp)
       cat << EOF > ${newbootstraphubkubeconfig}
apiVersion: v1
kind: Config
clusters:
- name: default-cluster
  cluster:
    certificate-authority-data: ${ca}
    server: ${server}
contexts:
- name: default-context
  context:
    cluster: default-cluster
    namespace: default
    user: default-auth
current-context: default-context
users:
- name: default-auth
  user:
    token: ${token}
EOF
       
       echo_yellow "Created $newbootstraphubkubeconfig"
       
       oc --kubeconfig=$managedclusterkubeconfig delete secret  bootstrap-hub-kubeconfig -n open-cluster-management-agent
       
       oc --kubeconfig=$managedclusterkubeconfig create secret generic bootstrap-hub-kubeconfig --from-file=kubeconfig="${newbootstraphubkubeconfig}" -n open-cluster-management-agent
       rm -rf $managedclusterkubeconfig
       if [ $? -eq 0 ]
       then
           echo_green "tmp kubeconfig $managedclusterkubeconfig deleted"
       fi
       
           
       # Update syncset kubeconfig with newbootstraphubkubeconfig
       oldboostraphubkconfig=$(oc get syncset ${managedclustername}-klusterlet -n ${managedclustername} -o jsonpath='{.spec.resources[*].data.kubeconfig}')
       
       encodedNewbootstraphubkubeconfig=$(cat $newbootstraphubkubeconfig | ${BASE64_ENCODE})
       oc get syncset ${managedclustername}-klusterlet -n ${managedclustername} -o yaml | sed "s/${oldboostraphubkconfig}/${encodedNewbootstraphubkubeconfig}/" | oc replace -f -
       rm -rf $newbootstraphubkubeconfig
       if [ $? -eq 0 ]
       then
	   echo_green "tmp kubeconfig $newbootstraphubkubeconfig deleted"
       fi

       cat << EOF | oc  apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: system:open-cluster-management:managedcluster:bootstrap:${managedclustername}
rules:
- apiGroups:
  - certificates.k8s.io
  resources:
  - certificatesigningrequests
  verbs:
  - create
  - get
  - list
  - watch
- apiGroups:
  - cluster.open-cluster-management.io
  resources:
  - managedclusters
  verbs:
  - get
  - create
EOF

       cat << EOF | oc  apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  managedFields:
  name: system:open-cluster-management:managedcluster:bootstrap:${managedclustername}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:open-cluster-management:managedcluster:bootstrap:${managedclustername}
subjects:
- kind: ServiceAccount
  name: ${managedclustername}-bootstrap-sa
  namespace: ${managedclustername}
EOF

        cat << EOF | oc  apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: open-cluster-management:managedcluster:${managedclustername}
rules:
- apiGroups:
  - certificates.k8s.io
  resources:
  - certificatesigningrequests
  verbs:
  - create
  - get
  - list
  - watch
- apiGroups:
  - register.open-cluster-management.io
  resources:
  - managedclusters/clientcertificates
  verbs:
  - renew
- apiGroups:
  - cluster.open-cluster-management.io
  resourceNames:
  - ${managedclustername}
  resources:
  - managedclusters
  verbs:
  - get
  - list
  - update
  - watch
- apiGroups:
  - cluster.open-cluster-management.io
  resourceNames:
  - ${managedclustername}
  resources:
  - managedclusters/status
  verbs:
  - patch
  - update
EOF

	cat << EOF | oc  apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: open-cluster-management:managedcluster:${managedclustername}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: open-cluster-management:managedcluster:${managedclustername}
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: system:open-cluster-management:${managedclustername}
EOF

    done

}

# accepts_managed_clusters iterates over all the managed clusters and accept the certificate
accepts_managed_clusters() {
    for managedclustername in $(oc get ns -lcluster.open-cluster-management.io/managedCluster -o jsonpath='{.items[*].metadata.name}');
    do previoushubhaccepted=$(oc get ns ${managedclustername} -o jsonpath='{.metadata.annotations.open-cluster-management\.io/srchubacceptsclient}');
       #TODO: check previoushubhaccepted is defined
       if  [ "${previoushubhaccepted}" == "true" ];
	   then
	       oc patch managedcluster ${managedclustername} -p='{"spec":{"hubAcceptsClient":true}}' --type=merge;
	       if [ $? -eq 0 ]	 		
	       then
		   echo_green "Managed cluster ${managedclustername} accepted"
	       else
		   echo_red "Unable to accept managed cluster ${managedclustername}" 
	       fi
       else
	   echo_red "Skipping managed cluster $managedclustername as it was not accepted"
       fi
       
        
    done
}


backups_available() {
    rv="1"
    howmanybackups=0
    for bck in $(oc get backups -n velero --sort-by=.status.startTimestamp  -o jsonpath='{.items[?(@.status.phase=="Completed")].metadata.name}');
    do
	let howmanybackups+=1
    done
    if  [ $howmanybackups -ne 0 ]
    then
	rv="0"	
    fi
    echo ${rv}    
}

#kconfig_or_context inferrs whether the parameter is a Kubeconfi file or a context name. It returns the oc/kubectl parameter
kconfig_or_kcontext() {
    if [ $# -ne 1 ];
    then
	echo_red "One (and only one) parameter is admitted: either a kubeconfig file path oa string context name"
	exit
    fi
    if [ -z "$1" ];
    then
	echo_red "Emtpy parameter given. Cannot continue."
	exit
    fi
    kforctxt=${1}
    if [ -f ${kforctxt} ];
    then
	echo "--kubeconfig=${kforctxt}"
    else
	echo "--context=${kforctxt}"
    fi
}


deployment_scaled_to_zero() {
    contextorkubeconfig=$1
    namespace=$2
    deployment=$3

    rv="1"
    desiredReplicas=$(oc $(kconfig_or_kcontext ${contextorkubeconfig}) get deployment ${deployment} -n ${namespace} -ojsonpath="{.spec.replicas}" --ignore-not-found)
    availableReplicas=$(oc get $(kconfig_or_kcontext ${contextorkubeconfig}) deployment ${deployment} -n ${namespace} -ojsonpath="{.status.availebleReplicas}")
    if [ "${desiredReplicas}" == "0" ] && [ -z "$availableReplicas" ];
    then
	rv="0"
    fi
    echo ${rv}
}

#detach_clusters detach the managedcluster from the previous HUB src
detach_clusters() {
    HUBSRC=${1}
    if [ -z ${HUBSRC} ];
    then
	echo_red "Unable to connect to HUB... Missing kubeconfig or context" 
	echo "1"
	return
    fi

    for managedclustername in $(oc $(kconfig_or_kcontext ${HUBSRC}) get ns -lcluster.open-cluster-management.io/managedCluster -o jsonpath='{.items[*].metadata.name}');
    do [ ${managedclustername} == "local-cluster" ] && continue;
     
       oc $(kconfig_or_kcontext ${HUBSRC}) patch clusterdeployment/${managedclustername} -n  ${managedclustername} --type=json --patch='[ { "op": "add", "path": "/spec/preserveOnDelete", "value":true}]'

       oc $(kconfig_or_kcontext ${HUBSRC}) patch clusterdeployment/${managedclustername} -n  ${managedclustername} --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' 
       oc $(kconfig_or_kcontext ${HUBSRC}) delete clusterdeployment/${managedclustername} -n ${managedclustername} --wait=true
        oc $(kconfig_or_kcontext ${HUBSRC}) patch managedcluster/${managedclustername} -n  ${managedclustername} --type json   --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' 
       oc $(kconfig_or_kcontext ${HUBSRC}) delete managedcluster/${managedclustername} --wait=true    
    done
    # Now delete namespace
    for managedclustername in $(oc $(kconfig_or_kcontext ${HUBSRC}) get ns -lcluster.open-cluster-management.io/managedCluster -o jsonpath='{.items[*].metadata.name}');
    do [ ${managedclustername} == "local-cluster" ] && continue;
       oc patch namespace/${managedclustername} --type json   --patch='[ { "op": "remove", "path": "/spec/finalizers" } ]' 
       oc $(kconfig_or_kcontext ${HUBSRC} ) delete namespace ${managedclustername} --wait=true       
    done
    echo "0"
    return

}
