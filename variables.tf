variable "gke_cluster_name" {
  description = "Name of the existing GKE cluster to use as the Humanitec management cluster."
  type        = string
  nullable    = false

  validation {
    condition     = trimspace(var.gke_cluster_name) != ""
    error_message = "gke_cluster_name must not be empty."
  }
}

variable "gke_location" {
  description = "Location of the GKE cluster, i.e. its zone for a zonal cluster, e.g. `europe-west3-a`, or its region for a regional cluster, e.g. `europe-west3`. The module sets it as the Driver input `zone`."
  type        = string
  nullable    = false

  validation {
    condition     = trimspace(var.gke_location) != ""
    error_message = "gke_location must not be empty."
  }
}

variable "gke_project_id" {
  description = "ID of the Google Cloud project hosting the GKE cluster. If not set, the project of the `google` provider that is passed in to the module is used. The module creates the IAM custom role and its role binding in this project."
  type        = string
  nullable    = true
  default     = null

  validation {
    condition     = var.gke_project_id == null || try(trimspace(var.gke_project_id), "") != ""
    error_message = "gke_project_id must not be empty if set."
  }
}

variable "cloud_account_service_account_email" {
  description = "Email address of the Google service account behind the GCP Cloud Account the Orchestrator uses to access the cluster, e.g. `humanitec-orchestrator@my-project.iam.gserviceaccount.com`. The module grants it the IAM custom role allowing access to the cluster, and binds the Kubernetes ClusterRole `cluster_role_name` to it."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9._-]+@[a-z0-9.-]+\\.gserviceaccount\\.com$", var.cloud_account_service_account_email))
    error_message = "cloud_account_service_account_email must be a service account email like my-sa@my-project.iam.gserviceaccount.com."
  }
}

variable "cloud_account_type" {
  description = "Type of the Cloud Account referenced by `cloud_account_id`, which determines the Kubernetes user name of its Google service account. `gcp-identity` (GCP Service account impersonation, recommended): the user name is the email address of the service account. `gcp` (GCP Service account keys): the user name is the OAuth client ID of the service account, which the module reads from the service account. See https://developer.humanitec.com/platform-orchestrator/docs/platform-orchestrator/security/cloud-accounts/gcp/"
  type        = string
  nullable    = false
  default     = "gcp-identity"

  validation {
    condition     = contains(["gcp-identity", "gcp"], var.cloud_account_type)
    error_message = "cloud_account_type must be one of gcp-identity, gcp."
  }
}

variable "iam_role_id" {
  description = "ID of the IAM custom role granting the Cloud Account service account access to the cluster, created in the project `gke_project_id`. If not set, the module generates an ID from the cluster name and a random four-letter suffix. Google Cloud blocks the ID of a deleted custom role for several weeks, so choose a new ID when recreating the role."
  type        = string
  nullable    = true
  default     = null

  validation {
    condition     = var.iam_role_id == null || can(regex("^[a-zA-Z0-9_.]{3,64}$", var.iam_role_id))
    error_message = "iam_role_id must consist of 3 to 64 letters, digits, underscores, or periods."
  }
}

variable "iam_role_title" {
  description = "Title of the IAM custom role granting the Cloud Account service account access to the cluster. If not set, a title is derived from the cluster name."
  type        = string
  nullable    = true
  default     = null

  validation {
    condition     = var.iam_role_title == null || try(length(trimspace(var.iam_role_title)) > 0 && length(var.iam_role_title) <= 100, false)
    error_message = "iam_role_title must not be empty and must not exceed 100 characters."
  }
}

variable "loadbalancer" {
  description = "The IP or DNS name representing the cluster load balancer."
  type        = string
  default     = null
}

variable "proxy_url" {
  description = "The URL of a proxy to use for accessing the cluster API server. Corresponds to the kubeconfig value `proxy-url`."
  type        = string
  default     = null
}

variable "internal_ip" {
  description = "Access the cluster via the private endpoint address of its control plane, if the private endpoint is enabled. Set it to `true` if you access a private cluster through the Humanitec Agent. Requires `enable_agent` to be `true`, as the Driver only uses the private endpoint through the Agent. If not set, the Driver default applies."
  type        = bool
  default     = null

  validation {
    condition     = var.internal_ip != true || var.enable_agent
    error_message = "internal_ip can only be true if enable_agent is true, as the Driver only uses the private endpoint of the cluster through the Humanitec Agent."
  }
}

