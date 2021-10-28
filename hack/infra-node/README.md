# Instructions and tools for creating infra nodes on OpenShift and deploying ACM on those infra nodes

The info below is provided to assist in the setup of OpenShift so that
infra nodes will be used for ACM when it is installed.

This tooling currently only supports OpenShift running in AWS.

## Deploy OpenShift

Deploy OpenShift with 3 masters and 3 workers in AWS.

## Add infra nodes

Add 3 infra nodes using the `infra_node_runner.sh` script.

```shell
./infra_node_runner.sh myname-infra m5.xlarge us-east-1
```

## Move OpenShift workload to infra nodes
Move OpenShift pod workload to infra nodes using the `move-to-infra.sh` script.

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

TBD

Ensure there are no pods in pending state.
```shell
oc get pods -A | grep Pending
```
