data "helm_template" "spegel_default" {
  count     = var.enable_spegel ? 1 : 0
  name      = "spegel"
  namespace = "spegel"

  repository   = "oci://ghcr.io/spegel-org/helm-charts"
  chart        = "spegel"
  version      = var.spegel_version
  kube_version = var.kubernetes_version

  set {
    name  = "spegel.containerdRegistryConfigPath"
    value = "/etc/cri/conf.d/hosts"
  }
}

data "helm_template" "spegel_from_values" {
  count     = var.enable_spegel && var.spegel_values != null ? 1 : 0
  name      = "spegel"
  namespace = "spegel"

  repository   = "oci://ghcr.io/spegel-org/helm-charts"
  chart        = "spegel"
  version      = var.spegel_version
  kube_version = var.kubernetes_version
  values       = var.spegel_values
}

data "kubectl_file_documents" "spegel" {
  content = coalesce(
    can(data.helm_template.spegel_from_values[0].manifest) ? data.helm_template.spegel_from_values[0].manifest : null,
    can(data.helm_template.spegel_default[0].manifest) ? data.helm_template.spegel_default[0].manifest : null
  )
}

resource "kubectl_manifest" "apply_spegel_ns" {
  count      = var.control_plane_count > 0 && var.enable_spegel ? 1 : 0
  yaml_body = <<YAML
apiVersion: v1
kind: Namespace
metadata:
  labels:
    pod-security.kubernetes.io/enforce: privileged
  name: spegel
YAML
  apply_only = true
  depends_on = [data.http.talos_health]
}

resource "kubectl_manifest" "apply_spegel" {
  for_each   = var.control_plane_count > 0 && var.enable_spegel ? data.kubectl_file_documents.spegel.manifests : {}
  yaml_body  = each.value
  apply_only = true
  depends_on = [
    data.http.talos_health,
    kubectl_manifest.apply_spegel_ns,
    ]
}
