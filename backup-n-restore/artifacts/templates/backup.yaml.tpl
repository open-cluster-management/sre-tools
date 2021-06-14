apiVersion: velero.io/v1
kind: Backup
metadata:
  name: VELERO_BACKUP_NAME
  namespace: VELERO_NAMESPACE
spec:
  excludedResources:
  - certificatesigningrequests
  hooks: {}
  ttl: 720h0m0s
  includeClusterResources: false
 
