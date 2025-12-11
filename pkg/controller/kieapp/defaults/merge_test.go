package defaults

import (
	"testing"

	"github.com/ghodss/yaml"
	api "github.com/kiegroup/kie-cloud-operator/pkg/apis/app/v2"
	"github.com/kiegroup/kie-cloud-operator/pkg/controller/kieapp/test"
	"github.com/stretchr/testify/assert"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/intstr"
)

func TestMergeServices(t *testing.T) {
	baseline, err := getEnvironment("rhpam-trial", "test")
	assert.Nil(t, err)
	overwrite := baseline.DeepCopy()

	service1 := baseline.Console.Services[0]
	service1.Labels["source"] = "baseline"
	service1.Labels["baseline"] = "true"
	service2 := service1.DeepCopy()
	service2.Name = service1.Name + "-2"
	baseline.Console.Services = append(baseline.Console.Services, *service2)

	service1b := overwrite.Console.Services[0]
	service1b.Labels["source"] = "overwrite"
	service1b.Labels["overwrite"] = "true"
	service3 := service1b.DeepCopy()
	service3.Name = service1b.Name + "-3"
	service5 := service1b.DeepCopy()
	service5.Name = service1b.Name + "-4"
	annotations := service5.Annotations
	if annotations == nil {
		annotations = make(map[string]string)
		service5.Annotations = annotations
	}
	service5.Annotations["delete"] = "true"
	overwrite.Console.Services = append(overwrite.Console.Services, *service3)
	overwrite.Console.Services = append(overwrite.Console.Services, *service5)

	mergedEnv, _ := merge(baseline, *overwrite)
	assert.Equal(t, 3, len(mergedEnv.Console.Services), "Expected 3 services")
	finalService1 := mergedEnv.Console.Services[0]
	// ping service
	finalService3 := mergedEnv.Console.Services[1]
	assert.Equal(t, "true", finalService1.Labels["baseline"], "Expected the baseline label to be set")
	assert.Equal(t, "true", finalService1.Labels["overwrite"], "Expected the overwrite label to also be set as part of the merge")
	assert.Equal(t, "overwrite", finalService1.Labels["source"], "Expected the source label to have been overwritten by merge")
	assert.Equal(t, "true", finalService3.Labels["baseline"], "Expected the baseline label to be set")
	assert.Equal(t, "baseline", finalService3.Labels["source"], "Expected the source label to be baseline")
	assert.Equal(t, "test-rhpamcentr-2", finalService3.Name, "Second service name should end with -2")
}

func TestMergeRoutes(t *testing.T) {
	baseline, err := getEnvironment("rhdm-trial", "test")
	assert.Nil(t, err)
	overwrite := baseline.DeepCopy()

	route1 := baseline.Console.Routes[0]
	route1.Labels["source"] = "baseline"
	route1.Labels["baseline"] = "true"
	route2 := route1.DeepCopy()
	route2.Name = route1.Name + "-2"
	route4 := route1.DeepCopy()
	route4.Name = route1.Name + "-4"
	baseline.Console.Routes = append(baseline.Console.Routes, *route2)
	baseline.Console.Routes = append(baseline.Console.Routes, *route4)

	route1b := overwrite.Console.Routes[0]
	route1b.Labels["source"] = "overwrite"
	route1b.Labels["overwrite"] = "true"
	route3 := route1b.DeepCopy()
	route3.Name = route1b.Name + "-3"
	route5 := route1b.DeepCopy()
	route5.Name = route1b.Name + "-4"
	annotations := route5.Annotations
	if annotations == nil {
		annotations = make(map[string]string)
		route5.Annotations = annotations
	}
	route5.Annotations["delete"] = "true"
	overwrite.Console.Routes = append(overwrite.Console.Routes, *route3)
	overwrite.Console.Routes = append(overwrite.Console.Routes, *route5)

	mergedEnv, err := merge(baseline, *overwrite)
	assert.Nil(t, err, "Error while merging environments")
	assert.Equal(t, 4, len(mergedEnv.Console.Routes), "Expected 4 routes.")
	finalRoute1 := mergedEnv.Console.Routes[0]
	finalRoute3 := mergedEnv.Console.Routes[2]
	finalRoute4 := mergedEnv.Console.Routes[3]
	assert.Equal(t, "true", finalRoute1.Labels["baseline"], "Expected the baseline label to be set")
	assert.Equal(t, "true", finalRoute1.Labels["overwrite"], "Expected the overwrite label to also be set as part of the merge")
	assert.Equal(t, "overwrite", finalRoute1.Labels["source"], "Expected the source label to have been overwritten by merge")
	assert.Equal(t, "true", finalRoute3.Labels["baseline"], "Expected the baseline label to be set")
	assert.Equal(t, "baseline", finalRoute3.Labels["source"], "Expected the source label to be baseline")
	assert.Equal(t, "true", finalRoute4.Labels["overwrite"], "Expected the baseline label to be set")
	assert.Equal(t, "true", finalRoute4.Labels["overwrite"], "Expected the overwrite label to be set")
	assert.Equal(t, "overwrite", finalRoute4.Labels["source"], "Expected the source label to be overwrite")
	assert.Equal(t, "test-rhdmcentr-2", finalRoute3.Name, "Second route name should end with -2")
	assert.Equal(t, "test-rhdmcentr-3", finalRoute4.Name, "Second route name should end with -3")
}

