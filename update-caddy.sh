#!/bin/bash
# Update Caddy config with subdomain-based routing
# Run as root: sudo bash update-caddy.sh

cat > /etc/caddy/Caddyfile << 'EOF'
{
  local_certs
}

https://pipi.local {
  tls internal
  handle /cert {
    root * /var/www/caddy-ca
    rewrite * /root.crt
    file_server
  }
  handle / {
    respond "pipi.local - ha.pipi.local, openclaw.pipi.local, /cert" 200
  }
}

https://ha.pipi.local {
  tls internal
  reverse_proxy localhost:8123
}

https://openclaw.pipi.local {
  tls internal
  reverse_proxy localhost:18789
}

http://pipi.local:80 {
  handle /cert {
    root * /var/www/caddy-ca
    rewrite * /root.crt
    file_server
  }
  handle / {
    respond "Visit /cert to download the CA certificate" 200
  }
}

https://192.168.4.80 {
  tls internal
  reverse_proxy localhost:8123
}

https://208.52.2.131 {
  tls internal
  reverse_proxy localhost:8123
}
EOF

mkdir -p /var/www/caddy-ca
caddy validate --config /etc/caddy/Caddyfile && systemctl restart caddy && sleep 3 && cp /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt /var/www/caddy-ca/root.crt && chmod 644 /var/www/caddy-ca/root.crt && chown caddy:caddy /var/www/caddy-ca/root.crt && echo "Done! Access https://ha.pipi.local and https://openclaw.pipi.local"
