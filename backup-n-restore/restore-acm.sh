#!/usr/bin/env bash


#https://github.com/vmware-tanzu/velero-plugin-for-aws
#https://github.com/vmware-tanzu/velero-plugin-for-aws#option-1-set-permissions-with-an-iam-user


ROOTDIR=$(git rev-parse --show-toplevel)

source ${ROOTDIR}/backup-n-restore/hack/common.sh

BUCKET=velero-backup-acm
REGION=us-east-1


oc cluster-info
if [[ $? != "0" ]]; then 
    echo "Please login to the cluster you want to backup"
    exit 1
fi


#TODO
#1) checks credentials 
#2) check BUCKET
#3) check region
#4) check if mch exist
#5) chec if no managedclusters (through labels)

exit


s3credentials=awss3/awss3.credentials
wait_until "namespace_active velero" #this check only velero namespace :(
if [[ $? != 0 ]]; then
    echo_yellow "Need to deploy velero"
    wait_until "deployment_up_and_running velero velero"
    deploy_velero  $BUCKET $REGION $s3credentials
fi


velero backup get


velero restore create --from-backup backup-sre-to-acm

#TODO wait unti restore complete


newhubkubeconfig=$(mktemp)
oc config view --flatten > ${newhubkubeconfig}

for n in $(oc get ns -lcluster.open-cluster-management.io/managedCluster -o jsonpath='{.items[*].metadata.name}');
do managed_kubeconfig_secret=$(oc get secret -o name -n $n | grep admin-kubeconfig);
   if [ -z "${managed_kubeconfig_secret}" ]; then #this will skip local-cluster as well
      continue
   fi
   oc get $managed_kubeconfig_secret -n $n  -o jsonpath={.data.kubeconfig} | base64 -d > $n-kubeconfig
  
   oc --kubeconfig=$n-kubeconfig delete deployment klusterlet  -n open-cluster-management-agent 
   #TODO wait until kubelet not found
   sleep 10
   
   oc --kubeconfig=$n-kubeconfig delete secret hub-kubeconfig-secret -n open-cluster-management-agent
   # TODO: remove sleep 
   sleep 10
   
   #Now import the cluster
   oc get secret  $n-import -n $n -o jsonpath={.data.import\\.yaml} | base64 -d | oc --kubeconfig=$n-kubeconfig apply -f -


   
done


