apiVersion: velero.io/v1
kind: Restore
metadata:
  name: VELERO_RESTORE_NAME
  namespace: VELERO_NAMESPACE
spec:
  backupName: VELERO_BACKUP_NAME
  hooks: {}
  includedNamespaces:
  - '*'

