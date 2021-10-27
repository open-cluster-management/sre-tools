#!/bin/sh -e

# Automation for making an infrastructure machine set for SVT
# v 1.0.1

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
echo 'Version 1.0.1'
echo 'Current cloud host platform support: AWS'
printf "\n"
echo 'Please note) This script is intended to be run on an existing cluster.'
echo '             Be sure you are already logged into your cluster before running.'
echo '             This utility assumes you have a 3 master node and 3 worker node cluster.'
echo '-----------------------------------------------------------------------------'

echo 'To use: ./infra_node_runner.sh INFRASTRUCTURE_NODE_SET INSTANCE_TYPE AVAILABILITY_ZONE'
printf "\n"
echo 'INFRASTRUCTURE_NODE_SET = Name you wish to make the infrastructure node label'
echo 'INSTANCE_TYPE = AWS instance type you wish the infrastructure nodes to be, for example m5.xlarge'
echo 'AVAILABILITY_ZONE = AWS availability zone the existing worker nodes are in, for example us-east-1'
printf "\n"
exit 1
fi

# Get infrastructure_node
infrastructure_node=$1

# Get instance_type
instance_type=$2

# Get availability zone
availability_zone=$3


echo "\n\n"
echo "Node label: ${infrastructure_node}"
echo "AWS instance type: ${instance_type}"
echo "AWS availability zone: ${availability_zone}"
echo "\n\n"

#####################################################################
# Get the variables that must be supplied to the machine_set_outline
echo "Getting variables needed for machine_set_outline..."

# Check for which base64 command we have available so we can use the right option
set +e
echo | base64 -w 0 > /dev/null 2>&1
if [ $? -eq 0 ]; then
  # GNU coreutils base64, '-w' supported
  BASE64_W_OPTION=" -w 0"
else
  # Openssl base64, no wrapping by default
  BASE64_W_OPTION=" "
fi
set -e

workers=$(oc get machines -n openshift-machine-api -o custom-columns=:.metadata.name --no-headers | grep worker | base64 ${BASE64_W_OPTION})
worker_a=$(echo $workers | base64 --decode | grep ${availability_zone}a)
worker_b=$(echo $workers | base64 --decode | grep ${availability_zone}b)
worker_c=$(echo $workers | base64 --decode | grep ${availability_zone}c)

worker_a_json=$(oc get machine $worker_a -n openshift-machine-api -ojson)
worker_b_json=$(oc get machine $worker_b -n openshift-machine-api -ojson)
worker_c_json=$(oc get machine $worker_c -n openshift-machine-api -ojson)

# Get infrastructure_set
infrastructure_set=$(echo $worker_a_json | jq -r '.metadata.labels["machine.openshift.io/cluster-api-cluster"]')

# Get infrastructure_ami
infrastructure_ami=$(echo $worker_a_json | jq -r '.spec.providerSpec.value.ami.id')


# Get infrastructure_region
infrastructure_region=$(echo $worker_a_json | jq -r '.metadata.labels["machine.openshift.io/region"]')

# Get zone_a, zone_b, zone_c
zone_a=$(echo $worker_a_json | jq -r '.metadata.labels["machine.openshift.io/zone"]')
zone_b=$(echo $worker_b_json | jq -r '.metadata.labels["machine.openshift.io/zone"]')
zone_c=$(echo $worker_c_json | jq -r '.metadata.labels["machine.openshift.io/zone"]')

echo "... Variables retrieved!"

#####################################################################
# Set variables to machine_set_outline for infrastructure config
echo "Setting required values in machine_set_outline..."

# Create 3 machine_set yamls and set infrastructure_set in each of them
sed "s/<infrastructure_set>/${infrastructure_set}/g" machine_set_outline.yaml > machine_set_a.yaml
sed "s/<infrastructure_set>/${infrastructure_set}/g" machine_set_outline.yaml > machine_set_b.yaml
sed "s/<infrastructure_set>/${infrastructure_set}/g" machine_set_outline.yaml > machine_set_c.yaml

# Set infrastructure_ami
gsed -i "s/<infrastructure_ami>/${infrastructure_ami}/g" machine_set_a.yaml machine_set_b.yaml machine_set_c.yaml

# Set infrastructure_node
gsed -i "s/<infrastructure_node>/${infrastructure_node}/g" machine_set_a.yaml machine_set_b.yaml machine_set_c.yaml

# Set instance_type
gsed -i "s/<instance_type>/${instance_type}/g" machine_set_a.yaml machine_set_b.yaml machine_set_c.yaml

# Set infrastructure_region
gsed -i "s/<infrastructure_region>/${infrastructure_region}/g" machine_set_a.yaml machine_set_b.yaml machine_set_c.yaml

# Set zone_a, zone_b, zone_c
gsed -i "s/<zone>/${zone_a}/g" machine_set_a.yaml
gsed -i "s/<zone>/${zone_b}/g" machine_set_b.yaml
gsed -i "s/<zone>/${zone_c}/g" machine_set_c.yaml

echo "... Values set!"

#####################################################################
# Apply infrastructure yamls
echo "Applying MachineSet resources..."

oc apply -f machine_set_a.yaml
oc apply -f machine_set_b.yaml
oc apply -f machine_set_c.yaml

echo "... MachineSet resources applied!"

#####################################################################
echo 'Please allow time for your machines to come up. You may check their status in your cluster.'
