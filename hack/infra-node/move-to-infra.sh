#!/bin/bash

# Assuming we created a cluster with worker nodes, and then added some infra nodes,
# do the things that move OCP stuff from worker to infra nodes.
#
#
# NOTE: This script requires utility yq that supports the -c option.  See https://kislyuk.github.io/yq/
# pip3 install yq
# OR
# Mac: brew install python-yq
# Using the yq from "brew install yq" will not work!
#
# This is based on OCP 4.7 doc and other experimentation.
#
# OCP 4.7 doc: https://docs.openshift.com/container-platform/4.7/machine_management/creating-infrastructure-machinesets.html#moving-resources-to-infrastructure-machinesets
#
# NB: THis script is still verry crappy, eg:  No error checking.
#
# Blame: @joeg-pro

if [ -z "$1" ] ; then
echo "To use: ./move-to-infra.sh INFRASTRUCTURE_NODE"
printf "\n"
echo 'INFRASTRUCTURE_NODE = Name you wish to make the infrastructure node label'
printf "\n"
exit 1
fi

# Get infrastructure_node
INFRASTRUCTURE_NODE=$1


tmp_file="./tmp.file"

# Common fragments:

nodeselector=$(cat <<EOF | yq -c .
node-role.kubernetes.io/infra: "${INFRASTRUCTURE_NODE}"
EOF
)

tolerations=$(cat <<EOF | yq -c .
- key: node-role.kubernetes.io/infra
  effect: NoSchedule
  operator: Exists
EOF
)

# Ingress Controller:

# Add nodeselectors/tolerations to the "defual"t IngressController resource, under
# spec.nodePlacement which we assume doesn't exist in the spec yet.

nodePlacement=$(cat <<EOF | yq -c .
nodeSelector:
  matchLabels: $nodeselector
tolerations: $tolerations
EOF
)

patch=$(cat <<EOF | jq -c .
[
  {"op": "add",
   "path": "/spec/nodePlacement",
   "value": $nodePlacement
  }
]
EOF
)

oc -n openshift-ingress-operator patch IngressController default  --type="json" -p "$patch"

# In-Cluster Image Registry:
#
# Add nodeselector/tolerations to the "cluster" ImageRegistry "Config" resource, as
# top level keys under spec.  We assume neither exists already.

nodeselector=$(cat <<EOF | yq -c .
node-role.kubernetes.io/infra: "${INFRASTRUCTURE_NODE}"
EOF
)

tolerations=$(cat <<EOF | yq -c .
- key: node-role.kubernetes.io/infra
  effect: NoSchedule
  operator: Exists
EOF
)

patch=$(cat <<EOF
[
  {"op": "add",
   "path": "/spec/nodeSelector",
   "value": $nodeselector
  },
  {"op": "add",
   "path": "/spec/tolerations",
   "value": $tolerations
  }
]
EOF
)

oc patch configs.imageregistry.operator.openshift.io cluster --type="json" -p "$patch"

# Monitoring stack.

# Monitoring is configured by a ConfigMap (IMHO, crappy approach).  By ConfigMap in question
# is not created by default, so we'll just create one that targets all monitoring components
# to infra nodes.

cat <<EOF > $tmp_file
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |+
    alertmanagerMain:
      nodeSelector:
        node-role.kubernetes.io/infra: "${INFRASTRUCTURE_NODE}"
      tolerations:
      - key: node-role.kubernetes.io/infra
        effect: NoSchedule
        operator: Exists
    prometheusK8s:
      nodeSelector:
        node-role.kubernetes.io/infra: "${INFRASTRUCTURE_NODE}"
      tolerations:
      - key: node-role.kubernetes.io/infra
        effect: NoSchedule
        operator: Exists
    prometheusOperator:
      nodeSelector:
        node-role.kubernetes.io/infra: "${INFRASTRUCTURE_NODE}"
      tolerations:
      - key: node-role.kubernetes.io/infra
        effect: NoSchedule
        operator: Exists
    grafana:
      nodeSelector:
        node-role.kubernetes.io/infra: "${INFRASTRUCTURE_NODE}"
      tolerations:
      - key: node-role.kubernetes.io/infra
        effect: NoSchedule
        operator: Exists
    k8sPrometheusAdapter:
      nodeSelector:
        node-role.kubernetes.io/infra: "${INFRASTRUCTURE_NODE}"
      tolerations:
      - key: node-role.kubernetes.io/infra
        effect: NoSchedule
        operator: Exists
    kubeStateMetrics:
      nodeSelector:
        node-role.kubernetes.io/infra: "${INFRASTRUCTURE_NODE}"
      tolerations:
      - key: node-role.kubernetes.io/infra
        effect: NoSchedule
        operator: Exists
    telemeterClient:
      nodeSelector:
        node-role.kubernetes.io/infra: "${INFRASTRUCTURE_NODE}"
      tolerations:
      - key: node-role.kubernetes.io/infra
        effect: NoSchedule
        operator: Exists
    openshiftStateMetrics:
      nodeSelector:
        node-role.kubernetes.io/infra: "${INFRASTRUCTURE_NODE}"
      tolerations:
      - key: node-role.kubernetes.io/infra
        effect: NoSchedule
        operator: Exists
    thanosQuerier:
      nodeSelector:
        node-role.kubernetes.io/infra: "${INFRASTRUCTURE_NODE}"
      tolerations:
      - key: node-role.kubernetes.io/infra
        effect: NoSchedule
        operator: Exists
EOF

oc apply -f $tmp_file
rm -f $tmp_file

# Logging:

# Assume logging not installed, so nothing to do.

# Still to deal with:
# - openshift marketplace pods
# - openshift-kube-storage-version-migrator pod