func getEnvironment(environment api.EnvironmentType, name string) (api.Environment, error) {
	cr := &api.KieApp{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name,
			Namespace: "test-ns",
		},
		Spec: api.KieAppSpec{
			Environment: environment,
		},
	}

	env, err := GetEnvironment(cr, test.MockService())
	if err != nil {
		return api.Environment{}, err
	}
	return env, nil
}

func TestMergeServerDeploymentConfigs(t *testing.T) {
	var dbEnv api.Environment
	err := getParsedTemplateWithDB("dbs/postgresql.yaml", "prod", &dbEnv)
	assert.Nil(t, err, "Error: %v", err)
	assert.Equal(t, appsv1.DeploymentStrategyTypeRecreate, dbEnv.Databases[0].Deployments[0].Spec.Strategy.Type)

	var prodEnv api.Environment
	err = getParsedTemplate("envs/rhpam-production.yaml", "prod", &prodEnv)
	assert.Nil(t, err, "Error: %v", err)

	var common api.Environment
	err = getParsedTemplate("common.yaml", "prod", &common)
	assert.Nil(t, err, "Error: %v", err)

	baseEnvCount := len(common.Servers[0].Deployments[0].Spec.Template.Spec.Containers[0].Env)
	prodEnvCount := len(prodEnv.Servers[0].Deployments[0].Spec.Template.Spec.Containers[0].Env)

	mergedDeployments := mergeDeployments(common.Servers[0].Deployments, prodEnv.Servers[0].Deployments)
	mergedDeployments = mergeDeployments(mergedDeployments, dbEnv.Databases[0].Deployments)

	assert.NotNil(t, mergedDeployments, "Must have encountered an error, merged Deployments should not be null")
	assert.Len(t, mergedDeployments, 2, "Expect 2 deployment descriptors but got %v", len(mergedDeployments))

	mergedEnvCount := len(mergedDeployments[0].Spec.Template.Spec.Containers[0].Env)
	assert.True(t, mergedEnvCount > baseEnvCount, "Merged Deployment should have a higher number of environment variables than the base server")
	assert.True(t, mergedEnvCount > prodEnvCount, "Merged Deployment should have a higher number of environment variables than the server")

	assert.Len(t, mergedDeployments[0].Spec.Template.Spec.Containers[0].Ports, 3, "Expecting 3 ports")

}

func TestMergeServerDeploymentConfigsWithJms(t *testing.T) {
	var dbEnv api.Environment
	err := getParsedTemplate("dbs/servers/h2.yaml", "immutable-prod", &dbEnv)
	assert.Nil(t, err, "Error: %v", err)

	var jmsEnv api.Environment
	err = getParsedTemplate("jms/activemq-jms-config.yaml", "immutable-prod", &jmsEnv)
	assert.Nil(t, err, "Error: %v", err)
	assert.Equal(t, jmsEnv.Servers[0].Deployments[1].Name, "immutable-prod-kieserver-amq")
	assert.Equal(t, appsv1.DeploymentStrategyTypeRollingUpdate, jmsEnv.Servers[0].Deployments[1].Spec.Strategy.Type)
	assert.Equal(t, &intstr.IntOrString{Type: 1, IntVal: 0, StrVal: "100%"}, jmsEnv.Servers[0].Deployments[1].Spec.Strategy.RollingUpdate.MaxSurge)

	var prodEnv api.Environment
	err = getParsedTemplate("envs/rhpam-production-immutable.yaml", "immutable-prod", &prodEnv)
	assert.Nil(t, err, "Error: %v", err)

	var common api.Environment
	err = getParsedTemplate("common.yaml", "immutable-prod", &common)
	assert.Nil(t, err, "Error: %v", err)

	baseEnvCount := len(common.Servers[0].Deployments[0].Spec.Template.Spec.Containers[0].Env)
	prodEnvCount := len(prodEnv.Servers[0].Deployments[0].Spec.Template.Spec.Containers[0].Env)

	mergedDeployments := mergeDeployments(common.Servers[0].Deployments, prodEnv.Servers[0].Deployments)
	mergedDeployments = mergeDeployments(mergedDeployments, dbEnv.Servers[0].Deployments)
	mergedDeployments = mergeDeployments(mergedDeployments, jmsEnv.Servers[0].Deployments)

	assert.NotNil(t, mergedDeployments, "Must have encountered an error, merged Deployments should not be null")
	assert.Len(t, mergedDeployments, 2, "Expect 2 deployment descriptors but got %v", len(mergedDeployments))

	mergedEnvCount := len(mergedDeployments[0].Spec.Template.Spec.Containers[0].Env)
	assert.True(t, mergedEnvCount > baseEnvCount, "Merged Deployment should have a higher number of environment variables than the base server")
	assert.True(t, mergedEnvCount > prodEnvCount, "Merged Deployment should have a higher number of environment variables than the server")

	assert.Len(t, mergedDeployments[0].Spec.Template.Spec.Containers[0].Ports, 3, "Expecting 3 ports")
}

