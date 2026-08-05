# Cloudflare Tunnel connector — a separate Fly app so the Phoenix deploy
# doesn't churn the tunnel process. The tunnel connects outbound-only to
# Cloudflare's edge and, on the Fly side, reaches Phoenix via the private
# `digital-oil-sticker.internal:8080` — sidestepping the CF→Fly-edge TLS
# handshake that was surfacing as intermittent 525s.

FROM cloudflare/cloudflared:latest

# The image's ENTRYPOINT is already `/usr/local/bin/cloudflared --no-autoupdate`.
# cloudflared reads TUNNEL_TOKEN from the environment automatically (set as a
# Fly secret), so we don't need to interpolate it here — which would require a
# shell the base image doesn't have.
CMD ["tunnel", "run"]
