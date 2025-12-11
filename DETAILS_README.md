# Operator and Operator Bundle Build Details

This document describes in detail how the operator image and the operator bundle image are built in this repository.

## 1. High level components

There are two main build artefacts:

- Operator runtime image – container image that runs the Go based controller. The main binary is `kie-cloud-operator`, with an auxiliary `console-cr-form` binary.
- Operator bundle image – an Operator Lifecycle Manager (OLM) bundle image that contains the ClusterServiceVersion (CSV), CRD and OLM metadata used to install the operator via OLM.

The build logic is orchestrated primarily through:

- `Makefile`
- Scripts under `hack/` (notably `go-build.sh`, `go-build-bundle.sh`, `go-sdk-gen.sh`, `go-csv.sh`, `go-mod-env.sh` plus helpers)
- The CSV generator in `tools/csv-gen/csv-gen.go`
- Container build descriptors `build/Dockerfile`, `image-prod.yaml` and `image-bundle.yaml`
- The pre generated OLM catalogs under `deploy/olm-catalog/{dev,test,prod}/<version>/...`

The build toolchain, as documented in `README.md`, expects at least:

- Go 1.17
- `operator-sdk` v0.19.2
- A container runtime (podman, docker or buildah)
- `cekit` for RHEL and bundle images
- `opm` for building index images on top of the bundle

---

## 2. Makefile entry points

The `Makefile` is the top level entry for building both the operator image and the bundle image.

### 2.1 Default build

Relevant targets:

- `all`
  - Defined as `all: build`, so `make` alone runs the `build` target.
- `build`
  - Runs `./hack/go-build.sh ${BUILDER}`.
  - `BUILDER` defaults to `podman` (`BUILDER ?= podman`). In the current scripts this value is only used for the cekit based RHEL builds (see later); the normal community image build path using `operator-sdk build` does not use it directly.

### 2.2 Bundle image targets

The following targets all delegate to `hack/go-build-bundle.sh` with different environment flags:

- `bundle`
  - Sets `LOCAL=true` and runs `./hack/go-build-bundle.sh ${BUILDER}`.
  - Builds a local bundle image using `cekit`, embedding the CSV, CRD and annotations as artifacts.
- `bundle-scratch`
  - Runs `./hack/go-build-bundle.sh ${BUILDER}` without setting `LOCAL`.
  - Causes `go-build-bundle.sh` to treat this as an OSBS style build rather than a purely local bundle build.
- `bundle-release`
  - Runs `./hack/go-build-bundle.sh ${BUILDER} release`.
  - Same as `bundle-scratch` but passes an extra `release` argument, which in the script causes additional cekit flags suitable for release builds.
- `bundle-dev`
  - Sets `DEV=true LOCAL=true` and runs `./hack/go-build-bundle.sh ${BUILDER}`.
  - Builds a development bundle image using the `dev` OLM catalog and tagging the image under the user Quay namespace.

### 2.3 RHEL operator image targets

These targets also use `hack/go-build.sh`, but in RHEL or OSBS oriented mode:

- `rhel`
  - Runs `LOCAL=true ./hack/go-build.sh ${BUILDER} rhel`.
- `rhel-scratch`
  - Runs `./hack/go-build.sh rhel` (here `rhel` is passed as the first argument to the script).
- `rhel-release`
  - Runs `./hack/go-build.sh ${BUILDER} rhel release`.
- `rhel-nightly`
  - Runs `./hack/go-build.sh ${BUILDER} rhel nightly $(build_user)`.
  - Used by `hack/build-osbs.sh` to run nightly OSBS builds.

### 2.4 CSV and SDK generation targets

- `sdk-generate`
  - Runs `./hack/go-sdk-gen.sh`.
  - Uses `operator-sdk generate` to regenerate Go types and CRDs and to lay out the base OLM catalog tree.
- `csv`
  - Declared as `csv: sdk-generate`, so it always regenerates SDK artefacts first.
  - Then runs `./hack/go-csv.sh`, which generates CSVs for dev, test and prod and validates them as OLM bundles.

---

## 3. Common Go build environment and helpers

Several helper scripts ensure the Go environment and code generation are in a consistent state before any image build.

