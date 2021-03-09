package main

import (
	"testing"

	_ "github.com/open-cluster-management/sre-tools/pkg/resources"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
)

// RunSRETools runs SRE tools
func RunSRETools(t *testing.T) {
	RegisterFailHandler(Fail)
	RunSpecs(t, "SRE tools Suite")
}
