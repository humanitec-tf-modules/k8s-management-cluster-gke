# Verifies the inputs this module sets on the management-cluster-k8s module, and that variables are passed through.
#
# All providers are mocked, so these tests run without Google Cloud credentials, a Kubernetes cluster, or a Humanitec Organization.

mock_provider "google" {
  mock_data "google_client_config" {
    defaults = {
      project = "my-provider-project"
    }
  }
  mock_data "google_container_cluster" {
    defaults = {
      id = "projects/my-project/locations/europe-west3/clusters/my-gke"
    }
  }
  mock_data "google_service_account" {
    defaults = {
      unique_id = "123456789012345678901"
    }
  }
  mock_resource "google_project_iam_custom_role" {
    defaults = {
      name = "projects/my-project/roles/my-role"
    }
  }
}

mock_provider "random" {
  # The mocked result does not honor the length attribute
  mock_resource "random_string" {
    defaults = {
      result = "abcd"
    }
  }
}

mock_provider "kubernetes" {}
mock_provider "helm" {}
mock_provider "humanitec" {}
mock_provider "tls" {}

variables {
  gke_cluster_name                    = "my-gke"
  gke_location                        = "europe-west3"
  gke_project_id                      = "my-project"
  cloud_account_service_account_email = "humanitec-orchestrator@my-project.iam.gserviceaccount.com"
  cloud_account_id                    = "my-gcp-cloud-account"

  # terraform test sets the default of an ephemeral root variable only during apply, failing the apply. Set it explicitly
  helm_release_set_wo = []
}

run "sets_fixed_gke_inputs" {
  command = apply

  assert {
    condition     = module.management_cluster.resource_definition_driver_type == "humanitec/k8s-cluster-gke"
    error_message = "The Driver must be humanitec/k8s-cluster-gke"
  }

  assert {
    condition     = startswith(module.management_cluster.resource_definition_id, "management-cluster-gke-")
    error_message = "The generated Resource Definition ID must use the default prefix management-cluster-gke"
  }

  assert {
    condition     = module.management_cluster.cluster_access_subject.kind == "User"
    error_message = "The cluster access subject must be a User"
  }

  assert {
    condition     = module.management_cluster.cluster_access_subject.name == "humanitec-orchestrator@my-project.iam.gserviceaccount.com"
    error_message = "The cluster access subject must be the email address of the Cloud Account service account"
  }

  assert {
    condition     = toset(keys(local.cluster_values)) == toset(["internal_ip", "loadbalancer", "name", "project_id", "proxy_url", "zone"])
    error_message = "The cluster values must have exactly the keys internal_ip, loadbalancer, name, project_id, proxy_url, zone"
  }

  assert {
    condition     = local.cluster_values.internal_ip == null && local.cluster_values.loadbalancer == null && local.cluster_values.proxy_url == null
    error_message = "The internal_ip, loadbalancer, and proxy_url cluster values must be null by default so that the Driver defaults apply"
  }

  assert {
    condition     = local.cluster_values.name == "my-gke"
    error_message = "The name cluster value must be the GKE cluster name"
  }

  assert {
    condition     = local.cluster_values.project_id == "my-project"
    error_message = "The project_id cluster value must be the project of the GKE cluster"
  }

  assert {
    condition     = local.cluster_values.zone == "europe-west3"
    error_message = "The zone cluster value must be the location of the GKE cluster"
  }
}

run "sets_optional_cluster_values" {
  command = apply

  variables {
    loadbalancer = "10.0.0.1"
    proxy_url    = "http://proxy.example.com:3128"
    internal_ip  = true
  }

  assert {
    condition     = local.cluster_values.loadbalancer == "10.0.0.1"
    error_message = "The loadbalancer cluster value must be taken from the loadbalancer variable"
  }

  assert {
    condition     = local.cluster_values.proxy_url == "http://proxy.example.com:3128"
    error_message = "The proxy_url cluster value must be taken from the proxy_url variable"
  }

  assert {
    condition     = local.cluster_values.internal_ip == true
    error_message = "The internal_ip cluster value must be taken from the internal_ip variable"
  }
}

run "rejects_internal_ip_without_agent" {
  command = plan

  variables {
    internal_ip  = true
    enable_agent = false
  }

  expect_failures = [var.internal_ip]
}

run "allows_disabled_agent_without_internal_ip" {
  command = plan

  variables {
    internal_ip  = false
    enable_agent = false
  }

  assert {
    condition     = local.cluster_values.internal_ip == false
    error_message = "internal_ip must be allowed to be false if enable_agent is false"
  }
}

run "uses_provider_project_for_cluster_values" {
  command = apply

  variables {
    gke_project_id = null
  }

  assert {
    condition     = local.cluster_values.project_id == "my-provider-project"
    error_message = "The project_id cluster value must fall back to the project of the google provider"
  }
}

