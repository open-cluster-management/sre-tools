#/usr/bin/env bash

ROOTDIR=$(git rev-parse --show-toplevel)
source ${ROOTDIR}/backup-n-restore/hack/common.sh

BUCKET=${DEFAULT_BUCKET}
REGION=${DEFAULT_S3REGION}

dateformat="%Y-%m-%d-%H%M%S"
################################################################################
# Help: displays usage
################################################################################
Help()
{
 # Display Help
 echo "$0 backup ACM HUB"
 echo
 echo "Syntax: backup-acm [ -b|c|h|n|r ]" 
 echo "options:"
 echo "-b <bucket name> Specify the bucket name. Default: ${BUCKET}"
 echo "-c <credential file path> Credential file path. No default."
 echo "-h Print this help."
 echo "-n <backup name> Specify the name of the backup, No default. If you don't specify a name the backup name will be acm-backup-${USER}-<date -u ${dateformat}>"
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


# Check whether mch exist
oc get mch -A
if [[ $? != "0" ]]; then 
    echo_red "Cannot find ACM. Cannot continue"
    exit 1
fi


backupnamespaces=open-cluster-management-agent,open-cluster-management-agent-addon,hive,openshift-operator-lifecycle-manager
#Add managedclusters
howmanymanaged=0
for mc in $(oc get managedclusters -o jsonpath='{.items[*].metadata.name}');
do
    if [ $mc  == "local-cluster" ];
    then
	echo_yellow "Skipping $mc";
	continue
    fi
    oc get ns $mc # check whether managedcluster namespace exists
    if [ $? -ne 0 ];
    then
       echo_yellow "No namespace for managedcluster resource, skipping cluster $mc"
       continue
    fi
    #Register annotation on namespace managedcluster
    oc annotate --overwrite ns $mc open-cluster-management.io/srchubacceptsclient=$(oc get managedcluster $mc -o jsonpath='{.spec.hubAcceptsClient}')
    let howmanymanaged+=1
    backupnamespaces=${backupnamespaces},${mc};
done

####################################################################
# Stop in case there's no managed clusters  (skiping local-cluster)
####################################################################
if [ $howmanymanaged -eq 0 ]
then
    echo_red "Couldn't find managed cluster... Cannot continue"
    exit
fi


backupmanifestfile=$(mktemp)
cp ${ROOTDIR}/backup-n-restore/artifacts/templates/backup.yaml.tpl $backupmanifestfile
echo_yellow "Created $backupmanifestfile as temporary manifest file for backup"
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "  includedNamespaces:" >> $backupmanifestfile
else
    echo -e "  includedNamespaces:" >> $backupmanifestfile
fi
# Add labels velero/exclude-from-backup 
# TODO: check if label velero.io/exclude-from-backup=true already exist and eventually don't reset.
#       If the TDDO is implemented no multiple script can run at the same time
IFS=',' read -ra NS <<< "$backupnamespaces"
for ns in ${NS[@]};
do oc get ns $ns;
   if [ $? -eq 0 ];
   then
       for item in $(oc get all -l 'helm.sh/chart' -n $ns -o jsonpath='{range .items[*]}{@.kind}/{@.metadata.name} {end}');
       do
	   oc label $item velero.io/exclude-from-backup=true -n $ns
       done
       if [[ "$OSTYPE" == "darwin"* ]]; then
           echo "  - $ns" >> $backupmanifestfile
       else
           echo -e "  - $ns" >> $backupmanifestfile
       fi
   fi
done

if [[ $(namespace_active velero) != 0 ]]; then
    echo_yellow "Need to deploy velero"
    [  -z $CREDENTIALFILEPATH  ] && { echo_red "No credential file give. Cannot continue."; echo; Help; exit 1; }
    [ ! -f $CREDENTIALFILEPATH ] && { echo_red "Cannot find file $CREDENTIALFILEPATH, Cannot continue"; echo; Help; exit 1; }
    deploy_velero  $BUCKET $REGION $CREDENTIALFILEPATH
    wait_until "deployment_up_and_running velero velero"    
else
    echo_green "velero detected"
fi


if [ -z "${BACKUPNAME}" ]; then
    BACKUPNAME=acm-backup-${USER}-$(date -u +"${dateformat}")     
fi


##########################
# Performing real backup #
##########################
cat  $backupmanifestfile | \
    sed "s/VELERO_NAMESPACE/velero/" | \
    sed "s/VELERO_BACKUP_NAME/${BACKUPNAME}/" | \
    oc apply -f -  

if [ $? -ne 0 ]
then
    echo_red "Backup ${BACKUPNAME} couldn't start... Can't continue"
    exit
fi

wait_until "backup_finished velero ${BACKUPNAME}" 10 600 

###################
# Removing labels #
###################
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

####################
# Remove annotations
####################
for mc in $(oc get managedclusters -o jsonpath='{.items[*].metadata.name}');
do
    if [ $mc  == "local-cluster" ];
    then
	echo_yellow "Skipping $mc";
	continue
    fi
    oc get ns $mc # check whether managedcluster namespace exists
    if [ $? -ne 0 ];
    then
       echo_yellow "No namespace for managedcluster resource, skipping cluster $mc"
       continue
    fi
    #Remove annotation on namespace managedcluster
    oc annotate ns $mc open-cluster-management.io/srchubacceptsclient-
done


