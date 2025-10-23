# Workshop README — PostgreSQL on Kubernetes (CNPG + PgBouncer + MetalLB + Cloudflare Tunnel)

This README summarizes everything we set up in this thread for a **simple but reliable PostgreSQL workshop environment** on a kubeadm cluster. It covers:

* High‑level architecture
* Namespaces, secrets, and Cluster CR
* Storage and scheduling (fixing Pending pods)
* Connection pooling (PgBouncer)
* Access patterns (in‑cluster, NodePort, LoadBalancer/MetalLB)
* Picking safe IPs with `nmap`
* Cloudflare Tunnel integration (Zero Trust)
* Operational tips, troubleshooting, and security

All examples use **namespace `workshop-ghaza`**, **Cluster name `pg-ws`**, **DB `spectra`**, **app user `peserta`**.

---

## 1) Architecture (what we ended up with)

* **CloudNativePG (CNPG) cluster**: `pg-ws` with **3 instances** (1 primary + 2 replicas)
* **Persistent storage**: `local-path` StorageClass; **separate WAL PVC**
* **PgBouncer poolers**: two Deployments managed by CNPG **Pooler CRs**

  * `pgbouncer-rw` (read/write → primary)
  * `pgbouncer-ro` (read‑only → replicas)
* **Services**:

  * In‑cluster ClusterIP: `pg-ws-rw`, `pg-ws-ro`, `pgbouncer-rw`, `pgbouncer-ro`
  * External (for attendees): **LoadBalancer via MetalLB**

    * `pgbouncer-rw-lb` → **10.34.4.196:5432**
    * `pgbouncer-ro-lb` → **10.34.4.197:5432**
* **Optional**: NodePort (30432/30433) was shown but we switched to MetalLB for cleaner 5432 port
* **Cloudflare Tunnel**: `cloudflared` Deployment routes a public hostname to the internal PgBouncer service using a remotely managed tunnel token
* **Resiliency**: PodDisruptionBudget (`minAvailable: 2`), anti‑affinity enabled; PgBouncer sits in front to smooth failovers

---

## 2) Namespaces

```bash
kubectl create ns workshop-ghaza || true
```

---

## 3) Secrets (superuser + app user)

> Use strong passwords; **do not commit these secrets to Git**. Prefer SealedSecrets/External Secrets in production.

```bash
kubectl -n workshop-ghaza create secret generic pg-superuser \
  --from-literal=username=postgres \
  --from-literal=password='postgrespw'

kubectl -n workshop-ghaza create secret generic pg-peserta \
  --from-literal=username=peserta \
  --from-literal=password='apppw'
```

YAML equivalent (if you must store it, put it in a private repo only):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: pg-superuser
  namespace: workshop-ghaza
type: Opaque
stringData:
  username: postgres
  password: postgrespw
---
apiVersion: v1
kind: Secret
metadata:
  name: pg-peserta
  namespace: workshop-ghaza
type: Opaque
stringData:
  username: peserta
  password: apppw
```

---

## 4) CloudNativePG Cluster CR (with WAL PVC + anti‑affinity)

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: pg-ws
  namespace: workshop-ghaza
spec:
  instances: 3
  imageName: ghcr.io/cloudnative-pg/postgresql:16

  superuserSecret:
    name: pg-superuser

  bootstrap:
    initdb:
      database: spectra
      owner: peserta
      secret:
        name: pg-peserta

  storage:
    size: 5Gi
    storageClass: local-path
  walStorage:
    size: 3Gi
    storageClass: local-path

  affinity:
    enablePodAntiAffinity: true

  resources:
    requests:
      cpu: "250m"
      memory: "512Mi"
    limits:
      cpu: "1"
      memory: "1Gi"

  monitoring:
    enablePodMonitor: true
```

Apply:

```bash
kubectl apply -f pg-cluster.yaml
```

---

## 5) PgBouncer Poolers (RW & RO)

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Pooler
metadata:
  name: pgbouncer-rw
  namespace: workshop-ghaza
spec:
  cluster:
    name: pg-ws
  instances: 1
  type: rw
  pgbouncer:
    poolMode: transaction
    parameters:
      default_pool_size: "50"
---
apiVersion: postgresql.cnpg.io/v1
kind: Pooler
metadata:
  name: pgbouncer-ro
  namespace: workshop-ghaza
spec:
  cluster:
    name: pg-ws
  instances: 1
  type: ro
  pgbouncer:
    poolMode: transaction
    parameters:
      default_pool_size: "50"
```

Apply:

```bash
kubectl apply -f pg-poolers.yaml
```

**What these do:** PgBouncer provides lightweight connection pooling and keeps client connections stable during primary failover. Use RW for writes/reads; RO for read‑only workloads.

---

## 6) Pod Disruption Budget (PDB)

Ensures at least 2 Postgres pods remain available during voluntary disruptions (drain/upgrade):

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: pg-ws-pdb
  namespace: workshop-ghaza
spec:
  minAvailable: 2
  selector:
    matchLabels:
      cnpg.io/cluster: pg-ws
```

Apply:

