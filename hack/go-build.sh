#!/usr/bin/env bash

set -e

source ./hack/go-mod-env.sh

REPO=https://github.com/kiegroup/kie-cloud-operator
PRODUCT_VERSION=$(go run getversion.go)
OPERATOR_VERSION=$(go run getversion.go -csv)
REGISTRY=quay.io/kiegroup
IMAGE=kie-cloud-operator
TAR=modules/builder/${IMAGE}.tar.gz
OVERRIDE_IMG_DESCRIPTOR=""

URL=${REPO}/archive/${OPERATOR_VERSION}.tar.gz
if [ -z ${BRANCH_NIGHTLY} ]; then
  BRANCH_NIGHTLY="release-v7.13.x-blue"
fi
URL_NIGHTLY=${REPO}/tarball/${BRANCH_NIGHTLY}

CFLAGS="${1}"

if [[ -z ${CI} ]]; then
    ./hack/go-test.sh
fi

./hack/go-gen.sh

if [[ -z ${CI} || -n ${CEKIT_OSBS_BUILD} ]]; then
    echo Now building operator:
    echo
    if [[ ${2} == "rhel" ]]; then
        if [[ ${LOCAL} != true ]]; then
            CFLAGS="osbs"
            if [[ ${3} == "release" ]]; then
                CFLAGS+=" --release"
                wget -q ${URL} -O ${TAR}
            fi
            if [[ ${3} == "nightly" ]]; then
              OVERRIDE_IMG_DESCRIPTOR=" --descriptor image-prod.yaml"
            fi
            if [[ ! -z ${CEKIT_RESPOND_YES+z} ]]; then
                    CFLAGS+=" -y"
            fi
        fi
        OSBS_USER="--user ${4}"
        set -x
        cekit --verbose --redhat ${OVERRIDE_IMG_DESCRIPTOR} build --overrides "{"version": "${PRODUCT_VERSION}"}"  ${CFLAGS} ${OSBS_USER}
        set +x

        if [[ -f ${TAR} ]]; then
          rm ${TAR}
        fi
    else
        echo
        echo Will build console and operator for multiple architectures:
        echo
        
        # Build for AMD64
        echo "Building for linux/amd64..."
        CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -v -mod=vendor -a -o build/_output/bin/console-cr-form-amd64 ./cmd/ui
        CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -v -mod=vendor -a -o build/_output/bin/kie-cloud-operator-amd64 ./cmd/manager
        
        # Build for ARM64
        echo "Building for linux/arm64..."
        CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -v -mod=vendor -a -o build/_output/bin/console-cr-form-arm64 ./cmd/ui
        CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -v -mod=vendor -a -o build/_output/bin/kie-cloud-operator-arm64 ./cmd/manager
        
        echo
        echo "Building multiplatform Docker image with buildx..."
        
        # Check if buildx is available
        if ! docker buildx version &> /dev/null; then
            echo "ERROR: Docker buildx is not available"
            echo "Please install Docker buildx or use Docker Desktop which includes it"
            exit 1
        fi
        
        # Create or use existing buildx builder
        BUILDER_NAME="multiarch-builder"
        if ! docker buildx inspect ${BUILDER_NAME} &> /dev/null; then
            echo "Creating new buildx builder: ${BUILDER_NAME}"
            docker buildx create --name ${BUILDER_NAME} --use --bootstrap
        else
            echo "Using existing buildx builder: ${BUILDER_NAME}"
            docker buildx use ${BUILDER_NAME}
        fi
        
        # Build multiplatform image
        docker buildx build \
            --platform linux/amd64,linux/arm64 \
            --tag ${REGISTRY}/${IMAGE}:${PRODUCT_VERSION} \
            --load \
            -f build/Dockerfile .
    fi
else
    # Build for AMD64
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -v -mod=vendor -a -o build/_output/bin/console-cr-form-amd64 ./cmd/ui
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -v -mod=vendor -a -o build/_output/bin/kie-cloud-operator-amd64 ./cmd/manager
    
    # Build for ARM64
    CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -v -mod=vendor -a -o build/_output/bin/console-cr-form-arm64 ./cmd/ui
    CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -v -mod=vendor -a -o build/_output/bin/kie-cloud-operator-arm64 ./cmd/manager
fi