### 3.1 `hack/go-mod-env.sh`

This script is sourced by most other `hack/*.sh` scripts and:

- Sets `GOFLAGS=-mod=vendor` so Go always uses the vendored dependencies.
- Detects whether the repo lives under `GOPATH` and, if so, sets `GO111MODULE=on`.

### 3.2 `hack/go-mod.sh`

- Sources `go-mod-env.sh`.
- Prints a reset message, then runs `go mod tidy` and `go mod vendor` to refresh both `go.mod`/`go.sum` and the `vendor` tree.
- In CI (when env `CI` is set) it enforces a clean vendor tree via `git diff --exit-code`.

### 3.3 `hack/go-fmt.sh` and `hack/go-vet.sh`

- `go-fmt.sh`:
  - Runs `gofmt -s -l -w` over `cmd/`, `pkg/`, `version/` and `tools/`.
  - In CI it enforces that no formatting changes are pending (`git diff --exit-code`).
- `go-vet.sh`:
  - Sources `go-mod-env.sh`.
  - If not running in CI:
    - Calls `go-mod.sh` to refresh modules and vendor.
    - Calls `go-sdk-gen.sh` to regenerate SDK types, CRDs and OLM layout.
  - Then runs `go vet ./...`.

### 3.4 `hack/go-test.sh`

- Sources `go-mod-env.sh`.
- If not in CI:
  - Runs `go-vet.sh` (which in turn may run `go-mod` and `go-sdk-gen`).
  - Runs `go-fmt.sh`.
- Finally runs `go test -count=1 ./...` (disabling test result caching).

A normal `make build` will therefore format, vet, update modules, regenerate SDK artefacts and run tests before it compiles binaries or builds container images.

---

## 4. Operator runtime image build

The runtime operator image can be built in two ways:

1. Local or community image using `operator-sdk build` and `build/Dockerfile`.
2. RHEL and OSBS images using `cekit` and `image-prod.yaml`.

### 4.1 Script `hack/go-build.sh`

This script is the core of all operator image builds. Its flow is:

1. Environment and metadata setup

   - Sources `hack/go-mod-env.sh`.
   - Defines:
     - `REPO=https://github.com/kiegroup/kie-cloud-operator`.
     - `PRODUCT_VERSION=$(go run getversion.go)`.
     - `OPERATOR_VERSION=$(go run getversion.go -csv)`.
     - `REGISTRY=quay.io/kiegroup`.
     - `IMAGE=kie-cloud-operator`.
     - `TAR=modules/builder/${IMAGE}.tar.gz`.
   - Prepares URLs used for OSBS or release tarballs:
     - `URL=${REPO}/archive/${OPERATOR_VERSION}.tar.gz`.
     - If `BRANCH_NIGHTLY` is not set it defaults to `release-v7.13.x-blue`.
     - `URL_NIGHTLY=${REPO}/tarball/${BRANCH_NIGHTLY}`.
   - Captures the first argument as `CFLAGS`, for later use with cekit in RHEL mode.

2. Tests and code generation

   - If the environment variable `CI` is not set:
     - Runs `./hack/go-test.sh`, which in turn:
       - Optionally runs `go-vet.sh` and `go-fmt.sh`.
       - Executes `go test ./...`.
   - Independently of CI, runs `./hack/go-gen.sh` which does `go generate -mod=vendor ./...`.