run "passes_through_variables" {
  command = apply

  variables {
    resource_definition_id       = "my-cluster"
    cluster_role_name            = "my-deploy-access"
    helm_release_name            = "my-operator"
    helm_release_namespace       = "my-namespace"
    helm_release_version         = "1.2.3"
    helm_release_repository      = "oci://example.com/charts"
    helm_release_chart           = "my-chart"
    enable_driver_authentication = true
    humanitec_org_id             = "my-org"
  }

  assert {
    condition     = module.management_cluster.resource_definition_id == "my-cluster"
    error_message = "resource_definition_id must be passed through"
  }

  assert {
    condition     = module.management_cluster.cluster_role_name == "my-deploy-access"
    error_message = "cluster_role_name must be passed through"
  }

  assert {
    condition     = module.management_cluster.helm_release_name == "my-operator"
    error_message = "helm_release_name must be passed through"
  }

  assert {
    condition     = module.management_cluster.helm_release_namespace == "my-namespace"
    error_message = "helm_release_namespace must be passed through"
  }

  assert {
    condition     = module.management_cluster.helm_release_version == "1.2.3"
    error_message = "helm_release_version must be passed through"
  }

  assert {
    condition     = module.management_cluster.helm_release_repository == "oci://example.com/charts"
    error_message = "helm_release_repository must be passed through"
  }

  assert {
    condition     = module.management_cluster.helm_release_chart == "my-chart"
    error_message = "helm_release_chart must be passed through"
  }

  assert {
    condition     = module.management_cluster.operator_private_key_secret_name == "humanitec-operator-private-key"
    error_message = "enable_driver_authentication must be passed through"
  }
}

run "passes_through_resource_definition_id_prefix" {
  command = apply

  variables {
    resource_definition_id_prefix = "my-prefix"
  }

  assert {
    condition     = can(regex("^my-prefix-[a-z0-9]{4}$", module.management_cluster.resource_definition_id))
    error_message = "resource_definition_id_prefix must be passed through"
  }
}

run "passes_through_outputs" {
  command = apply

  # Enable driver authentication and set a chart version so that all outputs have non-null values
  variables {
    enable_driver_authentication = true
    humanitec_org_id             = "my-org"
    helm_release_version         = "1.2.3"
  }

  assert {
    condition     = alltrue([for v in [output.operator_public_key, output.operator_private_key, output.operator_public_key_id, output.operator_public_key_fingerprint, output.operator_private_key_secret_name, output.helm_release_version] : v != null])
    error_message = "The operator and chart version outputs must not be null when driver authentication is enabled"
  }

  assert {
    condition     = output.operator_public_key == module.management_cluster.operator_public_key
    error_message = "Output operator_public_key must be passed through from the management-cluster-k8s module"
  }

  assert {
    condition     = output.operator_private_key == module.management_cluster.operator_private_key
    error_message = "Output operator_private_key must be passed through from the management-cluster-k8s module"
  }

  assert {
    condition     = output.operator_public_key_id == module.management_cluster.operator_public_key_id
    error_message = "Output operator_public_key_id must be passed through from the management-cluster-k8s module"
  }

  assert {
    condition     = output.operator_public_key_fingerprint == module.management_cluster.operator_public_key_fingerprint
    error_message = "Output operator_public_key_fingerprint must be passed through from the management-cluster-k8s module"
  }

  assert {
    condition     = output.operator_private_key_secret_name == module.management_cluster.operator_private_key_secret_name
    error_message = "Output operator_private_key_secret_name must be passed through from the management-cluster-k8s module"
  }

  assert {
    condition     = output.helm_release_namespace == module.management_cluster.helm_release_namespace
    error_message = "Output helm_release_namespace must be passed through from the management-cluster-k8s module"
  }

  assert {
    condition     = output.helm_release_name == module.management_cluster.helm_release_name
    error_message = "Output helm_release_name must be passed through from the management-cluster-k8s module"
  }

  assert {
    condition     = output.helm_release_version == module.management_cluster.helm_release_version
    error_message = "Output helm_release_version must be passed through from the management-cluster-k8s module"
  }

  assert {
    condition     = output.helm_release_repository == module.management_cluster.helm_release_repository
    error_message = "Output helm_release_repository must be passed through from the management-cluster-k8s module"
  }

  assert {
    condition     = output.helm_release_chart == module.management_cluster.helm_release_chart
    error_message = "Output helm_release_chart must be passed through from the management-cluster-k8s module"
  }

  assert {
    condition     = output.resource_definition_id == module.management_cluster.resource_definition_id
    error_message = "Output resource_definition_id must be passed through from the management-cluster-k8s module"
  }

  assert {
    condition     = output.resource_definition_driver_type == module.management_cluster.resource_definition_driver_type
    error_message = "Output resource_definition_driver_type must be passed through from the management-cluster-k8s module"
  }

  assert {
    condition     = output.cluster_role_name == module.management_cluster.cluster_role_name
    error_message = "Output cluster_role_name must be passed through from the management-cluster-k8s module"
  }

  assert {
    condition     = output.cluster_role_binding_name == module.management_cluster.cluster_role_binding_name
    error_message = "Output cluster_role_binding_name must be passed through from the management-cluster-k8s module"
  }

  assert {
    condition     = output.cluster_access_subject == module.management_cluster.cluster_access_subject
    error_message = "Output cluster_access_subject must be passed through from the management-cluster-k8s module"
  }
}
