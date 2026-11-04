# Facts confirm each host is Windows Server 2022 or 2025 before anything is installed.
data "conn3x_host" "facts" {
  for_each = var.hosts

  allow_windows = true

  ssh {
    host             = try(each.value.address, each.value)
    host_key         = try(each.value.host_key, null)
    user             = try(each.value.user, var.ssh_user)
    port             = try(each.value.port, var.ssh_port)
    private_key_file = try(each.value.private_key_file, var.ssh_private_key_file)
    jump_hosts       = try(each.value.jump_hosts, null)
    known_hosts_file = var.ssh_known_hosts_file
  }

  lifecycle {
    postcondition {
      condition     = self.os_family == "windows" && contains(["2022", "2025"], self.windows.release) && self.arch == "x86_64"
      error_message = "circuit-iis runs on x86_64 Windows Server 2022 or 2025, the releases it is tested on."
    }
  }
}

locals {
  root = "C:\\inetpub\\${var.site_name}"

  # The GAC copy IIS installs, read-only: no IIS: drive, which can change
  # things the first time it's used.
  mwa          = "Microsoft.Web.Administration, Version=7.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35"
  default_stop = <<-PS
    $f = $env:windir + '\System32\inetsrv\config\applicationHost.config'
    if (-not (Test-Path -LiteralPath $f)) { return $false }
    [void][Reflection.Assembly]::Load('${local.mwa}')
    $s = ([Microsoft.Web.Administration.ServerManager]::new($true, $f)).Sites['Default Web Site']
    (-not $s) -or ($s.State -eq 'Stopped' -and -not $s.ServerAutoStart)
  PS

  # IIS's own URL Rewrite 2.1 MSI from Microsoft, pinned.
  url_rewrite = {
    product_code = "{9BCA2118-F753-4A1E-BCF3-5A820729965C}"
    url          = "https://download.microsoft.com/download/1/2/8/128E2E22-C1B9-44A4-BE2A-5859ED1D4592/rewrite_amd64_en-US.msi"
    sha256       = "37342ff2f585f263f34f48e9de59eb1051d61015a8e967dbde4075716230a32a"
  }
}

circuit "iis" {
  hosts = var.hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = true
  }

  step "web_server" {
    windows_feature {
      name = "Web-Server"
    }
  }

  # Part of a plain Web-Server install, but not of every image that has IIS on
  # already. Without it IIS answers 200 with an empty page.
  step "static_content" {
    windows_feature {
      name = "Web-Static-Content"
    }
  }

  step "restart_if_needed" {
    windows_reboot {
      only_if_pending = true
    }
  }

  # Default Web Site holds port 80 for every host name, so the site below
  # couldn't start there. Stopped, it stays stopped after a reboot.
  step "default_site_stopped" {
    for_each = var.stop_default_site ? { stop = true } : {}

    windows_powershell {
      script = <<-PS
        [void][Reflection.Assembly]::Load('${local.mwa}')
        $sm = New-Object Microsoft.Web.Administration.ServerManager
        $s = $sm.Sites['Default Web Site']
        if ($s) {
          $s.ServerAutoStart = $false
          $sm.CommitChanges()
          if ($s.State -ne 'Stopped') { [void]$s.Stop() }
        }
      PS
      unless = local.default_stop
    }
  }

  step "url_rewrite" {
    for_each = var.url_rewrite ? { msi = true } : {}

    windows_package {
      product_code = local.url_rewrite.product_code
      url          = local.url_rewrite.url
      sha256       = local.url_rewrite.sha256
    }
  }

  step "app_pool" {
    windows_iis_app_pool {
      name                    = var.site_name
      managed_runtime_version = ""
    }
  }

  # IIS refuses to serve a folder anyone but administrators can change, so it
  # has its own rules from the moment it exists: the pools (IIS_IUSRS) and
  # anonymous visitors (IUSR) may only read.
  step "site_folder" {
    windows_directory {
      path = local.root

      acl {
        principal = "S-1-5-18"
        rights    = ["FullControl"]
      }
      acl {
        principal = "S-1-5-32-544"
        rights    = ["FullControl"]
      }
      acl {
        principal = "S-1-5-32-568"
        rights    = ["ReadAndExecute"]
      }
      acl {
        principal = "S-1-5-17"
        rights    = ["ReadAndExecute"]
      }
    }
  }

  step "pages" {
    for_each = var.pages

    windows_file {
      path    = "${local.root}\\${item.key}"
      content = item.value
    }
  }

  step "site" {
    windows_iis_site {
      name          = var.site_name
      physical_path = local.root
      app_pool      = var.site_name

      binding {
        port        = var.port
        host_header = var.host_header == "" ? null : var.host_header
      }
    }
  }

  step "firewall" {
    for_each = var.open_firewall ? { port = var.port } : {}

    windows_firewall_rule {
      name        = "circuit-iis ${var.site_name} http"
      protocol    = "tcp"
      local_ports = [tostring(item.value)]
    }
  }

  # A fixed, quiet time instead of IIS's every 29 hours from start.
  step "nightly_recycle" {
    for_each = var.recycle_at == null ? {} : { at = var.recycle_at }

    windows_scheduled_task {
      name      = "circuit-iis recycle ${var.site_name}"
      path      = "\\Conn3x\\"
      execute   = "C:\\Windows\\System32\\inetsrv\\appcmd.exe"
      arguments = "recycle apppool /apppool.name:${var.site_name}"
      user      = "SYSTEM"

      trigger {
        type = "daily"
        at   = "2026-01-01T${item.value}:00"
      }
    }
  }
}