```bash
kubectl apply -f pg-pdb.yaml
```

---

## 7) Fixing Pending Pods (what we debugged)

**Symptom:** `pg-ws-2` was `Pending` while init/join jobs had completed.

**Root causes & fixes:**

* **Unbound PVCs** (local‑path not binding):

  * Check: `kubectl -n workshop-ghaza get pvc -l cnpg.io/cluster=pg-ws -o wide`
  * Ensure `local-path` is installed and default:

    ```bash
    kubectl get sc
    kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
    ```
  * If a PVC is stuck in `Pending`, delete and let it re‑provision:

    ```bash
    kubectl -n workshop-ghaza delete pvc pg-ws-2 || true
    kubectl -n workshop-ghaza delete pvc pg-ws-wal-2 || true
    ```
* **local‑path provisioner DaemonSet not running on all workers**:

  * Check: `kubectl -n local-path-storage get pods -o wide`
  * Restart DS: `kubectl -n local-path-storage rollout restart ds/local-path-provisioner`
* **Resource pressure**: temporarily lower requests; or disable anti‑affinity briefly if scheduler is constrained.

---

## 8) Accessing the database

### In‑cluster (apps in same cluster)

* **RW**: `pgbouncer-rw.workshop-ghaza.svc.cluster.local:5432`
* **RO**: `pgbouncer-ro.workshop-ghaza.svc.cluster.local:5432`

Example debug pod:

```bash
kubectl -n workshop-ghaza run psql --rm -it --image=postgres:16 -- bash
export PGHOST=pgbouncer-rw.workshop-ghaza.svc.cluster.local
export PGPORT=5432
export PGUSER=peserta
export PGPASSWORD=$(kubectl -n workshop-ghaza get secret pg-peserta -o jsonpath='{.data.password}' | base64 -d)
export PGDATABASE=spectra
psql -c "select now(), current_user, version();"
```

### Port‑forward from your laptop (zero exposure)

```bash
kubectl -n workshop-ghaza port-forward svc/pgbouncer-rw 6432:5432
psql "host=127.0.0.1 port=6432 dbname=spectra user=peserta password=$(kubectl -n workshop-ghaza get secret pg-peserta -o jsonpath='{.data.password}' | base64 -d)" -c "select now();"
```

---

## 9) External exposure options we covered

### A) NodePort (we tried first; **5432 not allowed as nodePort**)

* NodePort range is **30000–32767** (cannot use 5432). Example that works:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: pgbouncer-rw-nodeport
  namespace: workshop-ghaza
spec:
  type: NodePort
  selector:
    cnpg.io/poolerName: pgbouncer-rw
  ports:
    - name: postgres
      port: 5432
      targetPort: 5432
      nodePort: 30432
```

**But we moved to MetalLB** to keep port 5432 externally and avoid per‑node port exposure.

### B) MetalLB LoadBalancer (**chosen solution**)

#### 1) Find two free IPs on your LAN

Your subnet: `10.34.4.128/25` (usable `10.34.4.129–254`). We scanned with:

```bash
sudo nmap -sn 10.34.4.128/25 -oG - | awk '/Up$/{print $2}'
```

We selected **10.34.4.196** and **10.34.4.197** (not in the `Up` list). Double‑check:

```bash
ping -c 2 10.34.4.196 || true
ping -c 2 10.34.4.197 || true
```

#### 2) Install MetalLB & configure pool (once)

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
```

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: pg-ip-pool
  namespace: metallb-system
spec:
  addresses:
    - 10.34.4.196-10.34.4.197
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: pg-l2adv
  namespace: metallb-system
spec: {}
```

Apply:

```bash
kubectl apply -f metallb-ip-pool.yaml
```

#### 3) Expose PgBouncer with type LoadBalancer (pinned to those IPs)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: pgbouncer-rw-lb
  namespace: workshop-ghaza
spec:
  type: LoadBalancer
  loadBalancerIP: 10.34.4.196
  selector:
    cnpg.io/poolerName: pgbouncer-rw
  ports:
    - name: postgres
      port: 5432
      targetPort: 5432
---
apiVersion: v1
kind: Service
metadata:
  name: pgbouncer-ro-lb
  namespace: workshop-ghaza
spec:
  type: LoadBalancer
  loadBalancerIP: 10.34.4.197
  selector:
    cnpg.io/poolerName: pgbouncer-ro
  ports:
    - name: postgres
      port: 5432
      targetPort: 5432
```

Apply and verify:

```bash
kubectl apply -f pgbouncer-lb.yaml
kubectl -n workshop-ghaza get svc pgbouncer-*-lb
```

Connect:

```bash
export PGPASSWORD=$(kubectl -n workshop-ghaza get secret pg-peserta -o jsonpath='{.data.password}' | base64 -d)
psql "host=10.34.4.196 port=5432 dbname=spectra user=peserta password=$PGPASSWORD" -c "select now(), inet_server_addr();"
```

### C) (Optional) Ingress TCP via ingress‑nginx

If you already run ingress‑nginx, you can map TCP 5432 → `pgbouncer-rw` using a `tcp-services` ConfigMap. (We didn’t need this because MetalLB was cleaner.)

