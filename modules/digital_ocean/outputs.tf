output "cluster_info" {
    value = {
        endpoint  = digitalocean_kubernetes_cluster.main.endpoint
        kube_config = digitalocean_kubernetes_cluster.main.kube_config[0]
    }
}
