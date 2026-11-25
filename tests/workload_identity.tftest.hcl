# Verifies the Helm chart values making the Operator impersonate a Google service account via Workload Identity
# Federation for GKE, and their merging with values passed in.
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

run "omits_helm_values_by_default" {
  command = plan

  assert {
    condition     = local.helm_release_values == null
    error_message = "No Helm values must be set if no Google service account is passed in for the Operator and no values are passed in"
  }
}

run "passes_values_through_by_default" {
  command = plan

  variables {
    helm_release_values = [yamlencode({ foo = "bar" })]
  }

  assert {
    condition     = local.helm_release_values == tolist(var.helm_release_values)
    error_message = "The values passed in must be used unchanged if no Google service account is passed in for the Operator"
  }
}

run "adds_service_account_annotation" {
  command = plan

  variables {
    operator_gcp_service_account_email = "humanitec-operator@my-project.iam.gserviceaccount.com"
  }

  assert {
    condition     = length(local.helm_release_values) == 1
    error_message = "Only the service account annotation values must be set if no values are passed in"
  }

  assert {
    condition     = yamldecode(local.helm_release_values[0]).controllerManager.serviceAccount.annotations["iam.gke.io/gcp-service-account"] == "humanitec-operator@my-project.iam.gserviceaccount.com"
    error_message = "The service account annotation must hold the email address of the Google service account"
  }
}

run "merges_annotation_values_with_values_passed_in" {
  command = plan

  variables {
    operator_gcp_service_account_email = "humanitec-operator@my-project.iam.gserviceaccount.com"
    helm_release_values = [
      yamlencode({ controllerManager = { podLabels = { team = "platform" } } }),
      yamlencode({ foo = "bar" }),
    ]
  }

  assert {
    condition     = length(local.helm_release_values) == 3
    error_message = "The service account annotation values and all values passed in must be set"
  }

  assert {
    condition     = yamldecode(local.helm_release_values[0]).controllerManager.serviceAccount.annotations["iam.gke.io/gcp-service-account"] == "humanitec-operator@my-project.iam.gserviceaccount.com"
    error_message = "The service account annotation values must come first so that the values passed in take precedence"
  }

  assert {
    condition     = slice(local.helm_release_values, 1, 3) == tolist(var.helm_release_values)
    error_message = "The values passed in must follow the service account annotation values in their original order"
  }
}

run "rejects_invalid_operator_service_account_email" {
  command = plan

  variables {
    operator_gcp_service_account_email = "not-a-service-account"
  }

  expect_failures = [var.operator_gcp_service_account_email]
}
