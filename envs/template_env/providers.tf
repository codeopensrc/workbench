terraform {
  required_providers {
    helm = {
      source = "hashicorp/helm"
      version = "2.9.0"
    }
  }
}

provider "helm" {
    kubernetes {
        config_path = var.local_kubeconfig_path
        config_context = local.root_domain_name
    }
    experiments {
        manifest = true
    }
}
#provider "helm" {
#  kubernetes {
#    host     = "https://cluster_endpoint:port"
#
#    client_certificate     = file("~/.kube/client-cert.pem")
#    client_key             = file("~/.kube/client-key.pem")
#    cluster_ca_certificate = file("~/.kube/cluster-ca-cert.pem")
#  }
#  experiments {
#    manifest = true
#  }
#}
#provider "helm" {
#  kubernetes {
#    host                   = var.cluster_endpoint
#    cluster_ca_certificate = base64decode(var.cluster_ca_cert)
#    exec {
#      api_version = "client.authentication.k8s.io/v1beta1"
#      args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
#      command     = "aws"
#    }
#  }
#  experiments {
#    manifest = true
#  }
#}
