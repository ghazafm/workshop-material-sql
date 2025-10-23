#!/bin/bash

# Script to apply all Kubernetes resources for the PostgreSQL workshop
# Usage: ./apply-all.sh

set -e  # Exit on error

NAMESPACE="workshop-ghaza"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================"
echo "PostgreSQL Workshop - Apply All Resources"
echo "========================================"
echo ""

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

# Create namespace
print_info "Creating namespace: $NAMESPACE"
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
print_success "Namespace created/verified"
echo ""

# Install CloudNativePG operator
print_info "Installing CloudNativePG operator (CNPG)"
if ! helm list -n $NAMESPACE | grep -q cnpg; then
    print_info "Adding CNPG helm repository..."
    helm repo add cnpg https://cloudnative-pg.github.io/charts
    helm repo update
    print_info "Installing CNPG operator..."
    helm upgrade --install cnpg \
      --namespace $NAMESPACE \
      cnpg/cloudnative-pg
    print_success "CNPG operator installed"
else
    print_info "CNPG operator already installed, upgrading..."
    helm repo update
    helm upgrade --install cnpg \
      --namespace $NAMESPACE \
      cnpg/cloudnative-pg
    print_success "CNPG operator upgraded"
fi

# Wait for CNPG operator to be ready
print_info "Waiting for CNPG operator to be ready..."
kubectl wait --for=condition=Available deployment/cnpg-cloudnative-pg -n $NAMESPACE --timeout=120s
print_success "CNPG operator is ready"
echo ""

# Apply storage class
print_info "Configuring storage class (local-path)"
if [ -f "$SCRIPT_DIR/database/storageclass.sh" ]; then
    bash "$SCRIPT_DIR/database/storageclass.sh"
    print_success "Storage class configured"
else
    print_info "Checking if local-path storage class exists..."
    if kubectl get storageclass local-path &> /dev/null; then
        kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
        print_success "Storage class configured"
    else
        print_error "local-path storage class not found. Please install it first."
        exit 1
    fi
fi
echo ""

# Apply secrets
print_info "Creating secrets"
if [ -f "$SCRIPT_DIR/database/secrets.yaml" ]; then
    kubectl apply -f "$SCRIPT_DIR/database/secrets.yaml"
    print_success "Secrets created"
else
    print_error "secrets.yaml not found. Please create it from secrets.template.yaml"
    echo "  cp $SCRIPT_DIR/database/secrets.template.yaml $SCRIPT_DIR/database/secrets.yaml"
    echo "  # Then edit secrets.yaml with your passwords"
    exit 1
fi
echo ""

# Apply PostgreSQL cluster
print_info "Creating PostgreSQL cluster (this may take a few minutes)"
kubectl apply -f "$SCRIPT_DIR/database/cluster.yaml"
print_success "PostgreSQL cluster configuration applied"
echo ""

# Wait for cluster to be ready
print_info "Waiting for PostgreSQL cluster to be ready..."
kubectl wait --for=condition=Ready cluster/pg-ws -n $NAMESPACE --timeout=300s || true
echo ""

# Apply PodDisruptionBudget
print_info "Creating PodDisruptionBudget"
kubectl apply -f "$SCRIPT_DIR/database/pdb.yaml"
print_success "PodDisruptionBudget created"
echo ""

# Apply PgBouncer poolers
print_info "Creating PgBouncer poolers"
kubectl apply -f "$SCRIPT_DIR/database/pooler.yaml"
print_success "PgBouncer poolers created"
echo ""

# Wait for poolers to be ready
print_info "Waiting for PgBouncer poolers to be ready..."
sleep 10
echo ""

# Install MetalLB if needed
print_info "Setting up MetalLB for LoadBalancer"
if [ -f "$SCRIPT_DIR/network/metallb.sh" ]; then
    bash "$SCRIPT_DIR/network/metallb.sh"
    print_success "MetalLB configured"
else
    print_info "Checking if MetalLB is installed..."
    if ! kubectl get namespace metallb-system &> /dev/null; then
        print_info "Installing MetalLB..."
        kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
        sleep 10
    fi
    print_success "MetalLB ready"
fi
echo ""

# Apply MetalLB IP pool
print_info "Configuring MetalLB IP pool"
kubectl apply -f "$SCRIPT_DIR/network/pool.yaml"
print_success "MetalLB IP pool configured"
echo ""

# Apply LoadBalancer services
print_info "Creating LoadBalancer services"
kubectl apply -f "$SCRIPT_DIR/database/loadbalancer.yaml"
print_success "LoadBalancer services created"
echo ""

# Optional: Apply Cloudflare tunnel if secrets exist
if [ -f "$SCRIPT_DIR/network/secrets.yaml" ]; then
    print_info "Creating Cloudflare tunnel secrets"
    kubectl apply -f "$SCRIPT_DIR/network/secrets.yaml"
    print_success "Cloudflare tunnel secrets created"
    echo ""
    
    print_info "Deploying Cloudflare tunnel"
    kubectl apply -f "$SCRIPT_DIR/network/cloudflare.yaml"
    print_success "Cloudflare tunnel deployed"
    echo ""
else
    print_info "Cloudflare tunnel secrets not found, skipping tunnel deployment"
    echo ""
fi

echo "========================================"
print_success "All resources applied successfully!"
echo "========================================"
echo ""

# Show status
print_info "Current status:"
echo ""
echo "Pods:"
kubectl get pods -n $NAMESPACE
echo ""
echo "Services:"
kubectl get svc -n $NAMESPACE
echo ""
echo "PVCs:"
kubectl get pvc -n $NAMESPACE
echo ""

# Get LoadBalancer IPs
print_info "LoadBalancer External IPs:"
kubectl get svc -n $NAMESPACE pgbouncer-rw-lb pgbouncer-ro-lb -o wide
echo ""

# Connection info
print_info "Connection information:"
PGPASSWORD=$(kubectl -n $NAMESPACE get secret pg-peserta -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)
RW_IP=$(kubectl -n $NAMESPACE get svc pgbouncer-rw-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
RO_IP=$(kubectl -n $NAMESPACE get svc pgbouncer-ro-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)

if [ ! -z "$RW_IP" ]; then
    echo "Read-Write (RW) connection:"
    echo "  psql \"host=$RW_IP port=5432 dbname=spectra user=peserta password=$PGPASSWORD\""
    echo ""
fi

if [ ! -z "$RO_IP" ]; then
    echo "Read-Only (RO) connection:"
    echo "  psql \"host=$RO_IP port=5432 dbname=spectra user=peserta password=$PGPASSWORD\""
    echo ""
fi

echo "In-cluster connection:"
echo "  RW: pgbouncer-rw.workshop-ghaza.svc.cluster.local:5432"
echo "  RO: pgbouncer-ro.workshop-ghaza.svc.cluster.local:5432"
echo ""

print_success "Setup complete! Your PostgreSQL workshop environment is ready."
