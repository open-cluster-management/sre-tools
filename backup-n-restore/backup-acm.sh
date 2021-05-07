#/usr/bin/env bash

ROOTDIR=$(git rev-parse --show-toplevel)
source ${ROOTDIR}/backup-n-restore/hack/common.sh


BUCKET=${DEFAULT_BUCKET}
REGION=${DEFAULT_S3REGION}
dateformat="%Y-%m-%dT%H:%M:%SZ"

################################################################################
# Help: displays usage
################################################################################
Help()
{
 # Display Help
 echo "$0 deploys OCM hub "
 echo
 echo "Syntax: backup-acm [ -h|n|p ]" 
 echo "options:"
 echo "-b <bucket name> Specify the bucket name. Default: ${BUCKET}"
 echo "-c <credential file path> Credential file path. No default."
 echo "-h Print this help."
 echo "-n <backup name> Specify the name of the backup, No default. If you don't specify a name the backup name will be acm-backup-${USER}-<date ${dateformat}>"
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


#Optional namespaces
others=open-cluster-management-agent,open-cluster-management-agent-addon

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
for namespace in $(oc get managedclusters -o jsonpath='{.items[*].metadata.name}');
do  backupnamespaces=${backupnamespaces},${namespace};
done


wait_until "namespace_active velero"
if [[ $? != 0 ]]; then
    echo_yellow "Need to deploy velero"
    wait_until "deployment_up_and_running velero velero"
    deploy_velero  $BUCKET $REGION $CREDENTIALFILEPATH
fi



if [ -z "${BACKUPNAME}" ]; then
    BACKUPNAME=acm-backup-${USER}-$(date +"${dateformat}")     
fi

   
velero backup create "${BACKUPNAME}" \
       --include-cluster-resources=false \
       --exclude-resources certificatesigningrequests \
       --include-namespaces ${backupnamespaces}

wait_until "backup_finished velero ${BACKUPNAME}"


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