variable "operator_gcp_service_account_email" {
  description = "Email address of a Google service account the Operator impersonates via Workload Identity Federation for GKE. If set, the module adds the Helm chart value for the service account annotation `iam.gke.io/gcp-service-account` before any values passed in via `helm_release_values`. Leave unset if the Operator uses its Kubernetes service account as an IAM principal directly, which requires no Helm chart values, or no Google Cloud identity at all. See https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity"
  type        = string
  default     = null

  validation {
    condition     = var.operator_gcp_service_account_email == null || can(regex("^[a-z0-9._-]+@[a-z0-9.-]+\\.gserviceaccount\\.com$", var.operator_gcp_service_account_email))
    error_message = "operator_gcp_service_account_email must be a service account email like my-sa@my-project.iam.gserviceaccount.com or null."
  }
}

# Variables passed through to the management-cluster-k8s module
# Note: no validation blocks on purpose because the child module already runs them
variable "resource_definition_id" {
  description = "ID of the Resource Definition of type `k8s-cluster` representing the cluster. Must be unique within the Humanitec Organization. Defaults to `<resource_definition_id_prefix>-<suffix>` with a random suffix of four lowercase alphanumeric characters."
  type        = string
  nullable    = true
  default     = null
}
variable "resource_definition_id_prefix" {
  description = "Prefix of the generated `resource_definition_id`. Ignored if `resource_definition_id` is set."
  type        = string
  nullable    = false
  default     = "management-cluster-gke"
}
variable "resource_definition_name" {
  description = "Display name of the Resource Definition. Defaults to `resource_definition_id`."
  type        = string
  nullable    = true
  default     = null
}
variable "resource_definition_criteria" {
  description = "Matching Criteria for the Resource Definition, directing Deployments to the cluster. Each entry creates one Matching Criteria. Unset attributes match any value. See https://developer.humanitec.com/platform-orchestrator/docs/platform-orchestrator/resources/resource-definitions/#matching-criteria"
  type = list(object({
    app_id   = optional(string)
    env_id   = optional(string)
    env_type = optional(string)
    res_id   = optional(string)
    class    = optional(string)
  }))
  nullable = false
  default  = []
}
variable "cloud_account_id" {
  description = "ID of the GCP Cloud Account the Orchestrator uses to access the cluster."
  type        = string
  nullable    = false
}
variable "enable_agent" {
  description = "Access the cluster through the Humanitec Agent. Adds the secret `agent_url`, referencing the output `url` of the Resource `agent#agent`, to the Resource Definition. Requires a Resource Definition of type `agent` matching the same Deployments as the cluster. See https://developer.humanitec.com/platform-orchestrator/docs/integration-and-extensions/humanitec-agent/overview/"
  type        = bool
  nullable    = false
  default     = true
}
variable "cluster_role_name" {
  description = "Name of the Kubernetes ClusterRole and ClusterRoleBinding granting the Orchestrator access to the cluster."
  type        = string
  nullable    = false
  default     = "humanitec-deploy-access"
}
variable "cluster_secrets" {
  description = "Driver input secrets of the Resource Definition for the Driver `humanitec/k8s-cluster-gke`. See the Driver documentation at https://developer.humanitec.com/platform-orchestrator/docs/integration-and-extensions/drivers/k8-drivers/. If `enable_agent` is `true`, the module adds the key `agent_url`."
  type        = any
  sensitive   = true
  nullable    = false
  default     = {}
}
variable "humanitec_org_id" {
  description = "Humanitec Organization ID. Required if `enable_driver_authentication` is `true`, ignored otherwise."
  type        = string
  nullable    = true
  default     = null
}
variable "enable_driver_authentication" {
  description = "Enable authentication of the Operator against Humanitec-hosted Drivers. Requires `humanitec_org_id`. Registers the public key in the Humanitec Organization and stores the private key in the Kubernetes Secret `humanitec-operator-private-key` in the namespace `helm_release_namespace`. Pass in a key pair via `operator_private_key` and `operator_public_key`, or leave both unset to generate a convenience key pair. Only required if you use Humanitec-hosted Drivers. See https://developer.humanitec.com/platform-orchestrator/docs/integration-and-extensions/humanitec-operator/installation/#configure-authentication-for-drivers"
  type        = bool
  nullable    = false
  default     = false
}
variable "operator_private_key" {
  description = "Private key for the Humanitec Operator authentication against Humanitec-hosted Drivers. Must be a multiline string starting with -----BEGIN PRIVATE KEY----- and having a final line break. Both or neither of `operator_public_key` and `operator_private_key` must be set, and only if `enable_driver_authentication` is `true`. If not set while `enable_driver_authentication` is `true`, a convenience key pair will be generated using a `tls_private_key` resource and stored in the Terraform state, but this is not recommended for production use."
  type        = string
  sensitive   = true
  nullable    = true
  default     = null
}
variable "operator_public_key" {
  description = "Public key for the Humanitec Operator authentication against Humanitec-hosted Drivers. Must be a multiline string starting with -----BEGIN PUBLIC KEY----- and having a final line break. Both or neither of `operator_public_key` and `operator_private_key` must be set, and only if `enable_driver_authentication` is `true`. If not set while `enable_driver_authentication` is `true`, a convenience key pair will be generated using a `tls_private_key` resource and stored in the Terraform state, but this is not recommended for production use."
  type        = string
  nullable    = true
  default     = null
}
variable "helm_release_namespace" {
  description = "Kubernetes namespace where to install the Operator"
  type        = string
  nullable    = false
  default     = "humanitec-operator-system"
}
variable "helm_release_create_namespace" {
  description = "Choose whether to create the Kubernetes namespace"
  type        = bool
  nullable    = false
  default     = true
}
variable "helm_release_name" {
  type        = string
  description = "Name of the Helm release for the Operator"
  nullable    = false
  default     = "humanitec-operator"
}
variable "helm_release_version" {
  type        = string
  description = "Chart version to use for the Operator installation in the format `X.Y.Z`. If this is not specified, the latest version is installed."
  nullable    = true
  default     = null
}
variable "helm_release_repository" {
  description = "Repository where to locate the requested chart. If is a URL the chart is installed without installing the repository. Set it to `null` for a local chart."
  type        = string
  nullable    = true
  default     = "oci://ghcr.io/humanitec/charts"
}
variable "helm_release_chart" {
  description = "Chart name to be installed. A path may be used."
  type        = string
  nullable    = false
  default     = "humanitec-operator"
}
variable "helm_release_atomic" {
  description = "If set, installation process purges chart on fail. The wait flag will be set automatically if atomic is used. Defaults to `false`."
  type        = bool
  default     = null
}
variable "helm_release_cleanup_on_fail" {
  description = "Allow deletion of new resources created in this upgrade when upgrade fails. Defaults to `false`."
  type        = bool
  default     = null
}
variable "helm_release_dependency_update" {
  description = "Run helm dependency update before installing the chart. Defaults to `false`."
  type        = bool
  default     = null
}
variable "helm_release_description" {
  description = "Add a custom description"
  type        = string
  default     = null
}
variable "helm_release_devel" {
  description = "Use chart development versions, too. Equivalent to version '>0.0.0-0'. If `helm_release_version` is set, this is ignored"
  type        = bool
  default     = null
}
variable "helm_release_disable_crd_hooks" {
  description = "Prevent CRD hooks from running, but run other hooks. See helm install --no-crd-hook"
  type        = bool
  default     = null
}
variable "helm_release_disable_openapi_validation" {
  description = "If set, the installation process will not validate rendered templates against the Kubernetes OpenAPI Schema. Defaults to `false`."
  type        = bool
  default     = null
}
variable "helm_release_disable_webhooks" {
  description = "Prevent hooks from running. Defaults to `false`."
  type        = bool
  default     = null
}
variable "helm_release_force_update" {
  description = "Force resource update through delete/recreate if needed. Defaults to `false`."
  type        = bool
  default     = null
}
variable "helm_release_keyring" {
  description = "Location of public keys used for verification. Used only if `helm_release_verify` is true. Defaults to `/.gnupg/pubring.gpg` in the location set by `home`."
  type        = string
  default     = null
}
variable "helm_release_lint" {
  description = "Run helm lint when planning. Defaults to `false`."
  type        = bool
  default     = null
}
variable "helm_release_max_history" {
  description = "Limit the maximum number of revisions saved per release. Use 0 for no limit. Defaults to 0 (no limit)."
  type        = number
  default     = null
}
variable "helm_release_pass_credentials" {
  description = "Pass credentials to all domains. Defaults to `false`."
  type        = bool
  default     = null
}
variable "helm_release_postrender" {
  description = "Postrender command configuration."
  type = object({
    binary_path = string
    args        = optional(list(string))
  })
  default = null
}
variable "helm_release_recreate_pods" {
  description = "Perform pods restart during upgrade/rollback. Defaults to `false`."
  type        = bool
  default     = null
}
variable "helm_release_render_subchart_notes" {
  description = "If set, render subchart notes along with the parent. Defaults to `true`."
  type        = bool
  default     = null
}
variable "helm_release_replace" {
  description = "Re-use the given name, even if that name is already used. This is unsafe in production. Defaults to `false`."
  type        = bool
  default     = null
}
variable "helm_release_repository_ca_file" {
  description = "The repositories CA File"
  type        = string
  default     = null
}
variable "helm_release_repository_cert_file" {
  description = "The repositories cert file"
  type        = string
  default     = null
}
variable "helm_release_repository_key_file" {
  description = "The repositories cert key file"
  type        = string
  default     = null
}
variable "helm_release_repository_password" {
  description = "Password for HTTP basic authentication"
  type        = string
  sensitive   = true
  default     = null
}
variable "helm_release_repository_username" {
  description = "Username for HTTP basic authentication"
  type        = string
  default     = null
}
variable "helm_release_reset_values" {
  description = "When upgrading, reset the values to the ones built into the chart. Defaults to `false`."
  type        = bool
  default     = null
}
variable "helm_release_reuse_values" {
  description = "When upgrading, reuse the last release's values and merge in any overrides. If 'helm_release_reset_values' is specified, this is ignored. Defaults to `false`."
  type        = bool
  default     = null
}
variable "helm_release_set" {
  description = "Custom values to be merged with the values."
  type = list(object({
    name  = string
    value = optional(string)
    type  = optional(string)
  }))
  nullable = false
  default  = []
}
variable "helm_release_set_wo" {
  description = "Custom values to be merged with the values. This is the same as \"helm_release_set\" but write-only."
  type = list(object({
    name  = string
    value = string
    type  = optional(string)
  }))
  ephemeral = true
  nullable  = false
  default   = []
}
variable "helm_release_set_wo_revision" {
  description = "The current revision of the write-only \"helm_release_set_wo\" attribute. Incrementing this integer value will cause Terraform to update the write-only value."
  type        = number
  default     = null
}
variable "helm_release_set_list" {
  description = "Custom list values to be merged with the values."
  type = list(object({
    name  = string
    value = list(string)
  }))
  nullable = false
  default  = []
}
variable "helm_release_set_sensitive" {
  description = "Custom sensitive values to be merged with the values."
  type = list(object({
    name  = string
    value = string
    type  = optional(string)
  }))
  sensitive = true
  nullable  = false
  default   = []
}
variable "helm_release_skip_crds" {
  description = "If set, no CRDs will be installed. By default, CRDs are installed if not already present. Defaults to `false`."
  type        = bool
  default     = null
}
variable "helm_release_take_ownership" {
  description = "If set, allows Helm to adopt existing resources not marked as managed by the release. Defaults to `false`."
  type        = bool
  default     = null
}
variable "helm_release_timeout" {
  description = "Time in seconds to wait for any individual Kubernetes operation. Defaults to 300 seconds."
  type        = number
  default     = null
}
variable "helm_release_upgrade_install" {
  description = "If true, the provider will install the release at the specified version even if a release not controlled by the provider is present: this is equivalent to running 'helm upgrade --install' with the Helm CLI. WARNING: this may not be suitable for production use -- see the 'Upgrade Mode' note in the provider documentation. Defaults to `false`."
  type        = bool
  default     = null
}
variable "helm_release_values" {
  description = "List of values in raw yaml format to pass to Helm. If `operator_gcp_service_account_email` is set, the module prepends the service account annotation values, so values passed in here are merged with them and take precedence."
  type        = list(string)
  default     = null
}
variable "helm_release_verify" {
  description = "Verify the package before installing it. Defaults to `false`."
  type        = bool
  default     = null
}
variable "helm_release_wait" {
  description = "Will wait until all resources are in a ready state before marking the release as successful. Defaults to `true`."
  type        = bool
  default     = null
}
variable "helm_release_wait_for_jobs" {
  description = "If wait is enabled, will wait until all Jobs have been completed before marking the release as successful. Defaults to `false`."
  type        = bool
  default     = null
}
