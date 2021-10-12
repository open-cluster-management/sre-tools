#!/bin/sh -e

# Automation for making an infrastructure machine set for SVT
# v 1.0

if [ -z "$2" ]; then
echo 'Version 1.0' 
echo 'Current cloud host platform support: AWS'
printf "\n"
echo 'Please note) This script is intended to be run on an existing cluster.'
echo '             Be sure you are already logged into your cluster before running.'
echo '-----------------------------------------------------------------------------'

echo 'To use: ./infra_node_runner.sh INFRASTRUCTURE_NODE_SET INSTANCE_TYPE'
printf "\n"
echo 'INFRASTRUCTURE_NODE_SET = Name you wish to make the infrastructure node label'
echo 'INSTANCE_TYPE = Instance type you wish the infrastructure nodes to be'
printf "\n"
exit 1
fi

#####################################################################
# Get the variables that must be supplied to the machine_set_outline
echo "Getting variables needed for machine_set_outline..."

workers=$(oc get machines -n openshift-machine-api -o custom-columns=:.metadata.name --no-headers | grep worker | base64 -w 0)
worker_a=$(echo $workers | base64 --decode | grep 2a)
worker_b=$(echo $workers | base64 --decode | grep 2b)
worker_c=$(echo $workers | base64 --decode | grep 2c)

worker_a_json=$(oc get machine $worker_a -n openshift-machine-api -ojson)
worker_b_json=$(oc get machine $worker_b -n openshift-machine-api -ojson)
worker_c_json=$(oc get machine $worker_c -n openshift-machine-api -ojson)

# Get infrastructure_set
infrastructure_set=$(echo $worker_a_json | jq -r '.metadata.labels["machine.openshift.io/cluster-api-cluster"]')

# Get infrastructure_ami
infrastructure_ami=$(echo $worker_a_json | jq -r '.spec.providerSpec.value.ami.id')

# Get infrastructure_node
infrastructure_node=$1

# Get instance_type
instance_type=$2

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