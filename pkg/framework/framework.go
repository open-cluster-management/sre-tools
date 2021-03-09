package framework

import (
	"fmt"

	//. "github.com/onsi/gomega"

	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"

	clusterclient "github.com/open-cluster-management/api/client/cluster/clientset/versioned"
)

// Framework stores what it is needed to interact with the clusters
type Framework struct {
	hubConfig *rest.Config
}

func initKubeConfig() (*rest.Config, error) {
	if len(KubeConfigFilePath) > 0 {
		return clientcmd.BuildConfigFromFlags("", KubeConfigFilePath) // out of cluster config
	}
	return rest.InClusterConfig()
}

// NewFramework initializes a test framework
func NewFramework() (*Framework, error) {
	f := &Framework{}
	c, err := initKubeConfig()
	if err != nil {
		return nil, fmt.Errorf("unable to initialize KubeConfig: %v", err)
	}
	f.hubConfig = c
	return f, nil
}

// KubeClient builds, intializes and returns a native Kubernetes resources client
func (f *Framework) KubeClient() (*kubernetes.Clientset, error) {
	return kubernetes.NewForConfig(f.hubConfig)
}

// ClusterClient builds, initializes and returns  clusterClient
func (f *Framework) ClusterClient() (*clusterclient.Clientset, error) {
	return clusterclient.NewForConfig(f.hubConfig)
}
