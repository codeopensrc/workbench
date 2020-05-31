
variable "active_env_provider" {}
variable "server_name_prefix" {}
variable "region" { default = "" }

variable "do_ssh_fingerprint" {}

variable "admin_servers" {}
variable "leader_servers" {}
variable "db_servers" {}
variable "build_servers" {}
variable "web_servers" {}
variable "dev_servers" {}
variable "legacy_servers" {}
variable "mongo_servers" {}
variable "pg_servers" {}
variable "redis_servers" {}

variable "do_admin_size" {}
variable "do_leader_size" {}
variable "do_db_size" {}
variable "do_build_size" {}
variable "do_web_size" {}
variable "do_dev_size" {}
variable "do_legacy_size" {}
variable "do_mongo_size" {}
variable "do_pg_size" {}
variable "do_redis_size" {}

variable "app_ips" { default = [] }
variable "station_ips" { default = [] }
