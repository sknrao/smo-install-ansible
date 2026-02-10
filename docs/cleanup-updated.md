# Fixing the Three SMO Uninstallation Issues

## Problem Summary

You identified three critical issues preventing complete SMO cleanup:

1. **Completed pods not being removed** (affects complete removal)
2. **ONAP namespace stuck in Terminating** due to Kafka topic `acm-ppnt-sync-kt`
3. **SMO pods remain**: `kafka-client` and `minio-client` (not StatefulSets/Deployments)

## Root Cause Analysis

### Issue 1: Completed Pods Not Removed

**Why it happens:**
```yaml
# Original approach only deleted these workload types:
- StatefulSets
- Deployments  
- DaemonSets

# But MISSED:
- Jobs (create pods that run to completion)
- CronJobs (create recurring jobs)
- Standalone Pods (not managed by any controller)
```

**What gets left behind:**
```bash
$ kubectl get pods -n smo
NAME                     STATUS      RESTARTS   AGE
kafka-client             Completed   0          5h    # ← Job pod
minio-client             Completed   0          5h    # ← Job pod
some-init-job-xyz        Succeeded   0          5h    # ← Job pod
```

### Issue 2: ONAP Namespace Stuck on Kafka Topic

**Why it happens:**
```yaml
# Kafka topics have finalizers that prevent deletion:
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: acm-ppnt-sync-kt
  namespace: onap
  finalizers:
    - strimzi.io/topic-operator  # ← Blocks deletion!
```

**The cascade effect:**
```
1. Try to delete namespace "onap"
2. Namespace tries to delete KafkaTopic "acm-ppnt-sync-kt"
3. KafkaTopic has finalizer waiting for Strimzi operator
4. Strimzi operator might be deleted/unavailable
5. Finalizer never removed
6. Namespace stuck in "Terminating" forever
```

### Issue 3: Client Pods in SMO

**Why kafka-client and minio-client survive:**
```yaml
# These are created by Jobs, not Deployments/StatefulSets:
apiVersion: batch/v1
kind: Job
metadata:
  name: kafka-client-job
spec:
  template:
    spec:
      containers:
      - name: kafka-client
        image: confluentinc/cp-kafka:latest
        command: ["/bin/sh", "-c", "kafka-topics --list"]
      restartPolicy: Never  # Runs once, stays as "Completed"
```

**Pod lifecycle:**
```
Job created → Pod runs → Task completes → Pod status = "Completed"
                                            ↑
                              But pod is NOT deleted automatically!
```

## The Fixes

### Fix for Issue 1 & 3: Delete All Pod Types

```yaml
# NEW: Delete Jobs first (they create the completed pods)
- name: Delete Jobs in namespace
  shell: kubectl delete jobs --all -n {{ namespace }} --grace-period=0

- name: Delete CronJobs
  shell: kubectl delete cronjobs --all -n {{ namespace }} --grace-period=0

# NEW: Explicitly delete completed/failed pods
- name: Delete completed pods
  shell: |
    kubectl delete pods --field-selector=status.phase==Succeeded \
      -n {{ namespace }} --grace-period=0 --force

- name: Delete failed pods  
  shell: |
    kubectl delete pods --field-selector=status.phase==Failed \
      -n {{ namespace }} --grace-period=0 --force

# Then existing workloads
- name: Delete StatefulSets, Deployments, DaemonSets
  # ... existing tasks ...

# NEW: Force delete ANY remaining pods (catch-all)
- name: Force delete all remaining pods
  shell: kubectl delete pods --all -n {{ namespace }} --grace-period=0 --force
```

### Fix for Issue 2: Handle Kafka Topic Finalizers

