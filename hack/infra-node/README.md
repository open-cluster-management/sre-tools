# Instructions and tools for creating infra nodes on OpenShift and deploying ACM on those infra nodes

The info below is provided to assist in the setup of OpenShift so that
infra nodes will be used for ACM when it is installed.

The instructions and tooling currently only support OpenShift running in AWS.

## Deploy OpenShift

Deploy OpenShift with 3 masters and 3 workers in AWS.

## Add infra nodes

Add 3 infra nodes using the `infra_node_runner.sh` script.

```shell
./infra_node_runner.sh myname-infra m5.xlarge us-east-1
```

## Move OpenShift workload to infra nodes
Move OpenShift pod workload to infra nodes using the `move-to-infra.sh` script.  This is based on https://docs.openshift.com/container-platform/4.8/machine_management/creating-infrastructure-machinesets.html#moving-resources-to-infrastructure-machinesets

```shell
./move-to-infra.sh cahl-infra myname-infra
```

Ensure there are no pods in pending state.
```shell
oc get pods -A | grep Pending
```

## Disable scheduling on worker nodes

Find the nodes with a role of `worker` (ignore nodes with a role of `infra,worker`)
```shell
oc get nodes
```

For every worker node, cordon it so no more pods will be scheduled on them.
```shell
kubectl cordon  <node name>
```


## Install ACM on the infra nodes

A modification will need to be done to TBD in order to ACM to install on the infra nodes

TBD.  Still need more investigation to get this to work with https://github.com/open-cluster-management/deploy/blob/master/start.sh and not have pods hanging in Pending state
because no vanilla worker nodes are available.  

TODO

Ensure there are no pods in pending state.
```shell
oc get pods -A | grep Pending
```

## Make sure everything works!

Run your tests.
