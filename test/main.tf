# Applied by CI to the windows-2022 and windows-2025 runners themselves, over loopback OpenSSH.
# ci.auto.tfvars is written by the workflow.

variable "user" {
  type = string
}

variable "key_file" {
  type = string
}

variable "host_key" {
  type = string
}

module "iis" {
  source = "../"

  hosts = {
    runner = {
      address  = "127.0.0.1"
      host_key = var.host_key
    }
  }
  ssh_user             = var.user
  ssh_private_key_file = var.key_file

  site_name   = "citest"
  host_header = "circuit-iis.test"
  # The runner's Default Web Site may serve other things; leave it running and
  # answer on a host name instead.
  stop_default_site = false
  url_rewrite       = true
  recycle_at        = "03:30"
  pages = {
    "index.html" = "<p>circuit-iis test page</p>\n"
  }
}
