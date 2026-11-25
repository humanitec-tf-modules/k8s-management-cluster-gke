# Configuration of the google provider, for its project as the fallback of gke_project_id.
# It is read unconditionally: a count depending on whether gke_project_id is set could not be
# planned if it is only known after apply.
data "google_client_config" "current" {
  lifecycle {
    postcondition {
      condition     = var.gke_project_id != null || try(coalesce(self.project), null) != null
      error_message = "gke_project_id must be set if no project is configured in the google provider."
    }
  }
}

locals {
  # Project of the google provider, or null if none is configured. The provider reports an unset project
  # as an empty string, which coalesce() skips, and try() turns the error of coalesce() without a value into null.
  provider_project_id = try(coalesce(data.google_client_config.current.project), null)
  gke_project_id      = try(coalesce(var.gke_project_id, local.provider_project_id), null)
}

data "google_container_cluster" "gke" {
  name     = var.gke_cluster_name
  location = var.gke_location
  project  = local.gke_project_id
}

# Google service account behind a Cloud Account of type "gcp", read for its OAuth client ID.
# Not needed for type "gcp-identity", which identifies the service account by its email address
data "google_service_account" "cloud_account" {
  count = local.use_service_account_keys ? 1 : 0

  account_id = var.cloud_account_service_account_email
}

# Random suffix for the generated IAM custom role ID. Created only if no ID is passed in
resource "random_string" "iam_role_id_suffix" {
  count = var.iam_role_id == null ? 1 : 0

  length  = 4
  upper   = false
  numeric = false
  special = false
}

locals {
  use_service_account_keys = var.cloud_account_type == "gcp"

  # Kubernetes user name of the Cloud Account service account, depending on the type of the Cloud Account.
  # See https://developer.humanitec.com/platform-orchestrator/docs/integration-and-extensions/containerization/kubernetes/#2-configure-gke-for-direct-deployments
  cluster_access_subject_name = (
    local.use_service_account_keys
    ? one(data.google_service_account.cloud_account[*].unique_id)
    : var.cloud_account_service_account_email
  )

  # IAM custom role IDs must be 3 to 64 characters long and may only contain letters, digits, underscores, and periods.
  # "humanitec_orchestrator_gke_" (27) + at most 32 characters of the cluster name + "_" + the random suffix (4) yields at most 64.
  # Trailing hyphens of the truncated cluster name are removed, and the remaining ones replaced with underscores.
  iam_role_id = var.iam_role_id != null ? var.iam_role_id : join("_", [
    "humanitec_orchestrator_gke",
    replace(replace(substr(var.gke_cluster_name, 0, 32), "/-+$/", ""), "-", "_"),
    random_string.iam_role_id_suffix[0].result,
  ])

  iam_role_title = coalesce(var.iam_role_title, "Humanitec Orchestrator access to GKE cluster ${var.gke_cluster_name}")

  # Driver input values for humanitec/k8s-cluster-gke. The child module drops null values so that the Driver defaults apply
  cluster_values = {
    internal_ip  = var.internal_ip
    loadbalancer = var.loadbalancer
    name         = var.gke_cluster_name
    project_id   = local.gke_project_id
    proxy_url    = var.proxy_url
    # The Driver input "zone" takes the location of the cluster
    zone = var.gke_location
  }

  # Helm chart values making the Operator impersonate a Google service account via Workload Identity Federation for GKE.
  # Using the Kubernetes service account of the Operator directly as an IAM principal requires no Helm values
  use_operator_gcp_service_account = var.operator_gcp_service_account_email != null
  operator_gcp_service_account_helm_values = yamlencode({
    controllerManager = {
      serviceAccount = {
        annotations = {
          "iam.gke.io/gcp-service-account" = var.operator_gcp_service_account_email
        }
      }
    }
  })

  # Helm merges values documents in order, so the values passed in come last to take precedence
  helm_release_values = local.use_operator_gcp_service_account ? concat(
    [local.operator_gcp_service_account_helm_values],
    var.helm_release_values != null ? var.helm_release_values : [],
  ) : var.helm_release_values
}

# IAM custom role granting access to the API server of the GKE clusters in the project.
# Least privilege: the role contains no permissions on Kubernetes objects.
# The child module grants these through a Kubernetes ClusterRole bound to the Cloud Account service account instead.
# See https://developer.humanitec.com/platform-orchestrator/docs/integration-and-extensions/containerization/kubernetes/#2-configure-gke-for-direct-deployments
resource "google_project_iam_custom_role" "orchestrator_cluster_access" {
  project     = local.gke_project_id
  role_id     = local.iam_role_id
  title       = local.iam_role_title
  description = "Humanitec Orchestrator access to the GKE cluster ${var.gke_cluster_name} in ${var.gke_location}. Kubernetes RBAC on the cluster grants the permissions on Kubernetes objects."
  permissions = [
    "container.clusters.connect",
    "container.clusters.get",
  ]
}

