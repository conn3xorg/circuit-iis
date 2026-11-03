# circuit-iis on Azure

**Experimental.** Windows support in Conn3x is new and may change between releases.

One plan makes a Windows Server 2025 VM on Azure and turns it into an IIS server with circuit-iis: a site on port 80 serving a page from a locked-down folder, the port open in Windows Firewall, URL Rewrite installed, and a nightly app pool recycle. Conn3x installs its own host key at first boot, so it checks the host from the very first connection.

## Run it

You need an Azure subscription, `az login`, and an SSH key. It costs about $0.11 for each hour it's up on `Standard_B2s_v2` in `westus2`, disk and IP included, so destroy it when you're done.

```sh
export ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
export TF_VAR_state_passphrase="$(openssl rand -hex 16)"   # keep this; state needs it
export TF_VAR_admin_cidrs="[\"$(curl -4 -s https://ifconfig.me)/32\"]"
export TF_VAR_admin_public_key_file=~/.ssh/id_ed25519.pub
export TF_VAR_admin_private_key_file=~/.ssh/id_ed25519

conn3x init
conn3x plan -out tfplan
conn3x apply tfplan
curl "$(conn3x output -raw url)"
```

The first apply took about 11 minutes. Run `conn3x plan` again and it reports no changes. Stop the site or edit the page on the host, and `conn3x drift` exits 2 and names it; `conn3x apply` puts it back.

Port 80 is open to `admin_cidrs` only. Set `web_cidrs = ["0.0.0.0/0"]` to open it to everyone.

```sh
conn3x destroy
```

## What to know

- **State holds secrets of Azure's making.** `azurerm` keeps the first admin password and the extension's settings in state, including the host's private key. That's why this example encrypts state. A last step replaces the password, so the copy in state stops being useful. The host key stays useful, so treat state as a secret.
- **SSH is the only way in,** from `admin_cidrs` only. RDP stays closed.
- **Destroying removes the VM and everything in its resource group.**
