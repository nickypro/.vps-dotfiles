# Agent box settings, read by the Makefile. Edit in place; after changing
# ACCESS, run `sudo make host-config` again.

# How you reach T3's web UI:
#   tailscale  Only your own devices, over your tailnet. No domain, no certs,
#              nothing open to the internet. Recommended.
#   mtls       https://DOMAIN via nginx. The browser must present a client
#              cert from your own CA; an optional password covers devices
#              without one.
#   public     https://DOMAIN via nginx. A password alone, rate limited and
#              fail2ban'd. Read the warning in the README first.
ACCESS = tailscale

# mtls/public only: your domain. It must match server_name (and the cert
# paths) in nginx/agent-box-$(ACCESS).conf. In tailscale mode leave it unset:
# the box's MagicDNS name (myvps.your-tailnet.ts.net) is looked up for you.
# DOMAIN = code.example.com
