#/usr/bin/env bash



ROOTDIR=$(git rev-parse --show-toplevel)
source ${ROOTDIR}/backup-n-restore/hack/common.sh


oc cluster-info
if [[ $? != "0" ]]; then 
    echo "Please login to the cluster you want to backup"
    exit 1
fi


#Check velero presence. It checks only in velero

wait_until "namespace_active velero"
if [[ $? != 0 ]]; then
    echo_yellow "Need to deploy velero"
    wait_until "deployment_up_and_running velero velero"
    deploy_velero  $BUCKET $REGION $s3credentials
fi

exit




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


#Attach managed clusters, should we check whether namespace exist?
for namespace in $(oc get managedclusters -o jsonpath='{.items[*].metadata.name}'); do backupnamespaces=${backupnamespaces},${namespace}; done

velero backup create backup-sre-to-acm \
       --include-cluster-resources=false \
       --exclude-resources nodes,events,certificatesigningrequests \
       --include-namespaces ${backupnamespaces}


