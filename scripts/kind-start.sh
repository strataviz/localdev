#!/usr/bin/env bash
set -o errexit

CLUSTER_NAME=$1
NODE_IMAGE="kindest/node:v1.28.0"
SRCDIR=$2

CLUSTER="$(kind get clusters 2>&1 | grep ${CLUSTER_NAME} || : )"
if [ "x$CLUSTER" == "x" ] ; then
cat <<EOF | kind create cluster --name=${CLUSTER_NAME} --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  image: $NODE_IMAGE
  extraMounts:
    - hostPath: ${SRCDIR}
      containerPath: /mnt
      readOnly: true
    - hostPath: ${PWD}/.minio
      containerPath: /data
      readOnly: false
- role: worker
  image: $NODE_IMAGE
  extraMounts:
    - hostPath: ${SRCDIR}
      containerPath: /mnt
      readOnly: true
    - hostPath: ${PWD}/.minio
      containerPath: /data
      readOnly: false
- role: worker
  image: $NODE_IMAGE
  extraMounts:
    - hostPath: ${SRCDIR}
      containerPath: /mnt
      readOnly: true
    - hostPath: ${PWD}/.minio
      containerPath: /data
      readOnly: false
- role: worker
  image: $NODE_IMAGE
  extraMounts:
    - hostPath: ${SRCDIR}
      containerPath: /mnt
      readOnly: true
    - hostPath: ${PWD}/.minio
      containerPath: /data
      readOnly: false
EOF
else
	echo "Cluster exists, skipping creation"
fi
