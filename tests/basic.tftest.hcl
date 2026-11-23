# See https://developer.hashicorp.com/terraform/language/tests for more on how to write tests.
# See https://developer.hashicorp.com/terraform/language/tests/mocking for information on mocking providers.
#
# All providers are mocked, so these tests run without Google Cloud credentials and create no real infrastructure.

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

run "creates_gcp_objects_with_defaults" {
  command = apply

  # Cluster
  assert {
    condition     = data.google_container_cluster.gke.name == "my-gke" && data.google_container_cluster.gke.location == "europe-west3" && data.google_container_cluster.gke.project == "my-project"
    error_message = "The cluster must be read by its name, location, and project"
  }

  # IAM custom role
  assert {
    condition     = google_project_iam_custom_role.orchestrator_cluster_access.role_id == "humanitec_orchestrator_gke_my_gke_abcd"
    error_message = "The IAM role ID must be generated as humanitec_orchestrator_gke_<cluster name>_<suffix> with underscores instead of hyphens, got ${google_project_iam_custom_role.orchestrator_cluster_access.role_id}"
  }

  assert {
    condition     = google_project_iam_custom_role.orchestrator_cluster_access.title == "Humanitec Orchestrator access to GKE cluster my-gke"
    error_message = "The IAM role title must be derived from the cluster name"
  }

  assert {
    condition     = google_project_iam_custom_role.orchestrator_cluster_access.project == "my-project"
    error_message = "The IAM role must be created in the project of the cluster"
  }

  assert {
    condition     = toset(google_project_iam_custom_role.orchestrator_cluster_access.permissions) == toset(["container.clusters.connect", "container.clusters.get"])
    error_message = "The IAM role must contain exactly the permissions container.clusters.connect and container.clusters.get"
  }

  assert {
    condition     = strcontains(google_project_iam_custom_role.orchestrator_cluster_access.description, "GKE cluster my-gke in europe-west3")
    error_message = "The IAM role description must name the cluster and its location"
  }

  # IAM role binding
  assert {
    condition     = google_project_iam_member.orchestrator_cluster_access.project == "my-project"
    error_message = "The IAM role must be granted on the project of the cluster"
  }

  assert {
    condition     = google_project_iam_member.orchestrator_cluster_access.role == "projects/my-project/roles/my-role"
    error_message = "The IAM role binding must grant the custom role"
  }

  assert {
    condition     = google_project_iam_member.orchestrator_cluster_access.member == "serviceAccount:humanitec-orchestrator@my-project.iam.gserviceaccount.com"
    error_message = "The IAM role must be granted to the Cloud Account service account"
  }

  # Kubernetes access
  assert {
    condition     = length(data.google_service_account.cloud_account) == 0
    error_message = "The Cloud Account service account must not be read for a Cloud Account of type gcp-identity"
  }

  assert {
    condition     = module.management_cluster.cluster_access_subject.kind == "User" && module.management_cluster.cluster_access_subject.name == "humanitec-orchestrator@my-project.iam.gserviceaccount.com"
    error_message = "The cluster access subject must be the User named after the email address of the Cloud Account service account"
  }

  # Outputs
  assert {
    condition     = output.iam_role_id == "humanitec_orchestrator_gke_my_gke_abcd"
    error_message = "The iam_role_id output must be the ID of the IAM role"
  }

  assert {
    condition     = output.iam_role_name == "projects/my-project/roles/my-role"
    error_message = "The iam_role_name output must be the full name of the IAM role"
  }

  assert {
    condition     = output.iam_member == "serviceAccount:humanitec-orchestrator@my-project.iam.gserviceaccount.com"
    error_message = "The iam_member output must be the member of the IAM role binding"
  }

  assert {
    condition     = output.gke_cluster_id == "projects/my-project/locations/europe-west3/clusters/my-gke"
    error_message = "The gke_cluster_id output must be the ID of the GKE cluster"
  }

  assert {
    condition     = output.gke_project_id == "my-project"
    error_message = "The gke_project_id output must be the project passed in"
  }
}