3. Selecting the build mode

   - If either `CI` is unset or `CEKIT_OSBS_BUILD` is set, the script proceeds to build container images.
   - Otherwise (in CI without `CEKIT_OSBS_BUILD`) it only compiles the binaries without building an image.

   The container image build path has two sub cases:

   #### 4.1.1 RHEL and OSBS builds (second argument `rhel`)

   When the second argument to the script equals `rhel` the script enters a RHEL specific path:

   - If `LOCAL` is not true (OSBS oriented builds):
     - Resets `CFLAGS` to `osbs`.
     - If the third argument equals `release`:
       - Appends `--release` to `CFLAGS`.
       - Downloads the source tarball for the specific operator version using `wget ${URL} -O ${TAR}`.
     - If the third argument equals `nightly`:
       - Sets `OVERRIDE_IMG_DESCRIPTOR` to `--descriptor image-prod.yaml`, which instructs cekit to use `image-prod.yaml` instead of some default descriptor.
     - If `CEKIT_RESPOND_YES` is set, appends `-y` to `CFLAGS` to auto answer prompts.
   - Sets an optional OSBS user: `OSBS_USER=--user ${4}` when a fourth argument is present.
   - Runs the cekit build:
     - `cekit --verbose --redhat ${OVERRIDE_IMG_DESCRIPTOR} build --overrides '{version: PRODUCT_VERSION}' ${CFLAGS} ${OSBS_USER}` (simplified for description).
   - After the build, if `${TAR}` exists, removes it to clean up.

   In this mode the actual image composition is defined by `image-prod.yaml` (see section 4.3).

   #### 4.1.2 Community or local image build (non RHEL)

   If the second argument is not `rhel`, the script uses `operator-sdk build`:

   - Builds the auxiliary UI binary first:
     - `CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -v -mod=vendor -a -o build/_output/bin/console-cr-form ./cmd/ui`.
   - Then calls `operator-sdk build`:
     - `operator-sdk build --go-build-args -mod=vendor ${REGISTRY}/${IMAGE}:${PRODUCT_VERSION}`.
   - `operator-sdk build` uses the local `build/Dockerfile` to assemble the final runtime image.

   #### 4.1.3 CI only binary build

   If running in CI and `CEKIT_OSBS_BUILD` is not set, no container images are built. Instead the script only compiles the Go binaries:

   - `CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build ... ./cmd/ui`.
   - `CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build ... ./cmd/manager`.

   These binaries land under `build/_output/bin/` and can be re used by other tooling or image definitions.

### 4.2 Runtime Dockerfile `build/Dockerfile`

The `build/Dockerfile` used by `operator-sdk build` is minimal:

```Dockerfile
FROM registry.redhat.io/ubi8-minimal

# install operator binary
COPY build/_output/bin/kie-cloud-operator /usr/local/bin/kie-cloud-operator
COPY build/_output/bin/console-cr-form /usr/local/bin/console-cr-form

USER 1001
```

Key points:

- Uses `ubi8-minimal` as base image.
- Copies both the operator and console binaries from `build/_output/bin`.
- Runs under non root user id 1001.

### 4.3 RHEL and OSBS image descriptor `image-prod.yaml`

For RHEL based images and OSBS builds the image definition comes from `image-prod.yaml`. It contains two descriptors:

1. A builder image descriptor named `builder`:
   - Base image `registry.redhat.io/ubi8/go-toolset:1.23.9`.
   - Configures `osbs.remote_source` to fetch this repository from GitHub at a specific commit referenced by `ref`.
   - Declares `gomod` as the package manager and restricts platforms to `x86_64`.

2. The runtime operator image descriptor `ibm-bamoe/bamoe-rhel8-operator`:
   - Base image `ubi8-minimal`.
   - Sets labels such as `com.redhat.component`, `io.k8s.display-name`, `io.openshift.tags` and others required by Red Hat productization.
   - Uses a module named `runtime` (from `modules/runtime`) to install the built operator binary into the final image.
   - Configures OSBS repository metadata under `osbs.repository` for `containers/ibm-bamoe-operator` and branch `ibm-bamoe-rhel-8`.
   - Configures the container to run as user 1001.

`hack/build-osbs.sh` modifies the `ref` and branch fields in this descriptor for nightly builds, sets OSBS related environment variables and finally runs `make rhel-nightly` which triggers `hack/go-build.sh` in the appropriate OSBS mode.

---

## 5. OLM catalog and CSV generation

Before building the bundle image, the OLM artefacts (CRD, CSV and metadata) must exist under `deploy/olm-catalog` for each supported environment and version.

### 5.1 Script `hack/go-sdk-gen.sh`

This script ties together operator sdk code generation and initial OLM catalog layout:

1. Sources `go-mod-env.sh` so Go module flags are consistent.
2. Runs operator sdk generators:
   - `operator-sdk generate k8s`.
   - `operator-sdk generate crds`.
3. Normalises the CRD filename:
   - Moves `deploy/crds/app.kiegroup.org_kieapps_crd.yaml` to `deploy/crds/kieapp.crd.yaml`.
