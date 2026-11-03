output "site_folder" {
  description = "Folder on each host that the site serves. Only administrators can change it."
  value       = local.root
}

output "url" {
  description = "Address of the site on each host, by host name."
  value       = { for k, v in var.hosts : k => "http://${var.host_header != "" ? var.host_header : try(v.address, v)}${var.port == 80 ? "" : ":${var.port}"}/" }
}
