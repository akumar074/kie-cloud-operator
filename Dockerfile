FROM quay.io/r_anand/bamoe-kieserver-rhel9:8.0.9

# Remove the old JAR file
RUN rm -f /deployments/ROOT.war/WEB-INF/lib/kie-server-services-openshift-7.67.2.Final-redhat-00045.jar

# Copy the updated JAR file (relative to build context)
COPY kie-server-services-openshift-7.67.2.Final-redhat-00045.jar /deployments/ROOT.war/WEB-INF/lib/kie-server-services-openshift-7.67.2.Final-redhat-00045.jar

# Switch to 'root' user and remove artifacts and modules
USER root
RUN [ ! -d /tmp/scripts ] || rm -rf /tmp/scripts
RUN [ ! -d /tmp/artifacts ] || rm -rf /tmp/artifacts

# Clear package manager metadata
RUN microdnf clean all && [ ! -d /var/cache/yum ] || rm -rf /var/cache/yum

# Define the user
USER 185

# Define the working directory
WORKDIR /home/jboss

# Define run cmd
CMD ["/opt/eap/bin/openshift-launch.sh"]