4. Prepares OLM directory structure for the current CSV version:
   - Gets `CSVVERSION=$(go run getversion.go -csv)`.
   - For each of `dev`, `test` and `prod`:
     - Creates `deploy/olm-catalog/<env>/<CSVVERSION>/manifests`.
     - Copies `deploy/crds/kieapp.crd.yaml` into the `manifests` directory.

After this step each environment and version directory has the CRD present but not yet the CSV or the bundle metadata.

### 5.2 CSV generator `tools/csv-gen/csv-gen.go`

`hack/go-csv.sh` invokes this Go program to generate the CSVs and related OLM assets.

The generator imports:

- API types from `pkg/apis/app/v2`.
- Controller constants and defaults from `pkg/controller/kieapp/constants` and `pkg/controller/kieapp/defaults`.
- A set of helper functions from `pkg/components` to build the Deployment and RBAC resources.
- Version information from the `version` package.
- Operator SDK and OLM APIs from the `github.com/operator-framework/api` and `github.com/operator-framework/operator-sdk` packages.

#### 5.2.1 CSV settings for environments

The generator defines a slice of `csvSetting` values, one per logical environment:

- Dev setting:
  - Display name `IBM Business Automation (DEV)`.
  - Uses `quay.io` and the `kiegroup` organisation.
  - Image name `kie-cloud-operator` with tag equal to the current version.
  - Marked with maturity `dev` and a `Dev` flag set to true.
- Test setting:
  - Display name `IBM Business Automation`.
  - Uses internal brew registry and context from constants.
  - Image name derived from version, such as `bamoe-<major>-rhpam-rhel8-operator`.
  - Maturity `test`.
- Prod or channel setting:
  - Display name `IBM Business Automation`.
  - Uses staging or production registry and context from constants.
  - Image name based on the IBM BAMOE image prefix with `-rhel8-operator` suffix.
  - Maturity set to the stable channel, for example `8.x-stable`.

Each CSV produced by the generator shares the same logical operator package name but points at different image locations and maturity channels.

#### 5.2.2 CSV contents

For each `csvSetting` the generator builds a complete `ClusterServiceVersion` object:

1. Deployment spec

   - Calls `components.GetDeployment` to build the operator `Deployment` with the correct image reference and pull policy.
   - Wraps this into a `StrategyDetailsDeployment` and stores it under `Spec.InstallStrategy`.

2. RBAC

   - Uses `components.GetRole` and `components.GetClusterRole` to obtain the appropriate RBAC rules for the operator.
   - Adds them as `Permissions` (namespaced) and `ClusterPermissions` in the CSV install strategy.
   - Also writes separate YAML resource files for reuse:
     - `deploy/role.yaml`.
     - `deploy/cluster_role.yaml`.
     - `deploy/cluster_role_binding.yaml`.
     - `deploy/role_binding.yaml`.
     - `deploy/service_account.yaml`.

3. Security context

   - Ensures the deployment created by the CSV uses a restricted security context:
     - Pod `RunAsNonRoot` set to true.
     - Container `RunAsNonRoot` true, `AllowPrivilegeEscalation` false, `Privileged` false.
     - Drops all Linux capabilities.

4. Metadata and annotations

   - Constructs a versioned CSV name by combining the operator package name and the CSV version.
   - For dev maturity builds adds a random build suffix in the semantic version metadata to distinguish development bundles.
   - Sets CSV labels and annotations including:
     - Human readable description, repository URL and keywords.
     - Provider and maintainer entries.
     - Links to product page and documentation.
     - Multiple OpenShift feature flags indicating support for disconnected environments, FIPS, proxy awareness, TLS profiles and token authentication (these are currently set to specific true or false values).
   - Sets `Spec.Replaces` to the previous CSV version based on the `version` package.
   - Populates `Spec.DisplayName`, `Spec.Maturity`, `Spec.Provider`, `Spec.Links`, `Spec.Maintainers` and `Spec.Icon`.
   - Defines `Spec.Labels`, `Spec.Selector` and `Spec.InstallModes` for various namespace scopes.
   - Populates `Spec.CustomResourceDefinitions.Owned` to describe the `KieApp` CRD, including the kinds of resources created by the operator (DeploymentConfig, StatefulSet, Role, RoleBinding, Route, BuildConfig, ImageStream, Secret, PVC, ServiceAccount, Service).
   - Adds `SpecDescriptors` and `StatusDescriptors` that drive how spec and status fields appear in the OLM UI, including fields like `upgrades.enabled`, `useImageTags`, `environment`, `version`, `phase`, console URL and deployment statuses.