```yaml
# Step 1: Check if Kafka CRD exists
- name: Check if KafkaTopic CRD exists
  shell: kubectl get crd kafkatopics.kafka.strimzi.io
  register: kafkatopic_crd_check
  failed_when: false

# Step 2: List all Kafka topics
- name: Get list of Kafka topics
  shell: kubectl get kafkatopics -n onap --no-headers | awk '{print $1}'
  register: kafka_topics_list
  when: kafkatopic_crd_check.rc == 0

# Step 3: Remove finalizers from each topic (key fix!)
- name: Remove finalizers from Kafka topics
  shell: |
    kubectl patch kafkatopic {{ item }} -n onap \
      -p '{"metadata":{"finalizers":null}}' --type=merge
  loop: "{{ kafka_topics_list.stdout_lines }}"
  when: kafkatopic_crd_check.rc == 0

# Step 4: Force delete the problematic topic specifically
- name: Force delete acm-ppnt-sync-kt
  shell: |
    kubectl delete kafkatopic acm-ppnt-sync-kt -n onap \
      --grace-period=0 --force
  when: kafkatopic_crd_check.rc == 0

# Step 5: Delete all remaining topics
- name: Delete all Kafka topics
  shell: |
    kubectl delete kafkatopics --all -n onap \
      --timeout=60s --grace-period=0 --force
  when: kafkatopic_crd_check.rc == 0
```

## Complete Deletion Order (Fixed)

```
┌─────────────────────────────────────────────┐
│ 1. Custom Resources (Kafka Topics)         │
│    - Remove finalizers first!              │
│    - Then force delete                     │
├─────────────────────────────────────────────┤
│ 2. Jobs & CronJobs                         │
│    - These create completed pods           │
├─────────────────────────────────────────────┤
│ 3. Completed/Failed Pods                   │
│    - Explicitly delete by status           │
├─────────────────────────────────────────────┤
│ 4. StatefulSets                            │
│    - Databases, Kafka brokers              │
├─────────────────────────────────────────────┤
│ 5. Deployments                             │
│    - Most application workloads            │
├─────────────────────────────────────────────┤
│ 6. DaemonSets                              │
│    - Node-level services                   │
├─────────────────────────────────────────────┤
│ 7. ReplicaSets                             │
│    - Often left by Deployments             │
├─────────────────────────────────────────────┤
│ 8. ALL Remaining Pods (Force)              │
│    - Catch-all for anything missed         │
├─────────────────────────────────────────────┤
│ 9. PersistentVolumeClaims                  │
│    - Storage resources                     │
├─────────────────────────────────────────────┤
│ 10. Services & Other Resources             │
│     - Remove finalizers if needed          │
├─────────────────────────────────────────────┤
│ 11. Namespace                              │
│     - Should be mostly empty now           │
├─────────────────────────────────────────────┤
│ 12. Force Delete Namespace (if stuck)      │
│     - Remove finalizers                    │
│     - Force with --grace-period=0          │
└─────────────────────────────────────────────┘
```

## Before vs After Comparison

### BEFORE (Original)

```yaml
# ❌ Only deleted 3 workload types
- Delete StatefulSets
- Delete Deployments
- Delete DaemonSets
- Delete namespace  # ← Gets stuck!

# What's left:
- ✗ Jobs still exist
- ✗ Completed pods (kafka-client, minio-client)
- ✗ Kafka topics with finalizers
- ✗ Namespace stuck in Terminating
```

### AFTER (Fixed)

```yaml
# ✅ Comprehensive cleanup
- Remove Kafka topic finalizers  # Issue 2 fix
- Delete Jobs & CronJobs         # Issue 1 & 3 fix
- Delete completed pods          # Issue 1 & 3 fix
- Delete StatefulSets
- Delete Deployments
- Delete DaemonSets
- Delete ReplicaSets
- Force delete ALL remaining pods # Catch-all
- Delete PVCs
- Remove service finalizers
- Delete namespace
- Force delete if stuck          # Fallback

# Result:
- ✓ All pods removed
- ✓ Kafka topics deleted
- ✓ Namespace successfully deleted
```

## How to Apply the Fixes

### Option 1: Replace Individual Files