run "truncates_generated_role_id" {
  command = plan

  variables {
    # 40 characters, the maximum length of a GKE cluster name, with a hyphen as the 32nd character
    gke_cluster_name = "my-very-long-gke-cluster-name-x-yyyyyyyy"
  }

  assert {
    condition     = local.iam_role_id == "humanitec_orchestrator_gke_my_very_long_gke_cluster_name_x_abcd"
    error_message = "The generated IAM role ID must use at most 32 characters of the cluster name without trailing hyphens, got ${local.iam_role_id}"
  }

  assert {
    condition     = can(regex("^[a-zA-Z0-9_.]{3,64}$", local.iam_role_id))
    error_message = "The generated IAM role ID must be a valid custom role ID"
  }
}

run "uses_custom_role_id_and_title" {
  command = apply

  variables {
    iam_role_id    = "my.custom_role"
    iam_role_title = "My custom role"
  }

  assert {
    condition     = google_project_iam_custom_role.orchestrator_cluster_access.role_id == "my.custom_role"
    error_message = "The IAM role ID must use the value passed in"
  }

  assert {
    condition     = google_project_iam_custom_role.orchestrator_cluster_access.title == "My custom role"
    error_message = "The IAM role title must use the value passed in"
  }

  assert {
    condition     = length(random_string.iam_role_id_suffix) == 0
    error_message = "No random suffix must be created when an IAM role ID is passed in"
  }
}

run "falls_back_to_provider_project" {
  command = apply

  variables {
    gke_project_id = null
  }

  assert {
    condition     = data.google_container_cluster.gke.project == "my-provider-project"
    error_message = "The cluster must be read from the project of the google provider"
  }

  assert {
    condition     = google_project_iam_custom_role.orchestrator_cluster_access.project == "my-provider-project"
    error_message = "The IAM role must be created in the project of the google provider"
  }

  assert {
    condition     = google_project_iam_member.orchestrator_cluster_access.project == "my-provider-project"
    error_message = "The IAM role must be granted on the project of the google provider"
  }

  assert {
    condition     = output.gke_project_id == "my-provider-project"
    error_message = "The gke_project_id output must be the project of the google provider"
  }
}

run "rejects_missing_project" {
  command = plan

  variables {
    gke_project_id = null
  }

  # The google provider reports an unset project as an empty string
  override_data {
    target = data.google_client_config.current
    values = {
      project = ""
    }
  }

  expect_failures = [data.google_client_config.current]
}

run "uses_oauth_client_id_for_service_account_keys" {
  command = apply

  variables {
    cloud_account_type = "gcp"
  }

  assert {
    condition     = length(data.google_service_account.cloud_account) == 1
    error_message = "The Cloud Account service account must be read for a Cloud Account of type gcp"
  }

  assert {
    condition     = data.google_service_account.cloud_account[0].account_id == "humanitec-orchestrator@my-project.iam.gserviceaccount.com"
    error_message = "The Cloud Account service account must be read by its email address"
  }

  assert {
    condition     = module.management_cluster.cluster_access_subject.kind == "User" && module.management_cluster.cluster_access_subject.name == "123456789012345678901"
    error_message = "The cluster access subject must be the User named after the OAuth client ID of the Cloud Account service account"
  }

  assert {
    condition     = google_project_iam_member.orchestrator_cluster_access.member == "serviceAccount:humanitec-orchestrator@my-project.iam.gserviceaccount.com"
    error_message = "The IAM role must be granted to the Cloud Account service account"
  }
}

run "rejects_empty_cluster_name" {
  command = plan

  variables {
    gke_cluster_name = " "
  }

  expect_failures = [var.gke_cluster_name]
}

run "rejects_empty_location" {
  command = plan

  variables {
    gke_location = ""
  }

  expect_failures = [var.gke_location]
}

run "rejects_empty_project_id" {
  command = plan

  variables {
    gke_project_id = ""
  }

  expect_failures = [var.gke_project_id]
}

run "rejects_invalid_service_account_email" {
  command = plan

  variables {
    cloud_account_service_account_email = "not-a-service-account@example.com"
  }

  expect_failures = [var.cloud_account_service_account_email]
}

run "rejects_invalid_cloud_account_type" {
  command = plan

  variables {
    cloud_account_type = "aws-role"
  }

  expect_failures = [var.cloud_account_type]
}

run "rejects_invalid_role_id" {
  command = plan

  variables {
    iam_role_id = "my-role"
  }

  expect_failures = [var.iam_role_id]
}

run "rejects_empty_role_title" {
  command = plan

  variables {
    iam_role_title = ""
  }

  expect_failures = [var.iam_role_title]
}
