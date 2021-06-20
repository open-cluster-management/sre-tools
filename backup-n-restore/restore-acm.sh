#!/usr/bin/env bash

#https://github.com/vmware-tanzu/velero-plugin-for-aws
#https://github.com/vmware-tanzu/velero-plugin-for-aws#option-1-set-permissions-with-an-iam-user


ROOTDIR=$(git rev-parse --show-toplevel)
source ${ROOTDIR}/backup-n-restore/hack/common.sh


BUCKET=${DEFAULT_BUCKET}
REGION=${DEFAULT_S3REGION}
DETACH=false

################################################################################
# Help: displays usage
################################################################################
Help()
{
 # Display Help
 echo "$0 restores ACM backup in a new hub "
 echo
 echo "Syntax: restore-acm [ -b|c|d|h|n|p|s ]" 
 echo "options:"
 echo "-b <bucket name> Specify the bucket name. Default: ${BUCKET}"
 echo "-c <credential file path> Credential file path. No default."
 echo "-d detach from source HUB. Sourcce HUB kubeconfig or source kubecontext must be supplied"
 echo "-h Print this help."
 echo "-n <backup name> Specify the name of the backup, No default: if no name is give, it will  be automatically selected from region and bucket"
 echo "-r <region name> Specify the region name ${REGION}"
 echo "-s <source HUB>. Source HUB kubeconfig file path or Source HUB context name. Mandatory if detach is demanded"
 echo
}

###############################################################
# Main program                                                #
###############################################################
while getopts "b:c:dhn:r:s:" arg; do
 case $arg in
     b) BUCKET=${OPTARG}
	;;
     c) CREDENTIALFILEPATH=${OPTARG}
	;;
     d) DETACH=true
	;;
     h) Help
	exit
	;;
     n) BACKUPNAME=${OPTARG}
        ;;
     r) REGION=${OPTARG}
	;;
     s) SOURCEHUB=${OPTARG}
	;;
     *)
         Help
	 exit
         ;;
 esac
done
shift $((OPTIND-1))

#check detach and SOURCEHUB
if [ "${DETACH}" == "true" ];
then
    if 
	[ -z ${SOURCEHUB} ];
    then
	echo
	echo_red "Cannot find source HUB Kubeconfig file path or context name. Cannot continue.";
	Help;
	exit 1;
    fi
    oc $(kconfig_or_kcontext ${SOURCEHUB}) cluster-info
    if [[ $? != "0" ]]; then 
	echo_red "Unable to login to HUB with ${SOURCEHUB}. Please double check it. Cannot continue."
	exit 1
    fi
fi

oc cluster-info
if [[ $? != "0" ]]; then 
    echo_red "Please login to the cluster you want to restore"
    exit 1
fi


[  -z $BUCKET  ] && { echo_red "No velero bucket found. Cannot continue."; echo; Help; exit 1; }
echo_green "Velero bucket $BUCKET"

[  -z $REGION  ] && { echo_red "No velero region found. Cannot continue."; echo; Help; exit 1; }
echo_green "Velero region $REGION"


# Check whether mch exist
oc get mch -A
if [[ $? != "0" ]]; then 
    echo_red "Cannot find ACM. Cannot continue"
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
    echo_yellow "Need to deploy velero"
    [  -z $CREDENTIALFILEPATH  ] && { echo_red "No credential file give. Cannot continue."; echo; Help; exit 1; }
    [ ! -f $CREDENTIALFILEPATH ] && { echo_red "Cannot find file $CREDENTIALFILEPATH, Cannot continue"; echo; Help; exit 1; }
    deploy_velero  $BUCKET $REGION $CREDENTIALFILEPATH
    sleep 10
fi



# Here velero should be up and running
wait_until "deployment_up_and_running velero velero" 10 300


# Wait until any backups is available
wait_until "backups_available velero" 5 60

if [ -z "${BACKUPNAME}" ];
then #Get most recent backup.
    echo_yellow "Missing backup name... Selecting the most recent without errors"
    completedBackups=$(oc get backups -n velero --sort-by=.status.startTimestamp  -o jsonpath='{.items[?(@.status.phase=="Completed")].metadata.name}')
    BACKUPNAME=${completedBackups##*' '}
fi

[  -z $BACKUPNAME  ] && { echo_red "No backup found. Cannot continue."; echo; Help; exit 1; }
echo_green "Backup selected ${BACKUPNAME}"


RESTORENAME=acm-restore-$(date -u +"%Y-%m-%d-%H%M%S")
echo_yellow "Restoring...${BACKUPANME} through ${RESTORENAME}"
cat ${ROOTDIR}/backup-n-restore/artifacts/templates/restore.yaml.tpl | \
    sed "s/VELERO_RESTORE_NAME/${RESTORENAME}/" | \
    sed "s/VELERO_NAMESPACE/velero/" | \
    sed "s/VELERO_BACKUP_NAME/${BACKUPNAME}/" | \
    oc apply -f - > /dev/null 2>&1

wait_until "restore_finished velero ${RESTORENAME}" 10 600


#It iterates on managed cluster namespaces via label selector
register_managed_clusters

#TODO: check managed cluster registered...

#It iterates on managed cluster namespaces via lable selector
accepts_managed_clusters
#TODO: check managed clsuters managed


if [ "${DETACH}" == "true" ];
then # Detach cluster
    oc $(kconfig_or_kcontext ${SOURCEHUB}) scale deployment managedcluster-import-controller --replicas=0 -n open-cluster-management
    wait_until "deployment_scaled_to_zero ${SOURCEHUB} open-cluster-management managedcluster-import-controller" 10 300
    
    if [ $? -eq 0 ];
    then
	detach_clusters  ${SOURCEHUB}
	if [ $? -eq 0 ];
	then
	    echo_red "Couldn't detach cluster"
	fi
    else
	echo_red "Unable to scale deployment managedcluster-import-controller: Cannot detach managed clusters"	
    fi
fi
