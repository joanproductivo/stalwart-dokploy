#!/usr/bin/env bash
# Comprobación externa y de solo lectura de un despliegue de Stalwart.
# Uso: verify.sh <mail-host> <dominio> [ip-del-servidor]
#
# No envía correo ni inicia sesión. Tampoco prueba rutas típicas de escáneres:
# el bloqueo automático de Stalwart podría banear la IP que hace la prueba.
set -u

if [ "$#" -lt 2 ]; then
  echo "Uso: $0 <mail-host> <dominio> [ip-del-servidor]" >&2
  exit 2
fi

for tool in dig nc openssl curl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Falta la herramienta: $tool" >&2
    exit 2
  fi
done

host=$1
domain=$2
ip=${3:-$(dig +short A "$host" | tail -1)}
if [ -z "$ip" ]; then
  echo "No se ha podido obtener la IP de $host. Crea su registro A o pásala como tercer argumento." >&2
  exit 2
fi
failures=0

ok() { echo "  OK     $1"; }
warn() { echo "  AVISO  $1"; }
fail() { echo "  FALLO  $1"; failures=$((failures + 1)); }

record() { dig +short @1.1.1.1 "$2" "$1" | tr '\n' ' '; }

echo "== DNS"
a=$(record "$host" A)
case "$a" in
  *"$ip"*) ok "A de $host -> $a" ;;
  *) fail "A de $host -> '${a}', se esperaba $ip (¿proxy de CDN activado?)" ;;
esac
mx=$(record "$domain" MX)
case "$mx" in
  *"$host"*) ok "MX -> $mx" ;;
  *) fail "MX de $domain -> '${mx}', debe apuntar a $host" ;;
esac
ptr=$(dig +short -x "$ip" | tr '\n' ' ')
case "$ptr" in
  *"$host"*) ok "DNS inverso -> $ptr" ;;
  *) warn "DNS inverso de $ip -> '${ptr}'. Debería ser $host; se configura en el proveedor del servidor" ;;
esac
spf=$(record "$domain" TXT | tr ' ' '\n' | grep -c 'v=spf1')
[ "$spf" = 1 ] && ok "SPF: un registro" || fail "SPF: $spf registros, debe haber exactamente uno"
for name in "_dmarc.$domain" "_mta-sts.$domain" "_smtp._tls.$domain"; do
  value=$(record "$name" TXT)
  [ -n "$value" ] && ok "$name" || warn "$name sin registro TXT"
done

echo "== Puertos (los proveedores de internet domésticos suelen bloquear el 25 de salida)"
port25=0
if nc -z -w 4 "$host" 25 >/dev/null 2>&1; then
  ok "25 abierto"
  port25=1
else
  warn "25 sin respuesta desde esta red. Confírmalo con correo real o desde otra red"
fi
for port in 465 993; do
  if nc -z -w 4 "$host" "$port" >/dev/null 2>&1; then
    ok "$port abierto"
  else
    fail "$port cerrado o filtrado"
  fi
done

echo "== Certificado de correo"
check_cert() {
  label=$1
  shift
  out=$(echo | openssl s_client "$@" -servername "$host" -verify_hostname "$host" 2>/dev/null)
  if printf '%s' "$out" | grep -q 'Verify return code: 0'; then
    ok "$label válido"
  else
    fail "$label no valida (¿todavía autofirmado? espera a ACME y repite)"
  fi
}
check_cert "993" -connect "$host:993"
check_cert "465" -connect "$host:465"
# Con el 25 filtrado, openssl se quedaría esperando la conexión.
if [ "$port25" = 1 ]; then
  check_cert "25 STARTTLS" -starttls smtp -connect "$host:25"
else
  warn "25 STARTTLS sin probar"
fi

echo "== Web a través del proxy"
status=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "https://$host/healthz/live")
if [ "$status" = 200 ]; then
  ok "healthz 200"
else
  fail "healthz $status. Con 502 o 403, comprueba si Stalwart ha bloqueado la IP del proxy"
fi
policy=$(curl -s -m 10 "https://mta-sts.$domain/.well-known/mta-sts.txt")
case "$policy" in
  *STSv1*) ok "política MTA-STS ($(printf '%s' "$policy" | tr -d '\r' | grep '^mode'))" ;;
  *) fail "política MTA-STS no disponible; falta la ruta de mta-sts.$domain" ;;
esac
for name in autoconfig autodiscover ua-auto-config; do
  cname=$(record "$name.$domain" CNAME)
  if [ -z "$cname" ]; then
    warn "$name.$domain sin CNAME"
    continue
  fi
  if curl -s -o /dev/null -m 10 "https://$name.$domain/"; then
    ok "$name.$domain con TLS válido"
  else
    fail "$name.$domain tiene CNAME pero no hay ruta o certificado en el proxy"
  fi
done

echo
if [ "$failures" -eq 0 ]; then
  echo "Sin fallos. Esto no sustituye una prueba real de envío y recepción."
else
  echo "$failures fallo(s)."
  exit 1
fi
