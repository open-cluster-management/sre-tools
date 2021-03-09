package main

import (
	goflag "flag"
	"os"
	"testing"

	"github.com/open-cluster-management/sre-tools/pkg/framework"

	"github.com/spf13/pflag"
)

func TestE2E(t *testing.T) {
	RunSRETools(t)
}

func TestMain(m *testing.M) {

	pflag.StringVar(&framework.KubeConfigFilePath, "kubeconfig", "", "HUB Kubeconfig filepath")
	pflag.CommandLine.AddGoFlagSet(goflag.CommandLine) // to include ginkgo and go test flags
	pflag.Parse()
	goflag.CommandLine.Parse([]string{})

	os.Exit(m.Run())
}
