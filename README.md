# sre-tools



This is one of the repository of RHACM SRE Squad. 

## The _one stop tool_ `sre-tools`

Ok, ok, name will change...

At the time of writing due to lack of inspiration (to find a better name) `sre-tools` is the _one stop tool_ in the repository. It's built using `ginkgo` and `gomega` abusing the `golang test` framework.

How to compile it:

If you work on Linux (though this is has been tested for `Fedora` only) we suggest you to follow `Kubernetes` convention, hence to clone this repository in  `${GOPATH}/src/github.com/open-cluster-manager` then with


```shell
$ cd ${GOPATH}/src/github.com/open-cluster-manager
$ make build
```

should build the tool. To run it 


```shell
 ./sre-tools --kubeconfig=$HOME/.kube/config
```

should be enough. This doc show the `out of cluster` mode but the tool will support an `in cluster` mode where we'll create a Container image to run `sre-tools` inside the cluster.

If you've followed the instruction in [open-cluster-management.io](https://open-cluster-management.io/) and you're sure you've ran

```shell
$kubectl config set-context kind-hub
```

the only (at the moment) test should pass since it currenty lists `managedclusters` looking for for `cluster1`.  More to come.