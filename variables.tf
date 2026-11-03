variable "hosts" {
  type        = any
  description = "Hosts to configure: a map of names to addresses, or to host objects with an address and optional host_key, user, port, private_key_file or jump_hosts."
}

variable "ssh_user" {
  type        = string
  default     = "Administrator"
  description = "User to log in as. It must be an administrator."
}

variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port."
}

variable "ssh_private_key_file" {
  type        = string
  default     = null
  description = "Path to a private key. When null, Conn3x uses the SSH agent."
}

variable "ssh_known_hosts_file" {
  type        = string
  default     = null
  description = "known_hosts file to check host keys against. When null, ~/.ssh/known_hosts."
}

variable "site_name" {
  type        = string
  default     = "conn3x"
  description = "Name of the IIS site and of its app pool."

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,47}$", var.site_name))
    error_message = "site_name must start with a letter or digit and use only letters, digits, _ and -, up to 48 characters."
  }
}

variable "port" {
  type        = number
  default     = 80
  description = "Port the site listens on, over http."

  validation {
    condition     = var.port >= 1 && var.port <= 65535 && floor(var.port) == var.port
    error_message = "port must be a whole number from 1 to 65535."
  }
}

variable "host_header" {
  type        = string
  default     = ""
  description = "Host name the site answers to, such as www.example.com. Empty answers any name."
}

variable "pages" {
  type        = map(string)
  default     = { "index.html" = "<!doctype html>\n<title>IIS</title>\n<p>Served by IIS, set up by Conn3x.</p>\n" }
  description = "Files to write into the site's folder, by file name. Plain files only, no subfolders. Conn3x leaves other files in the folder alone."

  validation {
    condition     = alltrue([for k in keys(var.pages) : can(regex("^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$", k)) && !endswith(k, ".")])
    error_message = "Each page needs a plain file name: letters, digits, ., _ and -, not ending in a dot."
  }
}

variable "stop_default_site" {
  type        = bool
  default     = true
  description = "Stop IIS's Default Web Site, which otherwise holds port 80 for every host name. It isn't deleted."
}

variable "open_firewall" {
  type        = bool
  default     = true
  description = "Open port in Windows Firewall, from anywhere. Set false to manage the firewall yourself."
}

variable "url_rewrite" {
  type        = bool
  default     = false
  description = "Install Microsoft's IIS URL Rewrite Module 2.1 from download.microsoft.com, checked against its SHA-256."
}

variable "recycle_at" {
  type        = string
  default     = null
  description = "Recycle the app pool every day at this local time on the host, such as \"03:30\", through a scheduled task. Null leaves IIS's own recycling, every 29 hours, as the only one."

  validation {
    condition     = var.recycle_at == null || can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.recycle_at))
    error_message = "recycle_at must be a 24-hour time such as \"03:30\"."
  }
}
