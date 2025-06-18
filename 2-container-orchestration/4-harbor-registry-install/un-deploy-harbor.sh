#!/bin/bash

# ---
# Harbor Un-Deployment Script
#
# This script is intended to completely remove a Harbor installation deployed
# via the accompanying `deploy-harbor.sh` script and its related storage
# setup (`setup-harbor-storage.sh`) from a MicroK8s cluster.
#
# It performs the following actions:
# 1. Uninstalls the Harbor Helm release.
# 2. Deletes PersistentVolumeClaims (PVCs) associated with Harbor services.
# 3. Deletes PersistentVolumes (PVs) backing those PVCs.
# 4. Removes the actual data from the host path directories used by the PVs.
# 5. Deletes Kubernetes secrets created for Harbor (e.g., admin password).
# 6. Deletes the Kubernetes namespace where Harbor was deployed.
#
# CAUTION: This script is destructive and will lead to data loss for the
# Harbor instance. Ensure you have backups if needed before running.
# ---

# 1. Uninstall Helm release
microk8s.helm3 uninstall harbor -n harbor

# 2. Delete PVCs
microk8s.kubectl delete pvc harbor-registry-pvc -n harbor
microk8s.kubectl delete pvc harbor-jobservice-pvc -n harbor
microk8s.kubectl delete pvc harbor-database-pvc -n harbor
microk8s.kubectl delete pvc harbor-redis-pvc -n harbor
microk8s.kubectl delete pvc harbor-trivy-pvc -n harbor

# 3. Delete PVs
microk8s.kubectl delete pv harbor-registry-pv
microk8s.kubectl delete pv harbor-jobservice-pv
microk8s.kubectl delete pv harbor-database-pv
microk8s.kubectl delete pv harbor-redis-pv
microk8s.kubectl delete pv harbor-trivy-pv

# 4. Delete host path data (ensure path is correct for your setup)
sudo rm -rf /var/snap/microk8s/common/harbor-storage/harbor

# 5. Delete Harbor-specific secrets
microk8s.kubectl delete secret harbor-admin-password -n harbor
microk8s.kubectl delete secret harbor-ingress -n harbor # Adjust if your TLS secret name differs

# 6. Delete Harbor namespace
microk8s.kubectl delete namespace harbor
