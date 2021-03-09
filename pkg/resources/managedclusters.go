package resources

import (
	"context"

	_ "github.com/open-cluster-management/sre-tools/pkg/framework"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	"github.com/open-cluster-management/sre-tools/pkg/framework"
	v1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

var _ = Describe("To test resources per number of managed cluster", func() {

	Context("Initially", func() {
		It("has one cluster", func() {
			f, err := framework.NewFramework()
			Ω(err).ShouldNot(HaveOccurred())
			Ω(f).ShouldNot(BeNil())

			clusterClient, err := f.ClusterClient()
			Ω(err).ShouldNot(HaveOccurred())
			Ω(clusterClient).ShouldNot(BeNil())

			clusters, err := clusterClient.ClusterV1().ManagedClusters().List(context.TODO(), v1.ListOptions{})
			Ω(err).ShouldNot(HaveOccurred())
			Ω(clusters.Items).ShouldNot(BeEmpty())

			Ω(clusters.Items[0].GetObjectMeta().GetName()).Should(Equal("cluster1"))

		})
	})
})