---

## 10) Cloudflare Tunnel (Zero Trust) — following Cloudflare’s doc

We set up a **remotely managed** tunnel using `TUNNEL_TOKEN`.

### 1) Create the Tunnel in Cloudflare dashboard

* Zero Trust → Networks → Tunnels → **Create Tunnel** → **Cloudflared** → **Docker**
* Name it (e.g., `pg-tunnel`)
* Copy the **token** (starts with `eyJhIjoi…`).

### 2) Store the token as a Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: pg-tunnel-token
  namespace: workshop-ghaza
stringData:
  token: <YOUR_TUNNEL_TOKEN>
```

```bash
kubectl apply -f pg-tunnel-secret.yaml
```

### 3) Deploy `cloudflared`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pg-cloudflared
  namespace: workshop-ghaza
spec:
  replicas: 2
  selector:
    matchLabels:
      app: pg-cloudflared
  template:
    metadata:
      labels:
        app: pg-cloudflared
    spec:
      securityContext:
        sysctls:
        - name: net.ipv4.ping_group_range
          value: "65532 65532"
      containers:
      - name: cloudflared
        image: cloudflare/cloudflared:latest
        env:
        - name: TUNNEL_TOKEN
          valueFrom:
            secretKeyRef:
              name: pg-tunnel-token
              key: token
        command:
        - cloudflared
        - tunnel
        - --no-autoupdate
        - --loglevel
        - debug
        - --metrics
        - 0.0.0.0:2000
        - run
        livenessProbe:
          httpGet:
            path: /ready
            port: 2000
          failureThreshold: 1
          initialDelaySeconds: 10
          periodSeconds: 10
```

Apply & check:

```bash
kubectl apply -f pg-cloudflared.yaml
kubectl -n workshop-ghaza get pods -l app=pg-cloudflared
kubectl -n workshop-ghaza logs -l app=pg-cloudflared | tail -n +1
```

### 4) Route a hostname to your Postgres service

In the Cloudflare Zero Trust **Tunnel** UI → **Route tunnel** → **Public Hostnames**:

* Hostname: `postgres.workshop.<yourdomain>.com`
* **Service**: `tcp://pgbouncer-rw-lb.workshop-ghaza.svc.cluster.local:5432`
* Save.

(Optional) Add **Cloudflare Access** policy to restrict who can reach it.

### 5) Connect through Cloudflare

```bash
psql "host=postgres.workshop.<yourdomain>.com port=5432 dbname=spectra user=peserta password=$(kubectl -n workshop-ghaza get secret pg-peserta -o jsonpath='{.data.password}' | base64 -d) sslmode=require" -c "select now();"
```

---

## 11) Security & repo hygiene

* **Do not commit raw Secrets**; use sealed secrets or external secret managers.
* Add a `.gitignore` rule for any `*-secret.yaml` you accidentally create.
* Consider NetworkPolicies to restrict access to PgBouncer from known namespaces/pods only.
* If exposing to the public Internet, prefer Cloudflare Tunnel + Access over raw IP exposure.
* Rotate `peserta` password if sharing with many participants.

---

## 12) Quick verification commands

```bash
# Overall status
kubectl -n workshop-ghaza get pods -l cnpg.io/cluster=pg-ws -L role
kubectl -n workshop-ghaza get pvc
kubectl -n workshop-ghaza get svc | egrep 'pg-ws-|pgbouncer-'

# Who is primary?
kubectl -n workshop-ghaza get pods -l cnpg.io/cluster=pg-ws -L role | grep primary

# Connect via service DNS from a debug pod
kubectl -n workshop-ghaza run psql --rm -it --image=postgres:16 -- bash -lc \
  "PGPASSWORD=$(kubectl -n workshop-ghaza get secret pg-peserta -o jsonpath='{.data.password}' | base64 -d) psql -h pgbouncer-rw.workshop-ghaza.svc.cluster.local -U peserta -d spectra -c 'select now()'"

# MetalLB services
kubectl -n workshop-ghaza get svc pgbouncer-rw-lb pgbouncer-ro-lb -o wide

# Cloudflared health
kubectl -n workshop-ghaza logs -l app=pg-cloudflared --tail=50
```

---

## 13) Troubleshooting quick map

* **Pod Pending** with `unbound immediate PersistentVolumeClaims` → check local-path, PVCs, DS on all workers; recreate Pending PVCs.
* **NodePort error** `Invalid value ... range 30000-32767` → NodePort cannot use 5432; use MetalLB or port‑forward.
* **Connection refused externally** → check LB IPs assigned, firewall rules, service selectors.
* **Auth failed** → verify `pg-peserta` secret values; try superuser to isolate.
* **Failover** → PgBouncer hides primary changes; connect via RW service.

---

### Done

You now have a tidy, workshop‑friendly Postgres on Kubernetes stack with HA, pooling, clean external access via MetalLB (and optionally Cloudflare Tunnel), and the right knobs for stability. Adjust sizes and policies as your workshop or lab grows.
