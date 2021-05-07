#!/usr/bin/env bash


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


#TODO
#1) checks credentials 
#2) check BUCKET
#3) check region


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
done


	  
#wait_until "namespace_active velero" #this check only velero namespace :(
if [[ $? != 0 ]]; then
    echo_yellow "Need to deploy velero"=
    deploy_velero  $BUCKET $REGION $CREDENTIALFILEPATH
    wait_until "deployment_up_and_running velero velero"
fi

if [ -z "${BACKUPNAME}" ];
then #Get most recent backup. TODO: selects only 0 errors backup
    echo_yellow "Missing backup name... Selecting one"
    completedBackups=$(oc get backups -n velero --sort-by=.status.startTimestamp  -o jsonpath='{.items[?(@.status.phase=="Completed")].metadata.name}')
    BACKUPNAME=${completedBackups##*' '}
fi


if  [ -z "${BACKUPNAME}" ]
then
    echo_red "Unable to select backup..."
    exit 1
else
    echo_green "Backup selected ${BACKUPNAME}"
fi

velero restore create --from-backup ${BACKUPNAME}
#TODO wait unti restore complete



newhubkubeconfig=$(mktemp)
oc config view --flatten > ${newhubkubeconfig}
for n in $(oc get ns -lcluster.open-cluster-management.io/managedCluster -o jsonpath='{.items[*].metadata.name}');
do managed_kubeconfig_secret=$(oc get secret -o name -n $n | grep admin-kubeconfig);
   if [ -z "${managed_kubeconfig_secret}" ]; then #this will skip local-cluster as well
      continue
   fi

   managedclusterkubeconfig=$(mktemp)
   #Get the secret for the managed cluster $n
   oc get $managed_kubeconfig_secret -n $n  -o jsonpath={.data.kubeconfig} | base64 -d > $managedclusterkubeconfig

   # Remove deployment
   oc --kubeconfig=$managedclusterkubeconfig delete deployment klusterlet  -n open-cluster-management-agent --wait=true      
   echo_green "Klusterlet deleted for cluster $n"
   
   #Now import the cluster:
   # 1 get the original import secret
   oc get secret  $n-import -n $n -o jsonpath={.data.import\\.yaml} | base64 -d  > $n-import-old.yaml
   # 2 patch it with the new kubeconfig
   cat $n-import-old.yaml | \
       sed "s/  kubeconfig: .*$/  kubeconfig: $(cat ${newhubkubeconfig} | base64 -w 0)/" |  \
       oc --kubeconfig=$managedclusterkubeconfig apply -f -
   
   echo_green "Cluster $n imported"
   rm -rf $managedclusterkubeconfig
done

rm -rf ${newhubkubeconfig}
