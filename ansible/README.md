# Ansible Playbooks

## Setup Ansible

## Usage

Set your kube context

```bash
# source your kube context in your environment
export KUBECONFIG=<path>
# verify that your context is pointing to the expected cluster
oc cluster-info
```

Run the Ansible playbooks

```
cd ansible

# setups up LetsEncrypt signed certifricate
ansible-playbook playbook/playbook-acmesh.yml

# install working group-sync operator
ansible-playbook playbook/playbook-group-sync.yml

# install rhacm operator via kustomize
ansible-playbook playbook/playbook-operator-rhacm-operator.yml
```