func TestMergeConfigsWithoutOverrides(t *testing.T) {
	var authEnv api.Environment
	err := getParsedTemplate("envs/rhdm-authoring.yaml", "authoring", &authEnv)
	assert.Nil(t, err, "Error: %v", err)

	var common api.Environment
	err = getParsedTemplate("common.yaml", "authoring", &common)
	assert.Nil(t, err, "Error: %v", err)

	assert.Equal(t, 1, len(common.Servers))
	assert.Equal(t, 0, len(authEnv.Servers))

	merged, err := merge(common, authEnv)
	assert.Nil(t, err, "Error: %v", err)

	assert.Equal(t, merged.Servers, common.Servers)
}

func TestMergeConfigsWithoutBaseline(t *testing.T) {
	var authEnv api.Environment
	err := getParsedTemplate("envs/rhdm-authoring.yaml", "authoring", &authEnv)
	assert.Nil(t, err, "Error: %v", err)

	var common api.Environment
	err = getParsedTemplate("common.yaml", "authoring", &common)
	assert.Nil(t, err, "Error: %v", err)

	assert.Equal(t, 1, len(common.Servers))
	assert.Equal(t, 0, len(authEnv.Servers))

	//Use authEnv as baseline and common as overrides
	merged, err := merge(authEnv, common)
	assert.Nil(t, err, "Error: %v", err)

	assert.Equal(t, merged.Servers, common.Servers)
}

func TestMergeConsoleOmitted(t *testing.T) {
	var trialEnv api.Environment

	err := getParsedTemplate("envs/rhpam-trial.yaml", "test", &trialEnv)
	assert.Nil(t, err, "Error: %v", err)

	var common api.Environment
	err = getParsedTemplate("common.yaml", "test", &common)
	assert.Nil(t, err, "Error: %v", err)

	mergedEnv, err := merge(common, trialEnv)
	assert.Nil(t, err, "Error: %v", err)
	assert.False(t, mergedEnv.Console.Omit, "Console deployment must not be omitted")
}

func TestMergeBuildConfigandIStreams(t *testing.T) {
	cr := &api.KieApp{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "test",
			Namespace: "test-ns",
		},
		Spec: api.KieAppSpec{
			Environment: api.RhpamProductionImmutable,
			Objects: api.KieAppObjects{
				Servers: []api.KieServerSet{
					{
						Build: &api.KieAppBuildObject{
							KieServerContainerDeployment: "test",
							GitSource: api.GitSource{
								URI: "test-url",
							},
						},
					},
				},
			},
		},
	}
	var prodImmutableEnv api.Environment
	err := getParsedTemplateFromCR(cr, "envs/rhpam-production-immutable.yaml", &prodImmutableEnv)
	assert.Nil(t, err, "Error: %v", err)

	var common api.Environment
	err = getParsedTemplateFromCR(cr, "common.yaml", &common)
	assert.Nil(t, err, "Error: %v", err)

	mergedEnv, err := merge(common, prodImmutableEnv)
	assert.Nil(t, err, "Error: %v", err)
	server := mergedEnv.Servers[0]
	assert.Len(t, server.ImageStreams, 1)
	assert.Equal(t, "test-kieserver", server.ImageStreams[0].ObjectMeta.Name)
	assert.Equal(t, "test-kieserver", server.BuildConfigs[0].ObjectMeta.Name)
}

