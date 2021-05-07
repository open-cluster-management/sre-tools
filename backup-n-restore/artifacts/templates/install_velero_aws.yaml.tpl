apiVersion: v1
items:
- apiVersion: v1
  kind: Namespace
  metadata:
    creationTimestamp: null
    labels:
      component: velero
    name: velero
  spec: {}
- apiVersion: rbac.authorization.k8s.io/v1beta1
  kind: ClusterRoleBinding
  metadata:
    creationTimestamp: null
    labels:
      component: velero
    name: velero
  roleRef:
    apiGroup: rbac.authorization.k8s.io
    kind: ClusterRole
    name: cluster-admin
  subjects:
  - kind: ServiceAccount
    name: velero
    namespace: velero
- apiVersion: v1
  kind: ServiceAccount
  metadata:
    creationTimestamp: null
    labels:
      component: velero
    name: velero
    namespace: velero
- apiVersion: v1
  data:
    cloud: S3CREDENTIALS
  kind: Secret
  metadata:
    creationTimestamp: null
    labels:
      component: velero
    name: cloud-credentials
    namespace: velero
  type: Opaque
- apiVersion: velero.io/v1
  kind: BackupStorageLocation
  metadata:
    creationTimestamp: null
    labels:
      component: velero
    name: default
    namespace: velero
  spec:
    config:
      region: BACKUPSTORAGELOCATIONREGION
    default: true
    objectStorage:
      bucket: BUCKET
    provider: aws
- apiVersion: velero.io/v1
  kind: VolumeSnapshotLocation
  metadata:
    creationTimestamp: null
    labels:
      component: velero
    name: default
    namespace: velero
  spec:
    config:
      region: VOLUMESNAPSHOTLOCATIONREGION
    provider: aws
- apiVersion: apps/v1
  kind: Deployment
  metadata:
    creationTimestamp: null
    labels:
      component: velero
    name: velero
    namespace: velero
  spec:
    selector:
      matchLabels:
        deploy: velero
    strategy: {}
    template:
      metadata:
        annotations:
          prometheus.io/path: /metrics
          prometheus.io/port: "8085"
          prometheus.io/scrape: "true"
        creationTimestamp: null
        labels:
          component: velero
          deploy: velero
      spec:
        containers:
        - args:
          - server
          - --features=
          command:
          - /velero
          env:
          - name: VELERO_SCRATCH_DIR
            value: /scratch
          - name: VELERO_NAMESPACE
            valueFrom:
              fieldRef:
                fieldPath: metadata.namespace
          - name: LD_LIBRARY_PATH
            value: /plugins
          - name: GOOGLE_APPLICATION_CREDENTIALS
            value: /credentials/cloud
          - name: AWS_SHARED_CREDENTIALS_FILE
            value: /credentials/cloud
          - name: AZURE_CREDENTIALS_FILE
            value: /credentials/cloud
          - name: ALIBABA_CLOUD_CREDENTIALS_FILE
            value: /credentials/cloud
          image: velero/velero:v1.6.0-rc.2
          imagePullPolicy: IfNotPresent
          name: velero
          ports:
          - containerPort: 8085
            name: metrics
          resources:
            limits:
              cpu: "1"
              memory: 512Mi
            requests:
              cpu: 500m
              memory: 128Mi
          volumeMounts:
          - mountPath: /plugins
            name: plugins
          - mountPath: /scratch
            name: scratch
          - mountPath: /credentials
            name: cloud-credentials
        initContainers:
        - image: velero/velero-plugin-for-aws:v1.2.0
          imagePullPolicy: IfNotPresent
          name: velero-velero-plugin-for-aws
          resources: {}
          volumeMounts:
          - mountPath: /target
            name: plugins
        restartPolicy: Always
        serviceAccountName: velero
        volumes:
        - emptyDir: {}
          name: plugins
        - emptyDir: {}
          name: scratch
        - name: cloud-credentials
          secret:
            secretName: cloud-credentials
kind: List