#!/bin/bash

# Script to delete all Kubernetes resources for the PostgreSQL workshop
# Usage: ./delete-all.sh [--force] [--delete-data]
#   --force        : Skip confirmation prompts
#   --delete-data  : Delete PVCs and all data (by default, data is preserved)

set -e  # Exit on error

NAMESPACE="workshop-ghaza"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEEP_DATA=true

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print colored output
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}→ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${RED}⚠ $1${NC}"
}

echo "========================================"
echo "PostgreSQL Workshop - Delete All Resources"
echo "========================================"
echo ""

# Parse command line arguments
for arg in "$@"; do
    case $arg in
        --force)
            FORCE=true
            ;;
        --delete-data)
            KEEP_DATA=false
            ;;
    esac
done

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed. Please install kubectl first."
    exit 1
fi

# Check if helm is installed
if ! command -v helm &> /dev/null; then
    print_error "helm is not installed. Please install helm first."
    exit 1
fi

# Check if namespace exists
if ! kubectl get namespace $NAMESPACE &> /dev/null; then
    print_info "Namespace $NAMESPACE does not exist. Nothing to delete."
    exit 0
fi

# Confirm deletion unless --force flag is used
if [ "$FORCE" != "true" ]; then
    print_warning "This will delete ALL resources in namespace: $NAMESPACE"
    print_warning "This includes:"
    echo "  - PostgreSQL cluster"
    echo "  - PgBouncer poolers"
    if [ "$KEEP_DATA" = "true" ]; then
        echo "  - PVCs and data will be PRESERVED by default (use --delete-data to remove)"
    else
        echo "  - All persistent volumes and data will be DELETED (--delete-data flag active)"
    fi
    echo "  - LoadBalancer services"
    echo "  - Cloudflare tunnel (if configured)"
    echo "  - CloudNativePG operator"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_info "Deletion cancelled."
        exit 0
    fi
fi

echo ""
print_info "Starting deletion process..."
echo ""

# Delete Cloudflare tunnel
if kubectl get deployment pg-cloudflared -n $NAMESPACE &> /dev/null; then
    print_info "Deleting Cloudflare tunnel deployment"
    kubectl delete -f "$SCRIPT_DIR/network/cloudflare.yaml" --ignore-not-found=true
    print_success "Cloudflare tunnel deleted"
    echo ""
fi

# Delete Cloudflare secrets
if kubectl get secret pg-tunnel-token -n $NAMESPACE &> /dev/null; then
    print_info "Deleting Cloudflare tunnel secrets"
    kubectl delete -f "$SCRIPT_DIR/network/secrets.yaml" --ignore-not-found=true
    print_success "Cloudflare secrets deleted"
    echo ""
fi

# Delete LoadBalancer services
print_info "Deleting LoadBalancer services"
kubectl delete -f "$SCRIPT_DIR/database/loadbalancer.yaml" --ignore-not-found=true
print_success "LoadBalancer services deleted"
echo ""

# Delete MetalLB IP pool
print_info "Deleting MetalLB IP pool"
kubectl delete -f "$SCRIPT_DIR/network/pool.yaml" --ignore-not-found=true
print_success "MetalLB IP pool deleted"
echo ""

# Delete PgBouncer poolers
print_info "Deleting PgBouncer poolers"
kubectl delete -f "$SCRIPT_DIR/database/pooler.yaml" --ignore-not-found=true
print_success "PgBouncer poolers deleted"
echo ""

# Wait for poolers to be fully deleted
print_info "Waiting for poolers to be removed..."
kubectl wait --for=delete pooler/pgbouncer-rw -n $NAMESPACE --timeout=60s 2>/dev/null || true
kubectl wait --for=delete pooler/pgbouncer-ro -n $NAMESPACE --timeout=60s 2>/dev/null || true
echo ""

# Delete PodDisruptionBudget
print_info "Deleting PodDisruptionBudget"
kubectl delete -f "$SCRIPT_DIR/database/pdb.yaml" --ignore-not-found=true
print_success "PodDisruptionBudget deleted"
echo ""

# Delete PostgreSQL cluster
print_info "Deleting PostgreSQL cluster (this may take a minute)"

# If keeping data, remove ownerReferences from PVCs first to prevent auto-deletion
if [ "$KEEP_DATA" = "true" ]; then
    print_info "Removing ownerReferences from PVCs to prevent auto-deletion..."
    for pvc in $(kubectl get pvc -n $NAMESPACE -l cnpg.io/cluster=pg-ws -o name 2>/dev/null); do
        kubectl patch $pvc -n $NAMESPACE --type=json -p='[{"op": "remove", "path": "/metadata/ownerReferences"}]' 2>/dev/null || true
    done
    print_success "PVCs protected from auto-deletion"
