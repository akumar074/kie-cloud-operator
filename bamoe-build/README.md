# BAMOE Custom Images Build Scripts

This package contains Docker configurations and build scripts for creating custom BAMOE images with updated JAR files.

## Contents

1. **Dockerfile** - KIE Server image configuration
2. **Dockerfile.businesscentral** - Business Central image configuration
3. **build-push-kie-server.sh** - Build script for KIE Server
4. **build-push-businesscentral.sh** - Build script for Business Central
5. **build-push-all.sh** - Combined build script for both images

## Prerequisites

### Required JAR Files

**For KIE Server (4 JARs):**
1. `kie-server-services-openshift-7.67.2.Final-redhat-00045.jar`
   - Location: `/home/abkuma/Workspace/droolsjbpm-integration/kie-server-parent/kie-server-services/kie-server-services-openshift/target/`
2. `kie-server-controller-openshift-7.67.2.Final-redhat-00045.jar`
   - Location: `$HOME/.m2/repository/org/kie/server/kie-server-controller-openshift/7.67.2.Final-redhat-00045/`
3. `drools-core-7.67.2.Final-redhat-00045.jar`
   - Location: `$HOME/.m2/repository/org/drools/drools-core/7.67.2.Final-redhat-00045/`
4. `drools-serialization-protobuf-7.67.2.Final-redhat-00045.jar`
   - Location: `$HOME/.m2/repository/org/drools/drools-serialization-protobuf/7.67.2.Final-redhat-00045/`

**For Business Central (3 JARs):**
1. `kie-server-controller-openshift-7.67.2.Final-redhat-00045.jar`
2. `drools-core-7.67.2.Final-redhat-00045.jar`
3. `drools-serialization-protobuf-7.67.2.Final-redhat-00045.jar`

All three from Maven repository locations listed above.

## Setup Instructions

1. **Extract the zip file:**
   ```bash
   unzip bamoe-custom-images.zip -d bamoe-build
   cd bamoe-build
   ```

2. **Make scripts executable:**
   ```bash
   chmod +x build-push-kie-server.sh
   chmod +x build-push-businesscentral.sh
   chmod +x build-push-all.sh
   ```

3. **Ensure all required JAR files are built and available in their respective locations**

4. **Login to Quay.io:**
   ```bash
   docker login quay.io
   ```

## Usage

### Build Both Images
```bash
./build-push-all.sh
```

### Build Individual Images

**KIE Server only:**
```bash
./build-push-kie-server.sh
```

**Business Central only:**
```bash
./build-push-businesscentral.sh
```

## Output Images

- **KIE Server:** `quay.io/abkuma/bamoe-kieserver-rhel9:8.0.9`
- **Business Central:** `quay.io/abkuma/bamoe-businesscentral-rhel9:8.0.9`

## Troubleshooting

### "Dockerfile.businesscentral: no such file or directory"
- Ensure you extracted all files from the zip to the same directory
- Verify the file exists: `ls -la Dockerfile.businesscentral`
- Make sure you're running the script from the directory containing all files

### "JAR file not found"
- Build the required Maven projects first
- Check that JAR files exist in the specified locations
- Verify Maven repository path: `echo $HOME/.m2/repository`

### "Docker build failed"
- Ensure Docker is running
- Check that base images are accessible
- Verify you have sufficient disk space

### "Docker push failed"
- Login to Quay.io: `docker login quay.io`
- Verify you have push permissions to the repository
- Check your network connection

## Notes

- All scripts include validation to check for required JAR files before building
- Build artifacts are automatically cleaned up after successful builds
- Scripts will stop on first error to prevent partial builds
