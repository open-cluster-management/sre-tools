#/usr/bin/env bash

set -x

ROOTDIR=$(git rev-parse --show-toplevel)
source ${ROOTDIR}/backup-n-restore/hack/common.sh


oc cluster-info
if [[ $? != "0" ]]; then 
    echo "Please login to the cluster you want to backup"
    exit 1
fi


#Mandatory namespaces in the backup
backupnamespaces=open-cluster-management,open-cluster-management-hub,hive,openshift-operator-lifecycle-manager



#Optional namespaces
others=open-cluster-management-agent,open-cluster-management-agent-addon


#Now Adds the labels to clusterroles, clusterrolebindings and APIservices

#To create a comma separeted list of existant namespaces. To avoid PartiallyFailed backups
IFS=',' read -ra NS <<< "$others"
for ns in ${NS[@]};
do oc get ns $ns;
   if [ $? -eq 0 ];
   then
      backupnamespaces=${backupnamespaces},$ns;
   fi
done



#Now in all namespaces we're going to backup we exclude the helm installed resources (to avoid double instances)
#TODO: check if label velero.io/exclude-from-backup=true already exist and eventually don't reset
IFS=',' read -ra NS <<< "$backupnamespaces"
for ns in ${NS[@]};
do oc get ns $ns;
   if [ $? -eq 0 ];
   then
       for item in $(oc get all -l 'helm.sh/chart' -n $ns -o jsonpath='{range .items[*]}{@.kind}/{@.metadata.name} {end}');
       do
	   oc label $item velero.io/exclude-from-backup=true -n $ns
       done
   fi
done




#Attach managed clusters... (TODO: check whether related namespace exist)
for namespace in $(oc get managedclusters -o jsonpath='{.items[*].metadata.name}'); do backupnamespaces=${backupnamespaces},${namespace}; done


wait_until "namespace_active velero"
if [[ $? != 0 ]]; then
    echo_yellow "Need to deploy velero"
    wait_until "deployment_up_and_running velero velero"
    deploy_velero  $BUCKET $REGION $s3credentials
fi




velero backup create backup-sre-to-acm-dario \
       --include-cluster-resources=false \
       --exclude-resources certificatesigningrequests \
       --include-namespaces ${backupnamespaces}

#Now we should remove labels
# TODO: dont remove labels if were already there
IFS=',' read -ra NS <<< "$backupnamespaces"
for ns in ${NS[@]};
do oc get ns $ns;
   if [ $? -eq 0 ];
   then
       for item in $(oc get all -l 'helm.sh/chart' -n $ns -o jsonpath='{range .items[*]}{@.kind}/{@.metadata.name} {end}');
       do
	    oc label $item velero.io/exclude-from-backup- -n $ns
       done
   fi
done