5. Bundle directory selection

   - For each CSV setting, chooses `bundleDir` based on maturity:
     - Prod: `deploy/olm-catalog/prod/<version>/`.
     - Dev: `deploy/olm-catalog/dev/<version>/`.
     - Test: `deploy/olm-catalog/test/<version>/`.
   - For dev builds, may also write a `deploy/operator.yaml` suitable for manual deployment.

6. Writing CSV and annotations

   - Serialises the CSV into the `manifests` directory under the chosen `bundleDir` with filename `bamoe-businessautomation-operator.clusterserviceversion.yaml`.
   - Creates an `annotations.yaml` structure containing keys such as:
     - `operators.operatorframework.io.bundle.channel.default.v1`.
     - `operators.operatorframework.io.bundle.channels.v1`.
     - `operators.operatorframework.io.bundle.manifests.v1`.
     - `operators.operatorframework.io.bundle.mediatype.v1`.
     - `operators.operatorframework.io.bundle.metadata.v1`.
     - `operators.operatorframework.io.bundle.package.v1`.
     - `operators.operatorframework.io.metrics.*` keys describing builder and project layout.
   - Writes this to `metadata/annotations.yaml` under `bundleDir`.

7. Additional snippets

   - Generates a `prior-version` `KieApp` custom resource snippet and writes it under `deploy/crs/v2/snippets/prior_version.yaml`, trimming runtime only fields and setting `spec.version` to the prior product version from constants.

### 5.3 Script `hack/go-csv.sh`

This is a thin wrapper around the CSV generator and bundle validation:

1. Sources `go-mod-env.sh`.
2. Computes `VERSION=$(go run getversion.go -csv)`.
3. Runs the CSV generator:
   - `go run ./tools/csv-gen/csv-gen.go`.
4. Validates the generated bundles using `operator-sdk bundle validate` for each environment path:
   - `deploy/olm-catalog/dev/${VERSION}`.
   - `deploy/olm-catalog/test/${VERSION}`.
   - `deploy/olm-catalog/prod/${VERSION}`.

When `make csv` is invoked, `sdk-generate` runs first to refresh the CRD and directory layout, followed by `go-csv.sh` to create and validate CSVs and metadata.

---

## 6. Operator bundle image build

The bundle image wraps the OLM catalog content into a container that can be consumed by an index image and ultimately by OLM catalog sources.

### 6.1 Bundle descriptor `image-bundle.yaml`

`image-bundle.yaml` is the cekit descriptor for the bundle image. It defines:

- `schema_version: 1`.
- `name: ibm-bamoe/bamoe-operator-bundle`.
- A description indicating that this is the IBM BAMOE Operator Bundle.
- `from: scratch` as the base image, which is common for bundle images.
- A set of labels including:
  - `operators.operatorframework.io.bundle.mediatype.v1: registry+v1`.
  - `operators.operatorframework.io.bundle.manifests.v1: manifests/`.
  - `operators.operatorframework.io.bundle.metadata.v1: metadata/`.
  - `operators.operatorframework.io.bundle.package.v1: bamoe-businessautomation-operator`.
  - `operators.operatorframework.io.bundle.channels.v1: 8.x-stable`.
  - `operators.operatorframework.io.bundle.channel.default.v1: 8.x-stable`.
  - Metrics labels that describe the builder (operator sdk) and project layout.
  - Red Hat delivery labels such as `com.redhat.delivery.operator.bundle` and the supported OpenShift versions.

The actual CSV, CRD and annotations are injected either via OSBS `extra_dir` configuration or via explicit `artifacts` overrides, which are set up by `hack/go-build-bundle.sh`.

### 6.2 Script `hack/go-build-bundle.sh`

