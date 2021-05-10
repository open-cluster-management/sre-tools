#!/usr/bin/env bash

set -x

#https://github.com/vmware-tanzu/velero-plugin-for-aws
#https://github.com/vmware-tanzu/velero-plugin-for-aws#option-1-set-permissions-with-an-iam-user


ROOTDIR=$(git rev-parse --show-toplevel)
source ${ROOTDIR}/backup-n-restore/hack/common.sh


BUCKET=${DEFAULT_BUCKET}
REGION=${DEFAULT_S3REGION}

################################################################################
# Help: displays usage
################################################################################
Help()
{
 # Display Help
 echo "$0 deploys OCM hub "
 echo
 echo "Syntax: restore-acm [ -h|n|p ]" 
 echo "options:"
 echo "-b <bucket name> Specify the bucket name. Default: ${BUCKET}"
 echo "-c <credential file path> Credential file path. No default."
 echo "-h Print this help."
 echo "-n <backup name> Specify the name of the backup, No default: if no name is give, it will  be automatically selected from region and bucket"
 echo "-r <region name> Specify the region name ${REGION}"
 echo
}

###############################################################
# Main program                                                #
###############################################################
while getopts "b:c:hn:r:" arg; do
 case $arg in
     b) BUCKET=${OPTARG}
	;;
     c) CREDENTIALFILEPATH=${OPTARG}
	;;
     h) # display Usage
	 Help
	 exit
	 ;;
     n) BACKUPNAME=${OPTARG}
        ;;
     r) REGION=${OPTARG}
	;;
     *)
         Help
	 exit
         ;;
 esac
done
shift $((OPTIND-1))

oc cluster-info
if [[ $? != "0" ]]; then 
    echo "Please login to the cluster you want to backup"
    exit 1
fi


[  -z $CREDENTIALFILEPATH  ] && { echo_red "No credential file give. Cannot continue."; echo; Help; exit 1; }
[ ! -f $CREDENTIALFILEPATH ] && { echo_red "Cannot find file $CREDENTIALFILEPATH, Cannot continue"; echo; Help; exit 1; }

[  -z $BUCKET  ] && { echo_red "No velero bucket found. Cannot continue."; echo; Help; exit 1; }
echo_green "Velero bucket $BUCKET"

[  -z $REGION  ] && { echo_red "No velero region found. Cannot continue."; echo; Help; exit 1; }
echo_green "Velero region $REGION"


# Check whether mch exist
oc get mch -A
if [[ $? != "0" ]]; then 
    echo_red "Install ACM before restoring managed clusters and configurations."
    exit 1
fi


# Check whether installation is empty
for mc in $(oc get managedclusters -o jsonpath='{.items[*].metadata.name}');
do if [ $mc == "local-cluster" ];
   then
       continue
   fi
   echo_red "ACM has already managed clusters: $mc"
   exit
done


wait_until "namespace_active velero" 1 5
if [[ $? != 0 ]]; then
    echo_yellow "Need to deploy velero"=
    deploy_velero  $BUCKET $REGION $CREDENTIALFILEPATH
    sleep 10
fi


# Here velero should be up and running
wait_until "deployment_up_and_running velero velero" 1 30

if [ -z "${BACKUPNAME}" ];
then #Get most recent backup.
    echo_yellow "Missing backup name... Selecting the most recent without errors"
    completedBackups=$(oc get backups -n velero --sort-by=.status.startTimestamp  -o jsonpath='{.items[?(@.status.phase=="Completed")].metadata.name}')
    BACKUPNAME=${completedBackups##*' '}
fi

[  -z $BACKUPNAME  ] && { echo_red "No backup found. Cannot continue."; echo; Help; exit 1; }
echo_green "Backup selected ${BACKUPNAME}"



RESTORENAME=acm-restore-$(date +"%Y-%m-%d%H-%M-%S")
cat ${ROOTDIR}/backup-n-restore/artifacts/templates/restore.yaml.tpl | \
    sed "s/VELERO_RESTORE_NAME/${RESTORENAME}/" | \
    sed "s/VELERO_NAMESPACE/velero/" | \
    sed "s/VELERO_BACKUP_NAME/${BACKUPNAME}/" | \
    oc apply -f - > /dev/null 2>&1

echo_green "Restore Created: $RESTORENAME" 
wait_until "restore_finished velero ${RESTORENAME}" 5 300

newhubkubeconfig=$(mktemp)
oc config view --flatten > ${newhubkubeconfig}
for n in $(oc get ns -lcluster.open-cluster-management.io/managedCluster -o jsonpath='{.items[*].metadata.name}');
do managed_kubeconfig_secret=$(oc get secret -o name -n $n | grep admin-kubeconfig);
   if [ -z "${managed_kubeconfig_secret}" ]; then #this will skip local-cluster as well
      continue
   fi

   managedclusterkubeconfig=$(mktemp)
   oc get $managed_kubeconfig_secret -n $n  -o jsonpath={.data.kubeconfig} | base64 -d > $managedclusterkubeconfig

   #Deleting the bootstrap-hu-kubeconfig
   oc --kubeconfig=$managedclusterkubeconfig delete secret bootstrap-hub-kubeconfig -n open-cluster-management-agent --wait=true

   #Recreating boostrap-hub-kubeconfig
   oc --kubeconfig=$managedclusterkubeconfig create secret generic bootstrap-hub-kubeconfig --from-file=kubeconfig="${newhubkubeconfig}" -n open-cluster-management-agent

done

rm -rf ${newhubkubeconfig}