func TestMergeConfigMaps(t *testing.T) {
	baseline := []corev1.ConfigMap{
		*buildConfigMap("overwrite-cm2",
			map[string]string{
				"cm2-data-key-1": "cm2-data-value",
				"cm2-data-key-2": "cm2-data-value",
				"cm2-data-key-3": "cm2-data-value",
			},
			map[string][]byte{
				"cm2-binary-data-key": {1, 3, 5, 7, 9},
			},
		),
		*buildConfigMap("cm1",
			map[string]string{
				"cm1-data-key": "cm1-data-value",
			},
			map[string][]byte{
				"cm1-binary-data-key-1": {1, 2, 3, 4, 5},
				"cm1-binary-data-key-2": {1, 2, 3, 4, 5},
				"cm1-binary-data-key-3": {1, 2, 3, 4, 5},
			},
		),
	}

	overwrite := []corev1.ConfigMap{
		*buildConfigMap("overwrite-cm2",
			map[string]string{
				"cm2-data-key-1": "cm2-data-value",
				"cm2-data-key-2": "cm2-data-value-2",
				"cm2-data-key-4": "cm2-data-value-3",
			},
			map[string][]byte{
				"cm2-binary-data-key": {1, 3, 5, 7, 9},
			},
		),
		*buildConfigMap("cm1",
			map[string]string{
				"cm1-data-key": "cm1-data-value-overwrite",
			},
			map[string][]byte{
				"cm1-binary-data-key-1": {1, 2, 3, 4, 5},
				"cm1-binary-data-key-2": {6, 7, 8, 9, 0},
				"cm1-binary-data-key-4": {1, 2, 3, 4, 5},
			},
		),
	}
	results := mergeConfigMaps(baseline, overwrite)

	expected := []corev1.ConfigMap{
		*buildConfigMap("overwrite-cm2",
			map[string]string{
				"cm2-data-key-1": "cm2-data-value",
				"cm2-data-key-2": "cm2-data-value-2",
				"cm2-data-key-3": "cm2-data-value",
				"cm2-data-key-4": "cm2-data-value-3",
			},
			map[string][]byte{
				"cm2-binary-data-key": {1, 3, 5, 7, 9},
			},
		),
		*buildConfigMap("cm1",
			map[string]string{
				"cm1-data-key": "cm1-data-value-overwrite",
			},
			map[string][]byte{
				"cm1-binary-data-key-1": {1, 2, 3, 4, 5},
				"cm1-binary-data-key-2": {6, 7, 8, 9, 0},
				"cm1-binary-data-key-3": {1, 2, 3, 4, 5},
				"cm1-binary-data-key-4": {1, 2, 3, 4, 5},
			},
		),
	}

	assert.Equal(t, 2, len(results))
	assert.Equal(t, expected[0].Data, results[0].Data)
	assert.Equal(t, expected[0].BinaryData, results[0].BinaryData)
	assert.Equal(t, expected[1].Data, results[1].Data)
	assert.Equal(t, expected[1].BinaryData, results[1].BinaryData)
}

func getParsedTemplate(filename string, name string, object interface{}) error {
	cr := &api.KieApp{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name,
			Namespace: "test-ns",
		},
	}
	return getParsedTemplateFromCR(cr, filename, object)
}

func getParsedTemplateWithDB(filename string, name string, object interface{}) error {
	cr := &api.KieApp{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name,
			Namespace: "test-ns",
		},
		Spec: api.KieAppSpec{
			Environment: api.RhpamTrial,
			Objects: api.KieAppObjects{
				ProcessMigration: &api.ProcessMigrationObject{
					Database: api.ProcessMigrationDatabaseObject{
						InternalDatabaseObject: api.InternalDatabaseObject{
							Type: api.DatabasePostgreSQL,
						},
					},
				},
			},
		},
	}
	return getParsedTemplateFromCR(cr, filename, object)
}

func getParsedTemplateFromCR(cr *api.KieApp, filename string, object interface{}) error {
	envTemplate, err := getEnvTemplate(cr)
	if err != nil {
		log.Error("Error getting environment template", err)
	}

	yamlBytes, err := loadYaml(test.MockService(), filename, cr.Status.Applied.Version, cr.Namespace, envTemplate)
	if err != nil {
		return err
	}
	err = yaml.Unmarshal(yamlBytes, object)
	if err != nil {
		log.Error("Error unmarshalling yaml. ", err)
	}
	return nil
}

func buildObjectMeta(name string) *metav1.ObjectMeta {
	return &metav1.ObjectMeta{
		Name:      name,
		Namespace: name + "-ns",
		Labels: map[string]string{
			name + ".label1": name + "-labelValue1",
			name + ".label2": name + "-labelValue2",
		},
		Annotations: map[string]string{
			name + ".annotation1": name + "-annValue1",
			name + ".annotation2": name + "-annValue2",
		},
	}
}

func buildProbe(name string, delay, timeout int32) *corev1.Probe {
	return &corev1.Probe{
		ProbeHandler: corev1.ProbeHandler{
			Exec: &corev1.ExecAction{
				Command: []string{
					"/bin/" + name,
					"-c",
					name,
				},
			},
		},
		InitialDelaySeconds: delay,
		TimeoutSeconds:      timeout,
	}
}

func buildConfigMap(name string, data map[string]string, binaryData map[string][]byte) *corev1.ConfigMap {
	return &corev1.ConfigMap{
		ObjectMeta: *buildObjectMeta(name + "-cm"),
		Data:       data,
		BinaryData: binaryData,
	}
}