This script orchestrates building the bundle image using cekit.

#### 6.2.1 Inputs and flags

- Sources `go-mod-env.sh`.
- Prompts for `USERNAME` (Quay account name) if it is not set in the environment.
- Sets:
  - `BUNDLE=rhpam-operator-bundle`.
  - `BUNDLE_NAME=rhpam-7/${BUNDLE}` by default.
  - `VERSION=$(go run getversion.go)`.
  - `CSVVERSION=$(go run getversion.go -csv)`.
- Initialises `CFLAGS` as the first script argument plus `--no-squash` (intended to pass through builder or engine flags).
- If `LOCAL` is not true (OSBS oriented build):
  - Resets `CFLAGS` to `osbs`.
  - If the second argument equals `release`, appends `--release` to `CFLAGS`.

The practical effect is that for local bundle builds (where `LOCAL=true` is set by the Makefile), the original first argument is preserved and used as cekit flags; while for OSBS builds the script forces cekit to run in `osbs` mode.

#### 6.2.2 Environment selection (dev versus prod)

- Sets `OLMDIR=deploy/olm-catalog/prod` by default.
- Uses `CSV=bamoe-businessautomation-operator.clusterserviceversion.yaml` as the CSV filename.
- If `DEV=true` is set (as in `make bundle-dev`):
  - Switches `OLMDIR` to `deploy/olm-catalog/dev`.
  - Changes `BUNDLE_NAME` to `quay.io/${USERNAME}/${BUNDLE}`, so the image is tagged under the user Quay account.

The target version directory is then:

- `VERDIR=${OLMDIR}/${CSVVERSION}`.

From there the script defines:

- `MANIFEST_DIR=${VERDIR}/manifests`.
- `CSV_PATH=${MANIFEST_DIR}/${CSV}`.
- `CRD_PATH=${MANIFEST_DIR}/kieapp.crd.yaml`.
- `ANNO_PATH=${VERDIR}/metadata/annotations.yaml`.

These files are expected to exist and be up to date; they are produced by the SDK and CSV generation steps described in section 5.

#### 6.2.3 MD5 and cekit cache

For each of CSV, CRD and annotations the script:

- Computes an MD5 sum (using `md5` on macOS or `md5sum` on Linux).
- Registers the file in the cekit cache via `cekit-cache add --md5 ...`.

This allows cekit to reuse downloaded artefacts and to validate them by checksum.

#### 6.2.4 OSBS versus local bundle builds

There are two main build branches.

1. OSBS or Red Hat bundle build (when `LOCAL` is not true):

   - Calls cekit with `--descriptor image-bundle.yaml --redhat build` and a set of overrides that:
     - Set `name` to `BUNDLE_NAME` (for example `rhpam-7/rhpam-operator-bundle`).
     - Set `version` to `VERSION`.
     - Define an `osbs` block that:
       - Points `extra_dir` to `VERDIR/`, which contains the versioned `manifests/` and `metadata/` directories.
       - Uses `extra_dir_target` of `/` to copy those into the image root.
       - Configures `operator_manifests.manifests_dir` as `VERDIR/manifests` so OSBS tooling knows where to find CSV and CRD.
       - Restricts `platforms` to `x86_64`.
       - Sets the dist git repository and branch for the bundle under `repository.name` and `repository.branch`.

   - The result is an OSBS ready bundle image that has its manifests and metadata at the correct locations, plus the labels defined in `image-bundle.yaml`.

2. Local or developer bundle build (when `LOCAL=true`):

   - Calls cekit with the same descriptor but instead of the `osbs` block uses an `artifacts` override that:
     - Lists the CSV file as an artifact with destination `/manifests/` and its MD5.
     - Lists the CRD file similarly under `/manifests/`.
     - Lists `annotations.yaml` as an artifact with destination `/metadata/`.

   - This produces a local bundle image which contains exactly the OLM assets for the specified `CSVVERSION` under the expected directories. It is suitable for direct use with OLM and for building index images using `opm`.

### 6.3 Makefile bundle targets in practice

Putting it together with the Makefile:

