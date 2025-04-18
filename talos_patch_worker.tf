locals {
  # Define a dummy worker entry for when count is 0
  dummy_workers = var.worker_count == 0 ? [{
    index              = 0
    name               = "dummy-worker-0"
    ipv4_public        = "0.0.0.0"                           # Fallback
    ipv6_public        = null                                # Fallback
    ipv6_public_subnet = null                                # Fallback
    ipv4_private       = cidrhost(local.node_ipv4_cidr, 200) # Use a predictable dummy private IP
  }] : []

  # Combine real and dummy workers
  merged_workers = concat(local.workers, local.dummy_workers)

  # Generate YAML for all (real or dummy) workers
  worker_yaml = {
    for worker in local.merged_workers : worker.name => {
      machine = {
        install = {
          image = "ghcr.io/siderolabs/installer:${var.talos_version}"
          extraKernelArgs = [
            "ipv6.disable=${var.enable_ipv6 ? 0 : 1}",
          ]
        }
        certSANs = local.cert_SANs
        kubelet = {
          extraArgs = merge(
            {
              "cloud-provider"             = "external"
              "rotate-server-certificates" = true
            },
            var.kubelet_extra_args
          )
          nodeIP = {
            validSubnets = [
              local.node_ipv4_cidr
            ]
          }
        }
        network = {
          extraHostEntries = local.extra_host_entries
          kubespan = {
            enabled = var.enable_kube_span
            advertiseKubernetesNetworks : false # Disabled because of cilium
            mtu : 1370                          # Hcloud has a MTU of 1450 (KubeSpanMTU = UnderlyingMTU - 80)
          }
        }
        kernel = {
          modules = var.kernel_modules_to_load
        }
        sysctls = merge(
          {
            "net.core.somaxconn"          = "65535"
            "net.core.netdev_max_backlog" = "4096"
          },
          var.sysctls_extra_args
        )
        features = {
          hostDNS = {
            enabled              = true
            forwardKubeDNSToHost = true
            resolveMemberNames   = true
          }
        }
        time = {
          servers = [
            "ntp1.hetzner.de",
            "ntp2.hetzner.com",
            "ntp3.hetzner.net",
            "time.cloudflare.com"
          ]
        }
        registries = var.registries
      }
      cluster = {
        network = {
          dnsDomain = var.cluster_domain
          podSubnets = [
            local.pod_ipv4_cidr
          ]
          serviceSubnets = [
            local.service_ipv4_cidr
          ]
          cni = {
            name = "none"
          }
        }
      }
    }
  }
}
