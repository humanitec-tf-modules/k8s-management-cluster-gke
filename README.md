# Humanitec management cluster on GKE

This repository contains an OpenTofu/Terraform module for configuring an existing Google Kubernetes Engine (GKE) cluster as a Humanitec management cluster.

It wraps the [generic base module](https://github.com/humanitec-tf-modules/k8s-management-cluster) and adds the Google Cloud specific elements around cluster access and Operator identity.

## Runner cluster

To also set up the cluster to execute runners, use the separate module for the [GKE runner cluster](https://github.com/humanitec-tf-modules/k8s-runner-cluster-gke).

## Operator installation

See the notes in the [generic base module](https://github.com/humanitec-tf-modules/k8s-management-cluster#operator-installation).

## Operator identity

The identity setup for the Operator is an outcome of the secret store configuration, e.g. using the [Google Cloud Secret Manager secret store module](https://github.com/humanitec-tf-modules/secret-store-gcpsm).

- If the Operator uses its Kubernetes service account as an IAM principal directly via [Workload Identity Federation for GKE](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity) (recommended), it requires no configuration in this module
- If the Operator impersonates a Google service account via Workload Identity Federation for GKE, the Operator service account requires an annotation with the email address of the Google service account. Pass in that email address via `operator_gcp_service_account_email`. See the [usage examples](#impersonate-a-google-service-account-for-the-operator) for configuration details

## Cluster access

The module implements the [least privilege](https://developer.humanitec.com/platform-orchestrator/docs/integration-and-extensions/containerization/kubernetes/#2-configure-gke-for-direct-deployments) access setup combining a Kubernetes `ClusterRole` with a minimal IAM custom role for the Google service account used in a [GCP Cloud Account](https://developer.humanitec.com/platform-orchestrator/docs/platform-orchestrator/security/cloud-accounts/gcp/). It creates:

- An IAM custom role containing only the permissions `container.clusters.get` and `container.clusters.connect` in the project of the cluster
- An IAM role binding granting that role to the Cloud Account service account on the project of the cluster
- A `ClusterRole` with the permissions required by the Platform Orchestrator and a `ClusterRoleBinding` to the Kubernetes user of the Cloud Account service account

The Kubernetes user name of the service account depends on the type of the Cloud Account, which you set via `cloud_account_type`:

- `gcp-identity` ([GCP Service account impersonation](https://developer.humanitec.com/platform-orchestrator/docs/platform-orchestrator/security/cloud-accounts/gcp/#gcp-service-account-impersonation), default and recommended): the email address of the service account
- `gcp` ([GCP Service account keys](https://developer.humanitec.com/platform-orchestrator/docs/platform-orchestrator/security/cloud-accounts/gcp/#gcp-service-account-keys)): the OAuth client ID of the service account. The module reads it from the service account

> [!NOTE]
> **Architectural decision**
>
> GKE does not support IAM policies on individual clusters, so the module grants the IAM custom role on the project of the cluster. The role allows the Cloud Account service account to connect to the API server of every cluster in that project, but it grants no permissions on Kubernetes objects. Kubernetes RBAC grants these only on the cluster passed in to the module.
>
> The ID of the IAM custom role has a random suffix by default, so that several clusters in the same project can each have their own role. This also avoids conflicts when you recreate the role, because Google Cloud blocks the ID of a deleted custom role for several weeks.

Prerequisites:

- A GCP Cloud Account exists in the Platform Orchestrator, e.g. created using the [GCP Cloud Account module](https://github.com/humanitec-tf-modules/orchestrator-cloud-account-gcp-identity)
- The Cloud Account service account has no other IAM roles granting permissions on Kubernetes objects in the project of the cluster, such as `roles/container.developer`. Such roles add to the permissions granted via Kubernetes RBAC and defeat the least privilege setup
- The `google` provider passed in to the module is allowed to create IAM custom roles and IAM role bindings on the project of the cluster, e.g. through the roles `roles/iam.roleAdmin` and `roles/resourcemanager.projectIamAdmin`, and to read the cluster. For a Cloud Account of type `gcp`, it must also be allowed to read the Cloud Account service account
- If the `google` provider has no `project` configured, `gke_project_id` is set

> [!NOTE]
> IAM role bindings can take several minutes to propagate. Deployments to the cluster may fail until then.

## Humanitec Agent

See the notes in the [generic base module](https://github.com/humanitec-tf-modules/k8s-management-cluster#humanitec-agent).

If the Agent accesses the cluster via the private endpoint of its control plane, set `internal_ip = true`. See the [usage examples](#access-a-private-cluster-via-the-humanitec-agent).

## Authentication for Drivers

See the notes in the [generic base module](https://github.com/humanitec-tf-modules/k8s-management-cluster#authentication-for-drivers).

## Usage

### Common usage: GCP Service account impersonation, Workload Identity Federation for the Operator, no authentication for Drivers

```hcl
module "my_management_cluster_gke" {
  source = "github.com/humanitec-tf-modules/k8s-management-cluster-gke?ref=vX.Y.Z"
  providers = {
    humanitec  = humanitec
    helm       = helm
    kubernetes = kubernetes
    google     = google
  }

  # Operator chart version
  helm_release_version = "X.Y.Z"

  # Cluster values
  gke_cluster_name = "my-gke-cluster"
  gke_location     = "europe-west3"
  gke_project_id   = "my-gcp-project"

  # ID of the GCP Cloud Account the Orchestrator uses to access the cluster
  cloud_account_id = "my-gcp-cloud-account"
  # Email address of the Google service account used by the Cloud Account
  cloud_account_service_account_email = "humanitec-orchestrator@my-gcp-project.iam.gserviceaccount.com"
}
```

If you omit `gke_project_id`, the module uses the project of the `google` provider.

When you manage the Cloud Account using the [GCP Cloud Account module](https://github.com/humanitec-tf-modules/orchestrator-cloud-account-gcp-identity), pass in its outputs:

```hcl
module "my_management_cluster_gke" {
  source = "github.com/humanitec-tf-modules/k8s-management-cluster-gke?ref=vX.Y.Z"
  providers = {
    humanitec  = humanitec
    helm       = helm
    kubernetes = kubernetes
    google     = google
  }

  # All other values like in the preceding example, omitted

  cloud_account_id                    = module.cloud_account_gcp_identity.cloud_account_id
  cloud_account_service_account_email = module.cloud_account_gcp_identity.service_account_email
}
```

The following examples configure the Operator installation. They omit the cluster inputs shown in the first example.

### Use a Cloud Account with service account keys

```hcl
module "my_management_cluster_gke" {
  source = "github.com/humanitec-tf-modules/k8s-management-cluster-gke?ref=vX.Y.Z"
  providers = {
    humanitec  = humanitec
    helm       = helm
    kubernetes = kubernetes
    google     = google
  }

  # All values like in the first example, omitted

  # The Cloud Account is of type "gcp", using a key of the service account
  cloud_account_type = "gcp"
}
```

### Set the load balancer of the cluster

```hcl
module "my_management_cluster_gke" {
  source = "github.com/humanitec-tf-modules/k8s-management-cluster-gke?ref=vX.Y.Z"
  providers = {
    humanitec  = humanitec
    helm       = helm
    kubernetes = kubernetes
    google     = google
  }

  # All values like in the first example, omitted

  loadbalancer = "35.10.10.10"
}
```

### Access a private cluster via the Humanitec Agent

```hcl
module "my_management_cluster_gke" {
  source = "github.com/humanitec-tf-modules/k8s-management-cluster-gke?ref=vX.Y.Z"
  providers = {
    humanitec  = humanitec
    helm       = helm
    kubernetes = kubernetes
    google     = google
  }

  # All values like in the first example, omitted

  # Access the cluster through the Humanitec Agent (this is the default)
  enable_agent = true
  # Use the private endpoint of the cluster control plane
  internal_ip = true
}
```

### Customize the IAM custom role

```hcl
module "my_management_cluster_gke" {
  source = "github.com/humanitec-tf-modules/k8s-management-cluster-gke?ref=vX.Y.Z"
  providers = {
    humanitec  = humanitec
    helm       = helm
    kubernetes = kubernetes
    google     = google
  }

  # All values like in the first example, omitted

  iam_role_id    = "humanitecGkeAccessMyCluster"
  iam_role_title = "Humanitec GKE access to my-gke-cluster"
}
```

### Impersonate a Google service account for the Operator

```hcl
module "my_management_cluster_gke" {
  source = "github.com/humanitec-tf-modules/k8s-management-cluster-gke?ref=vX.Y.Z"
  providers = {
    humanitec  = humanitec
    helm       = helm
    kubernetes = kubernetes
    google     = google
  }

  # All values like in the first example, omitted

  # Email address of the Google service account the Operator impersonates via Workload Identity Federation for GKE
  operator_gcp_service_account_email = "humanitec-operator@my-gcp-project.iam.gserviceaccount.com"
}
```

The Google service account must allow the Operator Kubernetes service account to impersonate it via the role `roles/iam.workloadIdentityUser`. The [Google Cloud Secret Manager secret store module](https://github.com/humanitec-tf-modules/secret-store-gcpsm) can create this binding.

### Enable authentication for Drivers with your own key pair

```hcl
module "my_management_cluster_gke" {
  source = "github.com/humanitec-tf-modules/k8s-management-cluster-gke?ref=vX.Y.Z"
  providers = {
    humanitec  = humanitec
    helm       = helm
    kubernetes = kubernetes
    google     = google
  }

  # Cluster values omitted

  enable_driver_authentication = true
  humanitec_org_id             = "my-org"
  operator_private_key         = "-----BEGIN PRIVATE KEY----- ..."
  operator_public_key          = "-----BEGIN PUBLIC KEY----- ..."
  helm_release_version         = "X.Y.Z"
}
```

### Enable authentication for Drivers with a convenience key pair

The module can generate a key pair for convenience, but we do not recommend this for production use because the module stores the private key in the Terraform state. Use an external key management solution and pass in the keys instead as shown in the preceding example.

```hcl
module "my_management_cluster_gke" {
  source = "github.com/humanitec-tf-modules/k8s-management-cluster-gke?ref=vX.Y.Z"
  providers = {
    humanitec  = humanitec
    helm       = helm
    kubernetes = kubernetes
    google     = google
  }

  # Cluster values omitted

  enable_driver_authentication = true
  humanitec_org_id             = "my-org"
}
```

### Set Helm chart values

If you set `operator_gcp_service_account_email`, the module sets the service account annotation `iam.gke.io/gcp-service-account` with that email address as a Helm chart value for the Operator. Otherwise, the module sets no Helm chart values.

You can set any other Helm chart value through `helm_release_values` or `helm_release_set`. The module merges the values in `helm_release_values` with the annotation values. If both set the same key, your value takes precedence.

This example impersonates a Google service account and adds a Pod label:

```hcl
module "my_management_cluster_gke" {
  source = "github.com/humanitec-tf-modules/k8s-management-cluster-gke?ref=vX.Y.Z"
  providers = {
    humanitec  = humanitec
    helm       = helm
    kubernetes = kubernetes
    google     = google
  }

  # Cluster values omitted

  # Email address of the Google service account the Operator impersonates
  operator_gcp_service_account_email = "humanitec-operator@my-gcp-project.iam.gserviceaccount.com"

  # Additional Helm chart values, merged with the annotation values
  helm_release_values = [
    yamlencode({
      controllerManager = {
        podLabels = {
          "team" = "platform"
        }
      }
    }),
  ]
}
```

### Self-hosting the Helm chart

```hcl
module "my_management_cluster_gke" {
  source = "github.com/humanitec-tf-modules/k8s-management-cluster-gke?ref=vX.Y.Z"
  providers = {
    humanitec  = humanitec
    helm       = helm
    kubernetes = kubernetes
    google     = google
  }

  # Cluster values omitted

  helm_release_repository         = "oci://my-registry.example.com/my/helm/charts"
  helm_release_chart              = "humanitec-operator"
  helm_release_version            = "X.Y.Z"
  helm_release_repository_ca_file = "..."
  # Use other "helm_release_repository_*" variables as required to access your own registry
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 7.0.0, < 9.0.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 3.0 |
| <a name="requirement_humanitec"></a> [humanitec](#requirement\_humanitec) | ~> 1.9 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 3 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.3 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_management_cluster"></a> [management\_cluster](#module\_management\_cluster) | github.com/humanitec-tf-modules/k8s-management-cluster | v1.0.0 |

## Resources

| Name | Type |
|------|------|
| [google_project_iam_custom_role.orchestrator_cluster_access](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_custom_role) | resource |
| [google_project_iam_member.orchestrator_cluster_access](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [random_string.iam_role_id_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [google_client_config.current](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/client_config) | data source |
| [google_container_cluster.gke](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/container_cluster) | data source |
| [google_service_account.cloud_account](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/service_account) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cloud_account_id"></a> [cloud\_account\_id](#input\_cloud\_account\_id) | ID of the GCP Cloud Account the Orchestrator uses to access the cluster. | `string` | n/a | yes |
| <a name="input_cloud_account_service_account_email"></a> [cloud\_account\_service\_account\_email](#input\_cloud\_account\_service\_account\_email) | Email address of the Google service account behind the GCP Cloud Account the Orchestrator uses to access the cluster, e.g. `humanitec-orchestrator@my-project.iam.gserviceaccount.com`. The module grants it the IAM custom role allowing access to the cluster, and binds the Kubernetes ClusterRole `cluster_role_name` to it. | `string` | n/a | yes |
| <a name="input_cloud_account_type"></a> [cloud\_account\_type](#input\_cloud\_account\_type) | Type of the Cloud Account referenced by `cloud_account_id`, which determines the Kubernetes user name of its Google service account. `gcp-identity` (GCP Service account impersonation, recommended): the user name is the email address of the service account. `gcp` (GCP Service account keys): the user name is the OAuth client ID of the service account, which the module reads from the service account. See https://developer.humanitec.com/platform-orchestrator/docs/platform-orchestrator/security/cloud-accounts/gcp/ | `string` | `"gcp-identity"` | no |
| <a name="input_cluster_role_name"></a> [cluster\_role\_name](#input\_cluster\_role\_name) | Name of the Kubernetes ClusterRole and ClusterRoleBinding granting the Orchestrator access to the cluster. | `string` | `"humanitec-deploy-access"` | no |
| <a name="input_cluster_secrets"></a> [cluster\_secrets](#input\_cluster\_secrets) | Driver input secrets of the Resource Definition for the Driver `humanitec/k8s-cluster-gke`. See the Driver documentation at https://developer.humanitec.com/platform-orchestrator/docs/integration-and-extensions/drivers/k8-drivers/. If `enable_agent` is `true`, the module adds the key `agent_url`. | `any` | `{}` | no |
| <a name="input_enable_agent"></a> [enable\_agent](#input\_enable\_agent) | Access the cluster through the Humanitec Agent. Adds the secret `agent_url`, referencing the output `url` of the Resource `agent#agent`, to the Resource Definition. Requires a Resource Definition of type `agent` matching the same Deployments as the cluster. See https://developer.humanitec.com/platform-orchestrator/docs/integration-and-extensions/humanitec-agent/overview/ | `bool` | `true` | no |
| <a name="input_enable_driver_authentication"></a> [enable\_driver\_authentication](#input\_enable\_driver\_authentication) | Enable authentication of the Operator against Humanitec-hosted Drivers. Requires `humanitec_org_id`. Registers the public key in the Humanitec Organization and stores the private key in the Kubernetes Secret `humanitec-operator-private-key` in the namespace `helm_release_namespace`. Pass in a key pair via `operator_private_key` and `operator_public_key`, or leave both unset to generate a convenience key pair. Only required if you use Humanitec-hosted Drivers. See https://developer.humanitec.com/platform-orchestrator/docs/integration-and-extensions/humanitec-operator/installation/#configure-authentication-for-drivers | `bool` | `false` | no |
| <a name="input_gke_cluster_name"></a> [gke\_cluster\_name](#input\_gke\_cluster\_name) | Name of the existing GKE cluster to use as the Humanitec management cluster. | `string` | n/a | yes |
| <a name="input_gke_location"></a> [gke\_location](#input\_gke\_location) | Location of the GKE cluster, i.e. its zone for a zonal cluster, e.g. `europe-west3-a`, or its region for a regional cluster, e.g. `europe-west3`. The module sets it as the Driver input `zone`. | `string` | n/a | yes |
| <a name="input_gke_project_id"></a> [gke\_project\_id](#input\_gke\_project\_id) | ID of the Google Cloud project hosting the GKE cluster. If not set, the project of the `google` provider that is passed in to the module is used. The module creates the IAM custom role and its role binding in this project. | `string` | `null` | no |
| <a name="input_helm_release_atomic"></a> [helm\_release\_atomic](#input\_helm\_release\_atomic) | If set, installation process purges chart on fail. The wait flag will be set automatically if atomic is used. Defaults to `false`. | `bool` | `null` | no |
| <a name="input_helm_release_chart"></a> [helm\_release\_chart](#input\_helm\_release\_chart) | Chart name to be installed. A path may be used. | `string` | `"humanitec-operator"` | no |
| <a name="input_helm_release_cleanup_on_fail"></a> [helm\_release\_cleanup\_on\_fail](#input\_helm\_release\_cleanup\_on\_fail) | Allow deletion of new resources created in this upgrade when upgrade fails. Defaults to `false`. | `bool` | `null` | no |
| <a name="input_helm_release_create_namespace"></a> [helm\_release\_create\_namespace](#input\_helm\_release\_create\_namespace) | Choose whether to create the Kubernetes namespace | `bool` | `true` | no |
| <a name="input_helm_release_dependency_update"></a> [helm\_release\_dependency\_update](#input\_helm\_release\_dependency\_update) | Run helm dependency update before installing the chart. Defaults to `false`. | `bool` | `null` | no |
| <a name="input_helm_release_description"></a> [helm\_release\_description](#input\_helm\_release\_description) | Add a custom description | `string` | `null` | no |
| <a name="input_helm_release_devel"></a> [helm\_release\_devel](#input\_helm\_release\_devel) | Use chart development versions, too. Equivalent to version '>0.0.0-0'. If `helm_release_version` is set, this is ignored | `bool` | `null` | no |
| <a name="input_helm_release_disable_crd_hooks"></a> [helm\_release\_disable\_crd\_hooks](#input\_helm\_release\_disable\_crd\_hooks) | Prevent CRD hooks from running, but run other hooks. See helm install --no-crd-hook | `bool` | `null` | no |
| <a name="input_helm_release_disable_openapi_validation"></a> [helm\_release\_disable\_openapi\_validation](#input\_helm\_release\_disable\_openapi\_validation) | If set, the installation process will not validate rendered templates against the Kubernetes OpenAPI Schema. Defaults to `false`. | `bool` | `null` | no |
| <a name="input_helm_release_disable_webhooks"></a> [helm\_release\_disable\_webhooks](#input\_helm\_release\_disable\_webhooks) | Prevent hooks from running. Defaults to `false`. | `bool` | `null` | no |
| <a name="input_helm_release_force_update"></a> [helm\_release\_force\_update](#input\_helm\_release\_force\_update) | Force resource update through delete/recreate if needed. Defaults to `false`. | `bool` | `null` | no |
| <a name="input_helm_release_keyring"></a> [helm\_release\_keyring](#input\_helm\_release\_keyring) | Location of public keys used for verification. Used only if `helm_release_verify` is true. Defaults to `/.gnupg/pubring.gpg` in the location set by `home`. | `string` | `null` | no |
| <a name="input_helm_release_lint"></a> [helm\_release\_lint](#input\_helm\_release\_lint) | Run helm lint when planning. Defaults to `false`. | `bool` | `null` | no |
| <a name="input_helm_release_max_history"></a> [helm\_release\_max\_history](#input\_helm\_release\_max\_history) | Limit the maximum number of revisions saved per release. Use 0 for no limit. Defaults to 0 (no limit). | `number` | `null` | no |
| <a name="input_helm_release_name"></a> [helm\_release\_name](#input\_helm\_release\_name) | Name of the Helm release for the Operator | `string` | `"humanitec-operator"` | no |
| <a name="input_helm_release_namespace"></a> [helm\_release\_namespace](#input\_helm\_release\_namespace) | Kubernetes namespace where to install the Operator | `string` | `"humanitec-operator-system"` | no |
| <a name="input_helm_release_pass_credentials"></a> [helm\_release\_pass\_credentials](#input\_helm\_release\_pass\_credentials) | Pass credentials to all domains. Defaults to `false`. | `bool` | `null` | no |
| <a name="input_helm_release_postrender"></a> [helm\_release\_postrender](#input\_helm\_release\_postrender) | Postrender command configuration. | <pre>object({<br/>    binary_path = string<br/>    args        = optional(list(string))<br/>  })</pre> | `null` | no |
| <a name="input_helm_release_recreate_pods"></a> [helm\_release\_recreate\_pods](#input\_helm\_release\_recreate\_pods) | Perform pods restart during upgrade/rollback. Defaults to `false`. | `bool` | `null` | no |
| <a name="input_helm_release_render_subchart_notes"></a> [helm\_release\_render\_subchart\_notes](#input\_helm\_release\_render\_subchart\_notes) | If set, render subchart notes along with the parent. Defaults to `true`. | `bool` | `null` | no |
| <a name="input_helm_release_replace"></a> [helm\_release\_replace](#input\_helm\_release\_replace) | Re-use the given name, even if that name is already used. This is unsafe in production. Defaults to `false`. | `bool` | `null` | no |
| <a name="input_helm_release_repository"></a> [helm\_release\_repository](#input\_helm\_release\_repository) | Repository where to locate the requested chart. If is a URL the chart is installed without installing the repository. Set it to `null` for a local chart. | `string` | `"oci://ghcr.io/humanitec/charts"` | no |
| <a name="input_helm_release_repository_ca_file"></a> [helm\_release\_repository\_ca\_file](#input\_helm\_release\_repository\_ca\_file) | The repositories CA File | `string` | `null` | no |
| <a name="input_helm_release_repository_cert_file"></a> [helm\_release\_repository\_cert\_file](#input\_helm\_release\_repository\_cert\_file) | The repositories cert file | `string` | `null` | no |
| <a name="input_helm_release_repository_key_file"></a> [helm\_release\_repository\_key\_file](#input\_helm\_release\_repository\_key\_file) | The repositories cert key file | `string` | `null` | no |
| <a name="input_helm_release_repository_password"></a> [helm\_release\_repository\_password](#input\_helm\_release\_repository\_password) | Password for HTTP basic authentication | `string` | `null` | no |
| <a name="input_helm_release_repository_username"></a> [helm\_release\_repository\_username](#input\_helm\_release\_repository\_username) | Username for HTTP basic authentication | `string` | `null` | no |
| <a name="input_helm_release_reset_values"></a> [helm\_release\_reset\_values](#input\_helm\_release\_reset\_values) | When upgrading, reset the values to the ones built into the chart. Defaults to `false`. | `bool` | `null` | no |
| <a name="input_helm_release_reuse_values"></a> [helm\_release\_reuse\_values](#input\_helm\_release\_reuse\_values) | When upgrading, reuse the last release's values and merge in any overrides. If 'helm\_release\_reset\_values' is specified, this is ignored. Defaults to `false`. | `bool` | `null` | no |
| <a name="input_helm_release_set"></a> [helm\_release\_set](#input\_helm\_release\_set) | Custom values to be merged with the values. | <pre>list(object({<br/>    name  = string<br/>    value = optional(string)<br/>    type  = optional(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_helm_release_set_list"></a> [helm\_release\_set\_list](#input\_helm\_release\_set\_list) | Custom list values to be merged with the values. | <pre>list(object({<br/>    name  = string<br/>    value = list(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_helm_release_set_sensitive"></a> [helm\_release\_set\_sensitive](#input\_helm\_release\_set\_sensitive) | Custom sensitive values to be merged with the values. | <pre>list(object({<br/>    name  = string<br/>    value = string<br/>    type  = optional(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_helm_release_set_wo"></a> [helm\_release\_set\_wo](#input\_helm\_release\_set\_wo) | Custom values to be merged with the values. This is the same as "helm\_release\_set" but write-only. | <pre>list(object({<br/>    name  = string<br/>    value = string<br/>    type  = optional(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_helm_release_set_wo_revision"></a> [helm\_release\_set\_wo\_revision](#input\_helm\_release\_set\_wo\_revision) | The current revision of the write-only "helm\_release\_set\_wo" attribute. Incrementing this integer value will cause Terraform to update the write-only value. | `number` | `null` | no |
| <a name="input_helm_release_skip_crds"></a> [helm\_release\_skip\_crds](#input\_helm\_release\_skip\_crds) | If set, no CRDs will be installed. By default, CRDs are installed if not already present. Defaults to `false`. | `bool` | `null` | no |
| <a name="input_helm_release_take_ownership"></a> [helm\_release\_take\_ownership](#input\_helm\_release\_take\_ownership) | If set, allows Helm to adopt existing resources not marked as managed by the release. Defaults to `false`. | `bool` | `null` | no |
| <a name="input_helm_release_timeout"></a> [helm\_release\_timeout](#input\_helm\_release\_timeout) | Time in seconds to wait for any individual Kubernetes operation. Defaults to 300 seconds. | `number` | `null` | no |
| <a name="input_helm_release_upgrade_install"></a> [helm\_release\_upgrade\_install](#input\_helm\_release\_upgrade\_install) | If true, the provider will install the release at the specified version even if a release not controlled by the provider is present: this is equivalent to running 'helm upgrade --install' with the Helm CLI. WARNING: this may not be suitable for production use -- see the 'Upgrade Mode' note in the provider documentation. Defaults to `false`. | `bool` | `null` | no |
| <a name="input_helm_release_values"></a> [helm\_release\_values](#input\_helm\_release\_values) | List of values in raw yaml format to pass to Helm. If `operator_gcp_service_account_email` is set, the module prepends the service account annotation values, so values passed in here are merged with them and take precedence. | `list(string)` | `null` | no |
| <a name="input_helm_release_verify"></a> [helm\_release\_verify](#input\_helm\_release\_verify) | Verify the package before installing it. Defaults to `false`. | `bool` | `null` | no |
| <a name="input_helm_release_version"></a> [helm\_release\_version](#input\_helm\_release\_version) | Chart version to use for the Operator installation in the format `X.Y.Z`. If this is not specified, the latest version is installed. | `string` | `null` | no |
| <a name="input_helm_release_wait"></a> [helm\_release\_wait](#input\_helm\_release\_wait) | Will wait until all resources are in a ready state before marking the release as successful. Defaults to `true`. | `bool` | `null` | no |
| <a name="input_helm_release_wait_for_jobs"></a> [helm\_release\_wait\_for\_jobs](#input\_helm\_release\_wait\_for\_jobs) | If wait is enabled, will wait until all Jobs have been completed before marking the release as successful. Defaults to `false`. | `bool` | `null` | no |
| <a name="input_humanitec_org_id"></a> [humanitec\_org\_id](#input\_humanitec\_org\_id) | Humanitec Organization ID. Required if `enable_driver_authentication` is `true`, ignored otherwise. | `string` | `null` | no |
| <a name="input_iam_role_id"></a> [iam\_role\_id](#input\_iam\_role\_id) | ID of the IAM custom role granting the Cloud Account service account access to the cluster, created in the project `gke_project_id`. If not set, the module generates an ID from the cluster name and a random four-letter suffix. Google Cloud blocks the ID of a deleted custom role for several weeks, so choose a new ID when recreating the role. | `string` | `null` | no |
| <a name="input_iam_role_title"></a> [iam\_role\_title](#input\_iam\_role\_title) | Title of the IAM custom role granting the Cloud Account service account access to the cluster. If not set, a title is derived from the cluster name. | `string` | `null` | no |
| <a name="input_internal_ip"></a> [internal\_ip](#input\_internal\_ip) | Access the cluster via the private endpoint address of its control plane, if the private endpoint is enabled. Set it to `true` if you access a private cluster through the Humanitec Agent. Requires `enable_agent` to be `true`, as the Driver only uses the private endpoint through the Agent. If not set, the Driver default applies. | `bool` | `null` | no |
| <a name="input_loadbalancer"></a> [loadbalancer](#input\_loadbalancer) | The IP or DNS name representing the cluster load balancer. | `string` | `null` | no |
| <a name="input_operator_gcp_service_account_email"></a> [operator\_gcp\_service\_account\_email](#input\_operator\_gcp\_service\_account\_email) | Email address of a Google service account the Operator impersonates via Workload Identity Federation for GKE. If set, the module adds the Helm chart value for the service account annotation `iam.gke.io/gcp-service-account` before any values passed in via `helm_release_values`. Leave unset if the Operator uses its Kubernetes service account as an IAM principal directly, which requires no Helm chart values, or no Google Cloud identity at all. See https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity | `string` | `null` | no |
| <a name="input_operator_private_key"></a> [operator\_private\_key](#input\_operator\_private\_key) | Private key for the Humanitec Operator authentication against Humanitec-hosted Drivers. Must be a multiline string starting with -----BEGIN PRIVATE KEY----- and having a final line break. Both or neither of `operator_public_key` and `operator_private_key` must be set, and only if `enable_driver_authentication` is `true`. If not set while `enable_driver_authentication` is `true`, a convenience key pair will be generated using a `tls_private_key` resource and stored in the Terraform state, but this is not recommended for production use. | `string` | `null` | no |
| <a name="input_operator_public_key"></a> [operator\_public\_key](#input\_operator\_public\_key) | Public key for the Humanitec Operator authentication against Humanitec-hosted Drivers. Must be a multiline string starting with -----BEGIN PUBLIC KEY----- and having a final line break. Both or neither of `operator_public_key` and `operator_private_key` must be set, and only if `enable_driver_authentication` is `true`. If not set while `enable_driver_authentication` is `true`, a convenience key pair will be generated using a `tls_private_key` resource and stored in the Terraform state, but this is not recommended for production use. | `string` | `null` | no |
| <a name="input_proxy_url"></a> [proxy\_url](#input\_proxy\_url) | The URL of a proxy to use for accessing the cluster API server. Corresponds to the kubeconfig value `proxy-url`. | `string` | `null` | no |
| <a name="input_resource_definition_criteria"></a> [resource\_definition\_criteria](#input\_resource\_definition\_criteria) | Matching Criteria for the Resource Definition, directing Deployments to the cluster. Each entry creates one Matching Criteria. Unset attributes match any value. See https://developer.humanitec.com/platform-orchestrator/docs/platform-orchestrator/resources/resource-definitions/#matching-criteria | <pre>list(object({<br/>    app_id   = optional(string)<br/>    env_id   = optional(string)<br/>    env_type = optional(string)<br/>    res_id   = optional(string)<br/>    class    = optional(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_resource_definition_id"></a> [resource\_definition\_id](#input\_resource\_definition\_id) | ID of the Resource Definition of type `k8s-cluster` representing the cluster. Must be unique within the Humanitec Organization. Defaults to `<resource_definition_id_prefix>-<suffix>` with a random suffix of four lowercase alphanumeric characters. | `string` | `null` | no |
| <a name="input_resource_definition_id_prefix"></a> [resource\_definition\_id\_prefix](#input\_resource\_definition\_id\_prefix) | Prefix of the generated `resource_definition_id`. Ignored if `resource_definition_id` is set. | `string` | `"management-cluster-gke"` | no |
| <a name="input_resource_definition_name"></a> [resource\_definition\_name](#input\_resource\_definition\_name) | Display name of the Resource Definition. Defaults to `resource_definition_id`. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cluster_access_subject"></a> [cluster\_access\_subject](#output\_cluster\_access\_subject) | Subject of the Kubernetes ClusterRoleBinding, i.e. the identity the Orchestrator uses to access the cluster, as an object with the attributes `kind` and `name` |
| <a name="output_cluster_role_binding_name"></a> [cluster\_role\_binding\_name](#output\_cluster\_role\_binding\_name) | Name of the Kubernetes ClusterRoleBinding granting the Orchestrator access to the cluster |
| <a name="output_cluster_role_name"></a> [cluster\_role\_name](#output\_cluster\_role\_name) | Name of the Kubernetes ClusterRole granting the Orchestrator access to the cluster |
| <a name="output_gke_cluster_id"></a> [gke\_cluster\_id](#output\_gke\_cluster\_id) | ID of the GKE cluster, i.e. `projects/<project>/locations/<location>/clusters/<name>`. |
| <a name="output_gke_project_id"></a> [gke\_project\_id](#output\_gke\_project\_id) | ID of the Google Cloud project hosting the GKE cluster, either passed in or the project of the `google` provider. |
| <a name="output_helm_release_chart"></a> [helm\_release\_chart](#output\_helm\_release\_chart) | Chart name used for the Operator Helm chart |
| <a name="output_helm_release_name"></a> [helm\_release\_name](#output\_helm\_release\_name) | Name of the Helm release for the Operator |
| <a name="output_helm_release_namespace"></a> [helm\_release\_namespace](#output\_helm\_release\_namespace) | Kubernetes namespace where the Operator is installed |
| <a name="output_helm_release_repository"></a> [helm\_release\_repository](#output\_helm\_release\_repository) | Repository used for the Operator Helm chart |
| <a name="output_helm_release_version"></a> [helm\_release\_version](#output\_helm\_release\_version) | Chart version used for the Operator installation |
| <a name="output_iam_member"></a> [iam\_member](#output\_iam\_member) | IAM member of the Cloud Account service account the module grants the IAM custom role on the project of the cluster, i.e. `serviceAccount:<email>`. |
| <a name="output_iam_role_id"></a> [iam\_role\_id](#output\_iam\_role\_id) | ID of the IAM custom role granting the Cloud Account service account access to the cluster. |
| <a name="output_iam_role_name"></a> [iam\_role\_name](#output\_iam\_role\_name) | Full name of the IAM custom role granting the Cloud Account service account access to the cluster, i.e. `projects/<project>/roles/<role id>`. |
| <a name="output_operator_private_key"></a> [operator\_private\_key](#output\_operator\_private\_key) | Private key of the Operator in PEM format. `null` if `enable_driver_authentication` is `false`. |
| <a name="output_operator_private_key_secret_name"></a> [operator\_private\_key\_secret\_name](#output\_operator\_private\_key\_secret\_name) | Name of the Kubernetes Secret holding the private key of the Operator. `null` if `enable_driver_authentication` is `false`. |
| <a name="output_operator_public_key"></a> [operator\_public\_key](#output\_operator\_public\_key) | Public key of the Operator in PEM format. `null` if `enable_driver_authentication` is `false`. |
| <a name="output_operator_public_key_fingerprint"></a> [operator\_public\_key\_fingerprint](#output\_operator\_public\_key\_fingerprint) | Fingerprint (SHA256 hash of the DER representation) of the public key registered in the Humanitec Organization. Use it to debug authentication against Humanitec-hosted Drivers. `null` if `enable_driver_authentication` is `false`. |
| <a name="output_operator_public_key_id"></a> [operator\_public\_key\_id](#output\_operator\_public\_key\_id) | ID of the public key registered in the Humanitec Organization. `null` if `enable_driver_authentication` is `false`. |
| <a name="output_resource_definition_driver_type"></a> [resource\_definition\_driver\_type](#output\_resource\_definition\_driver\_type) | Driver type of the Resource Definition |
| <a name="output_resource_definition_id"></a> [resource\_definition\_id](#output\_resource\_definition\_id) | ID of the Resource Definition of type `k8s-cluster` representing the cluster |
<!-- END_TF_DOCS -->