# Grant the custom role to the Cloud Account service account.
# Non-authoritative, so that other members of the role on the project remain in place.
# GKE does not support IAM policies on individual clusters, so the binding is on the project of the cluster
resource "google_project_iam_member" "orchestrator_cluster_access" {
  project = local.gke_project_id
  role    = google_project_iam_custom_role.orchestrator_cluster_access.name
  member  = "serviceAccount:${var.cloud_account_service_account_email}"
}

module "management_cluster" {
  source = "github.com/humanitec-tf-modules/k8s-management-cluster?ref=v1.0.0"

  driver_type                 = "humanitec/k8s-cluster-gke"
  cluster_access_subject_kind = "User"
  cluster_access_subject_name = local.cluster_access_subject_name
  cluster_values              = local.cluster_values

  # Pass-through variables
  resource_definition_id                  = var.resource_definition_id
  resource_definition_id_prefix           = var.resource_definition_id_prefix
  resource_definition_name                = var.resource_definition_name
  resource_definition_criteria            = var.resource_definition_criteria
  cloud_account_id                        = var.cloud_account_id
  enable_agent                            = var.enable_agent
  cluster_role_name                       = var.cluster_role_name
  cluster_secrets                         = var.cluster_secrets
  humanitec_org_id                        = var.humanitec_org_id
  enable_driver_authentication            = var.enable_driver_authentication
  operator_private_key                    = var.operator_private_key
  operator_public_key                     = var.operator_public_key
  helm_release_namespace                  = var.helm_release_namespace
  helm_release_create_namespace           = var.helm_release_create_namespace
  helm_release_name                       = var.helm_release_name
  helm_release_version                    = var.helm_release_version
  helm_release_repository                 = var.helm_release_repository
  helm_release_chart                      = var.helm_release_chart
  helm_release_atomic                     = var.helm_release_atomic
  helm_release_cleanup_on_fail            = var.helm_release_cleanup_on_fail
  helm_release_dependency_update          = var.helm_release_dependency_update
  helm_release_description                = var.helm_release_description
  helm_release_devel                      = var.helm_release_devel
  helm_release_disable_crd_hooks          = var.helm_release_disable_crd_hooks
  helm_release_disable_openapi_validation = var.helm_release_disable_openapi_validation
  helm_release_disable_webhooks           = var.helm_release_disable_webhooks
  helm_release_force_update               = var.helm_release_force_update
  helm_release_keyring                    = var.helm_release_keyring
  helm_release_lint                       = var.helm_release_lint
  helm_release_max_history                = var.helm_release_max_history
  helm_release_pass_credentials           = var.helm_release_pass_credentials
  helm_release_postrender                 = var.helm_release_postrender
  helm_release_recreate_pods              = var.helm_release_recreate_pods
  helm_release_render_subchart_notes      = var.helm_release_render_subchart_notes
  helm_release_replace                    = var.helm_release_replace
  helm_release_repository_ca_file         = var.helm_release_repository_ca_file
  helm_release_repository_cert_file       = var.helm_release_repository_cert_file
  helm_release_repository_key_file        = var.helm_release_repository_key_file
  helm_release_repository_password        = var.helm_release_repository_password
  helm_release_repository_username        = var.helm_release_repository_username
  helm_release_reset_values               = var.helm_release_reset_values
  helm_release_reuse_values               = var.helm_release_reuse_values
  helm_release_set                        = var.helm_release_set
  helm_release_set_wo                     = var.helm_release_set_wo
  helm_release_set_wo_revision            = var.helm_release_set_wo_revision
  helm_release_set_list                   = var.helm_release_set_list
  helm_release_set_sensitive              = var.helm_release_set_sensitive
  helm_release_skip_crds                  = var.helm_release_skip_crds
  helm_release_take_ownership             = var.helm_release_take_ownership
  helm_release_timeout                    = var.helm_release_timeout
  helm_release_upgrade_install            = var.helm_release_upgrade_install
  helm_release_values                     = local.helm_release_values
  helm_release_verify                     = var.helm_release_verify
  helm_release_wait                       = var.helm_release_wait
  helm_release_wait_for_jobs              = var.helm_release_wait_for_jobs

  # Make Deployments target the cluster, via the Resource Definition created in the module, only once the
  # Cloud Account service account can connect to the cluster. On destroy, the IAM access is revoked last.
  # The module contains no data sources, so this does not defer any reads to the apply
  depends_on = [google_project_iam_member.orchestrator_cluster_access]
}