- `make bundle-dev`:
  - Sets `DEV=true LOCAL=true` and runs `go-build-bundle.sh`.
  - Uses the `dev` OLM catalog at `deploy/olm-catalog/dev/<CSVVERSION>/`.
  - Builds a local bundle image tagged under `quay.io/<USERNAME>/rhpam-operator-bundle:<VERSION>` (and usually also as `latest`).
- `make bundle`:
  - Uses the `prod` OLM catalog and also sets `LOCAL=true`.
  - Produces a local bundle image based on production CSV and metadata.
- `make bundle-release` and `make bundle-scratch`:
  - Run `go-build-bundle.sh` without `LOCAL=true`, pushing the build down the OSBS or cekit `osbs` path for downstream product builds.

---

## 7. End to end examples

### 7.1 Local or community operator image

1. Ensure prerequisites (Go, operator sdk, container runtime) are installed.
2. Run `make` or `make build`.
3. The build will:
   - Format, vet and test the code.
   - Refresh modules and vendor tree when not in CI.
   - Regenerate SDK types and CRDs.
   - Run `go generate` over the repo.
   - Build the `console-cr-form` binary.
   - Call `operator-sdk build` to create an image like `quay.io/kiegroup/kie-cloud-operator:<PRODUCT_VERSION>` using `build/Dockerfile`.
4. Optionally tag and push the image to a personal registry as shown in `README.md`.

### 7.2 Local development bundle and index

1. Make sure the OLM content is up to date:
   - Run `make csv` to regenerate CRDs, CSVs and annotations and validate them.
2. Export Quay username:
   - `export USERNAME=<your-registry-id>`.
3. Build the dev bundle image:
   - Run `make bundle-dev`.
   - This uses the `dev` OLM catalog and builds `quay.io/${USERNAME}/rhpam-operator-bundle:<VERSION>`.
4. Push the bundle image to Quay.
5. Build an index image using `opm index add` and push it.
6. Create a `CatalogSource` in OpenShift that points to the index image and a `Subscription` that tracks the appropriate channel, as documented in `README.md`.

### 7.3 RHEL and OSBS operator image and bundle

For downstream or productised builds:

- Operator image:
  - Use `make rhel`, `make rhel-release` or `make rhel-nightly` depending on the desired target.
  - For nightly OSBS builds, use `hack/build-osbs.sh` which:
    - Sets OSBS related environment variables and options.
    - Updates `image-prod.yaml` to reference the correct commit and nightly branch.
    - Calls `make rhel-nightly` with the OSBS build user.
- Bundle image:
  - Use `make bundle-release` or an OSBS oriented invocation of `hack/go-build-bundle.sh`.
  - These builds rely on the `osbs.extra_dir` configuration in `go-build-bundle.sh` to supply bundle manifests and metadata to OSBS.

---

## 8. Summary

In summary, this repository organises the operator and bundle build as follows:

- The operator image is built by `hack/go-build.sh`, which:
  - Normalises Go modules and vendor behaviour.
  - Formats, vets and tests the code.
  - Regenerates SDK artefacts and any generated Go code.
  - Either calls `operator-sdk build` to produce a community image using `build/Dockerfile`, or drives `cekit` with descriptors such as `image-prod.yaml` for RHEL and OSBS builds.
- The OLM catalogue is generated by the combination of:
  - `hack/go-sdk-gen.sh` (CRDs and initial OLM directory scaffolding).
  - `tools/csv-gen/csv-gen.go` (CSV content, annotations and RBAC YAML).
  - `hack/go-csv.sh` (wrapper plus `operator-sdk bundle validate` for dev, test and prod variants).
- The operator bundle image is created by `hack/go-build-bundle.sh` using `image-bundle.yaml`, which:
  - Selects the correct `deploy/olm-catalog/{dev,test,prod}/<CSVVERSION>` directory.
  - Injects CSV, CRD and annotations into the image either via OSBS `extra_dir` or via explicit `artifacts`.
  - Ensures the final image exposes the correct OLM labels and metadata required by OpenShift and Red Hat tooling.

The Makefile ties everything together with simple `build`, `rhel*`, `csv` and `bundle*` targets, allowing day to day workflows to use short `make` commands while still supporting more complex RHEL, OSBS and OLM publishing pipelines documented in `README.md`.