fi

kubectl delete -f "$SCRIPT_DIR/database/cluster.yaml" --ignore-not-found=true
print_success "PostgreSQL cluster deleted"
echo ""

# Wait for cluster to be fully deleted
print_info "Waiting for cluster pods to be removed..."
kubectl wait --for=delete pods -l cnpg.io/cluster=pg-ws -n $NAMESPACE --timeout=120s 2>/dev/null || true
echo ""

# Delete secrets
print_info "Deleting secrets"
kubectl delete -f "$SCRIPT_DIR/database/secrets.yaml" --ignore-not-found=true
print_success "Secrets deleted"
echo ""

# Delete PVCs unless --keep-data flag is used
if [ "$KEEP_DATA" != "true" ]; then
    print_warning "Deleting PVCs (--delete-data flag active - this will DELETE all data)"
    kubectl delete pvc -n $NAMESPACE -l cnpg.io/cluster=pg-ws --ignore-not-found=true
    print_success "PVCs deleted"
    echo ""
else
    print_info "Preserving PVCs and data (default behavior)"
    PVC_COUNT=$(kubectl get pvc -n $NAMESPACE -l cnpg.io/cluster=pg-ws --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "$PVC_COUNT" -gt 0 ]; then
        print_success "Found $PVC_COUNT PVC(s) that will be preserved:"
        kubectl get pvc -n $NAMESPACE -l cnpg.io/cluster=pg-ws
    else
        print_info "No PVCs found to preserve"
    fi
    echo ""
fi

# Uninstall CloudNativePG operator
if helm list -n $NAMESPACE | grep -q cnpg; then
    print_info "Uninstalling CloudNativePG operator"
    helm uninstall cnpg -n $NAMESPACE
    print_success "CNPG operator uninstalled"
    echo ""
else
    print_info "CNPG operator not found (already uninstalled or not installed via helm)"
    echo ""
fi

# Delete namespace only if --delete-data flag is used
if [ "$KEEP_DATA" != "true" ]; then
    # Optional: Delete the namespace entirely
    if [ "$FORCE" != "true" ]; then
        read -p "Do you want to delete the entire namespace '$NAMESPACE'? (yes/no): " -r
        echo ""
        if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            print_info "Deleting namespace: $NAMESPACE"
            kubectl delete namespace $NAMESPACE
            print_success "Namespace deleted"
            echo ""
        else
            print_info "Namespace preserved. You can delete it manually with:"
            echo "  kubectl delete namespace $NAMESPACE"
            echo ""
        fi
    else
        print_info "Deleting namespace: $NAMESPACE"
        kubectl delete namespace $NAMESPACE
        print_success "Namespace deleted"
        echo ""
    fi
else
    print_warning "Namespace will NOT be deleted (data preservation mode)"
    print_info "The namespace '$NAMESPACE' contains your preserved PVCs with data."
    print_info "To delete the namespace later (this will delete your data):"
    echo "  kubectl delete namespace $NAMESPACE"
    echo ""
fi

# Check remaining resources
if kubectl get namespace $NAMESPACE &> /dev/null; then
    print_info "Checking for any remaining resources in namespace..."
    REMAINING=$(kubectl get all -n $NAMESPACE 2>/dev/null | grep -v "^NAME" | wc -l || echo "0")
    if [ "$REMAINING" -gt 0 ]; then
        print_warning "Some resources still exist in namespace:"
        kubectl get all -n $NAMESPACE
        echo ""
    else
        print_success "No resources remaining in namespace (except PVCs if preserved)"
        echo ""
    fi
fi

echo "========================================"
print_success "Deletion complete!"
echo "========================================"
echo ""

if [ "$KEEP_DATA" = "true" ]; then
    print_info "Data preservation summary:"
    echo "  - PVCs have been preserved and contain your data"
    echo "  - When you re-apply the cluster, it will reattach to existing PVCs"
    echo "  - Your database will retain all data from before deletion"
    echo ""
    print_warning "Important: Do not delete the namespace if you want to keep the data!"
    echo ""
fi

print_info "Note: MetalLB itself (in metallb-system namespace) was not removed."
print_info "To completely remove MetalLB, run:"
echo "  kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml"
echo ""
