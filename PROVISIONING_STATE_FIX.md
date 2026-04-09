# KieApp Provisioning State Fix

## Issues Fixed

### 1. Provisioning State Getting Stuck (Requeue Issue)

**Problem:**
The KieApp custom resource provisioning state would get stuck in "Provisioning" and never transition to "Deployed" even when all resources were successfully created.

**Root Cause:**
In [`pkg/controller/kieapp/kieapp_controller.go`](pkg/controller/kieapp/kieapp_controller.go:192-200), the `checkStatus()` function had an issue where:

When `hasUpdates=true` (resources were added/updated/removed) and the status was already "Provisioning", `SetProvisioning()` would return `false`, causing `requeue=false`. This stopped reconciliation even though resources were still being created/updated, preventing the status from ever transitioning to "Deployed" once resources stabilized.

**Fix:**
Modified the `checkStatus()` function to always requeue when there are updates, even if the status condition doesn't change. This ensures the controller continues monitoring resource creation/updates until they complete and the status can transition to "Deployed".

The fix relies on Kubernetes watch events to trigger reconciliation when deployment status changes (pods starting/becoming ready), so explicit deployment readiness checks in the requeue logic are not needed.

**Changed Code:**
```go
func (reconciler *Reconciler) checkStatus(ctx context.Context, instance, cachedInstance *api.KieApp, hasUpdates bool) (reconcile.Result, error) {
	var requeue bool
	if hasUpdates {
		requeue = status.SetProvisioning(instance)
		// If status didn't change but we have updates, still requeue to monitor progress
		if !requeue {
			requeue = true
		}
	} else {
		requeue = status.SetDeployed(instance)
	}
	return reconciler.updateStatus(ctx, instance, cachedInstance, requeue)
}
```

### 2. Invalid ServiceAccount Annotation Causing Oscillation

**Problem:**
The console ServiceAccount had an invalid annotation key that violated Kubernetes naming rules, causing reconciliation errors and oscillation between "Provisioning" and "Deployed" states.

**Error Message:**
```
ServiceAccount "console-cr-form" is invalid: metadata.annotations: Invalid value: 
"serviceaccounts.openshift.io/internal-registry-pull-secret-ref:console-cr-form-dockercfg-serviceaccounts.openshift.io/oauth-redirectreference.primary": 
a qualified name must consist of alphanumeric characters, '-', '_' or '.', and must start and end with an alphanumeric character
```

**Root Cause:**
In [`pkg/controller/kieapp/deploy_ui.go`](pkg/controller/kieapp/deploy_ui.go:441), the annotation key was malformed - it appeared to be two separate annotation keys concatenated with a colon, which is not allowed in Kubernetes annotation keys.

**Fix:**
Corrected the annotation key to use only the valid OAuth redirect reference annotation:

**Changed Code:**
```go
Annotations: map[string]string{
	"serviceaccounts.openshift.io/oauth-redirectreference.primary": string(annotation),
},
```

### 3. Deployment Comparison Causing Continuous Updates (Oscillation)

**Problem:**
The operator was continuously detecting Deployments as "not equal" on every reconciliation loop, even when no actual changes were made. This caused:
- Continuous resource updates (visible as increasing `generation` and `revision` numbers)
- Status oscillating between "Provisioning" and "Deployed"
- Resources never stabilizing

**Root Cause:**
In [`pkg/controller/kieapp/kieapp_controller.go`](pkg/controller/kieapp/kieapp_controller.go:255-277), there was no custom comparator for `appsv1.Deployment` resources. The default comparator from `operator-utils` library compares ALL fields including:
- `status` (which changes as pods start/stop)
- `metadata.resourceVersion` (updated by Kubernetes on every change)
- `metadata.generation` (incremented on spec changes)
- `metadata.managedFields` (updated by field managers)

These fields change frequently even when the desired state hasn't changed, causing the comparator to always return "not equal".

**Fix:**
Added a custom comparator for Deployments that clears dynamic fields before comparison:

**Changed Code:**
```go
func getComparator() compare.MapComparator {
	resourceComparator := compare.DefaultComparator()
	
	// Custom comparator for Deployments to avoid oscillation
	deploymentType := reflect.TypeOf(appsv1.Deployment{})
	defaultDeploymentComparator := resourceComparator.GetComparator(deploymentType)
	resourceComparator.SetComparator(deploymentType, func(deployed client.Object, requested client.Object) bool {
		dep1 := deployed.(*appsv1.Deployment).DeepCopy()
		dep2 := requested.(*appsv1.Deployment).DeepCopy()
		
		// Clear fields that are managed by Kubernetes and should not trigger updates
		dep1.Status = appsv1.DeploymentStatus{}
		dep2.Status = appsv1.DeploymentStatus{}
		dep1.ObjectMeta.ResourceVersion = ""
		dep2.ObjectMeta.ResourceVersion = ""
		dep1.ObjectMeta.Generation = 0
		dep2.ObjectMeta.Generation = 0
		dep1.ObjectMeta.ManagedFields = nil
		dep2.ObjectMeta.ManagedFields = nil
		
		return defaultDeploymentComparator(dep1, dep2)
	})
	
	// ... rest of comparators
}
```

## Impact

These fixes resolve:
1. KieApp resources getting stuck in "Provisioning" state indefinitely
2. Reconciliation errors due to invalid ServiceAccount annotations
3. Oscillation between "Provisioning" and "Deployed" states caused by continuous Deployment updates
4. Excessive reconciliation loops (from multiple times per second to only when actual changes occur)
5. Improved reliability of the operator's state management

## Testing Recommendations

1. Deploy a KieApp instance and verify it transitions from "Provisioning" to "Deployed"
2. Verify the console ServiceAccount is created without errors
3. Check operator logs for absence of annotation validation errors
4. Verify no oscillation occurs between states after deployment is complete