```bash
# Replace ONAP cleanup
cp cleanup_onap_fixed.yml smo-uninstall/tasks/cleanup_onap.yml

# Replace SMO cleanup  
cp cleanup_smo_fixed.yml smo-uninstall/tasks/cleanup_smo.yml

# Replace NonRTRIC cleanup
cp cleanup_nonrtric_fixed.yml smo-uninstall/tasks/cleanup_nonrtric.yml
```

### Option 2: Manual Quick Fix (Emergency)

If you have a stuck namespace right now:

```bash
# For Issue 2 (Kafka topic blocking ONAP namespace):
kubectl patch kafkatopic acm-ppnt-sync-kt -n onap \
  -p '{"metadata":{"finalizers":null}}' --type=merge
kubectl delete kafkatopic acm-ppnt-sync-kt -n onap --force --grace-period=0
kubectl patch namespace onap -p '{"metadata":{"finalizers":null}}' --type=merge
kubectl delete namespace onap --force --grace-period=0

# For Issue 1 & 3 (Completed pods):
kubectl delete pods --field-selector=status.phase==Succeeded --all-namespaces --force --grace-period=0
kubectl delete jobs --all -n smo --force --grace-period=0
kubectl delete jobs --all -n onap --force --grace-period=0
kubectl delete jobs --all -n nonrtric --force --grace-period=0
```

## Verification After Fixes

Run these commands to verify complete cleanup:

```bash
# 1. Check for any completed pods
kubectl get pods --all-namespaces --field-selector=status.phase==Succeeded
# Should return: No resources found

# 2. Check for any failed pods
kubectl get pods --all-namespaces --field-selector=status.phase==Failed
# Should return: No resources found

# 3. Check for Jobs
kubectl get jobs --all-namespaces | grep -E 'onap|nonrtric|smo'
# Should return: No resources found

# 4. Check for Kafka topics
kubectl get kafkatopics --all-namespaces
# Should return: No resources found (or error if CRD removed)

# 5. Check namespace status
kubectl get namespace | grep -E 'onap|nonrtric|smo'
# Should return: No resources found

# 6. Check for any SMO-related pods
kubectl get pods --all-namespaces | grep -E 'kafka-client|minio-client'
# Should return: No resources found
```

## What Each Fix Does

### cleanup_onap_fixed.yml

✅ Removes finalizers from Kafka topics before deletion
✅ Force deletes `acm-ppnt-sync-kt` specifically
✅ Deletes Jobs and completed pods
✅ Removes finalizers from services/configmaps
✅ Force deletes namespace if stuck
✅ Applies same fixes to strimzi-system and mariadb-operator

### cleanup_smo_fixed.yml

✅ Deletes Jobs & CronJobs first
✅ Explicitly deletes completed/failed pods (kafka-client, minio-client)
✅ Adds ReplicaSet deletion
✅ Force deletes all remaining pods
✅ Removes service finalizers
✅ Force deletes namespace if stuck

### cleanup_nonrtric_fixed.yml

✅ Same improvements as cleanup_smo_fixed.yml
✅ Preserves Kong cleanup logic
✅ Adds comprehensive pod cleanup
✅ Force delete mechanisms

## Key Improvements

1. **Finalizer Removal**: Prevents resources from blocking namespace deletion
2. **Job Deletion**: Removes the source of completed pods
3. **Status-Based Pod Deletion**: Explicitly targets Succeeded/Failed pods
4. **Force Delete Catch-All**: `kubectl delete pods --all` as final safety net
5. **Verification Steps**: Displays whether namespace was actually deleted

## Testing the Fixes

After applying, run the playbook again:

```bash
ansible-playbook -i inventory.ini smo_uninstall_playbook.yml -vv
```

You should see:
- ✅ No "completed pods" remaining messages
- ✅ Kafka topics deleted without hanging
- ✅ All namespaces successfully deleted
- ✅ "successfully deleted" status messages
