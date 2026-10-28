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

# Optional extras baked into the image (space-separated; then make rebuild):
#   desktop   a private remote desktop in your browser, with sound, and
#             Chromium on it that agents can drive (README: Extras)
#   wine      libraries Windows apps need under Wine (Synthesizer V); with desktop
#   scraping  curl_cffi, trafilatura, yt-dlp, Camoufox, Playwright... in /opt/scrape
EXTRAS =
