# Problemas conocidos

Los síntomas de esta tabla ocurrieron en un despliegue real con Stalwart v1.0.1 detrás del Traefik de Dokploy.

| Síntoma | Causa | Solución |
|---|---|---|
| `Bind for 127.0.0.1:8080 failed: port is already allocated` | Otro contenedor usa ese puerto | Elige otro puerto para el túnel. El contenedor sigue escuchando en 8080 |
| `exec /usr/local/bin/stalwart failed: Operation not permitted` en bucle | `cap_drop: ALL` sin capacidades añadidas | Añade `cap_add: NET_BIND_SERVICE` |
| `Unknown client id` al iniciar sesión | Inicio de sesión por HTTP, incluido el túnel, fuera del asistente y de recuperación | Entra por `https://<host>/admin`. Si no es posible, usa el modo de recuperación como se indica en «Bloqueo del proxy» |
| `Client metadata documents are disabled` | La URL del navegador no coincide con la URL pública | Revisa `STALWART_PUBLIC_URL`. Entra por el hostname, no por la IP ni el dominio de correo |
| 502 o 403 en todos los hostnames, mientras `/healthz/live` responde 200 desde dentro | Es probable que la IP del proxy esté en `Blocked IPs` | Ver «Bloqueo del proxy» |
| Certificado autofirmado (`rcgen self signed cert`) en 465 y 993 justo tras arrancar | ACME todavía no ha terminado | Espera un par de minutos y repite. No aceptes la advertencia en el navegador |
| Los puertos 25, 465 o 993 cerrados desde fuera con el contenedor sano y fuera de recuperación | Firewall del proveedor o de la red local | Abre la entrada en el panel del proveedor. Prueba desde otra red, porque muchas redes domésticas bloquean el 25 |
| Los logs del contenedor salen vacíos | En el asistente quedó «Log file», que es el valor por defecto | Settings › Telemetry › Tracers: cambia a Console |
| Certificado que no valida en `mta-sts`, `autoconfig`, `autodiscover` o `ua-auto-config` | Tienen CNAME, pero falta su ruta en Traefik | Añade el dominio en Dokploy y vuelve a desplegar |
| No aparecen registros DNS justo después del asistente | Se publican tras el reinicio y tardan algo | Espera y consulta de nuevo |
| `smtp.relay-not-allowed` desde un cliente como `smtpclient.apple` | El cliente envía por el 25 sin autenticarse | Configura SMTP en el hostname, puerto 465, SSL y contraseña, con la dirección completa como usuario |
| Una web o un cliente fallan por certificado tras cambiar de servidor | Usa un nombre antiguo que no está en el certificado | Cámbialo por el hostname de Stalwart |
| El correo llega a spam con SPF, DKIM y DMARC en `PASS` | Falta reputación de la IP o el dominio | Marca «No es spam», responde y envía poco volumen al principio |
| `_mta-sts` no aparece justo después de crearlo | Caché negativa del resolvedor | Consulta el servidor autoritativo y repite en unos minutos |
| `verify.sh` avisa del puerto 25 | Muchas redes domésticas filtran la salida | Confírmalo en los logs con una entrega real, por ejemplo `smtp.ehlo` de un servidor externo |
| `imapsync` no puede leer `passfile` | El contenedor no corre con el propietario de los archivos | Usa `--user "$(stat -c %u:%g <ARCHIVO>)"`, sin ampliar permisos |
| `imapsync` da `AUTHENTICATIONFAILED` | Contraseña equivocada en el archivo, o `read` guardó otro valor | Vuelve a crear ese archivo y comprueba su tamaño con `wc -c`, sin mostrarla |
| `imapsync` se para con `Too many requests` | Límite de peticiones de Stalwart | Añade `--maxmessagespersecond 3` y `--noresyncflags`, y repite: con `--addheader` no duplica |

## Herramientas de Dokploy

- `dockerVolume-listVolumeFiles` con un nombre inexistente puede crear un volumen vacío. Obtén antes el nombre real con `dockerVolume-getVolumes` o `compose-loadMountsByService`.
- `compose-readLogs` puede devolver 500 con ciertos valores de `search`. Si falla, repite sin `search`, con `tail` y `since` acotados.
- Añadir una ruta exige volver a desplegar, y eso reinicia el contenedor unos segundos.

## Bloqueo del proxy

Con `clientIpSource` en `peer`, todas las peticiones web parecen venir de Traefik. Una sola ruta de `scanBanPaths` banea esa IP de forma permanente, y los escáneres aparecen a los pocos minutos de emitirse un certificado público. Por eso `SKILL.md` configura `xForwardedFor` antes de publicar las rutas.

El bloqueo se conserva tras reiniciar. La recuperación es esta:

1. Desactiva las rutas de Stalwart en Dokploy. El modo de recuperación no tiene protección contra intentos de contraseña y no debe quedar accesible por el proxy.
2. Vuelve a añadir al compose la línea del túnel, `"127.0.0.1:<PUERTO_TUNEL>:8080"`, y despliega.
3. Entra en modo de recuperación (fase 4 de `SKILL.md`).
4. Borra la IP en `Blocked IPs`. Su campo `reason` indica el motivo.
5. Pon `clientIpSource` en `xForwardedFor` y `forwardedHops` en `1`.
6. Borra las variables de recuperación y la línea del túnel, reactiva las rutas y vuelve a desplegar.
7. Comprueba que las variables han desaparecido con `docker inspect <CONTENEDOR> | grep -c STALWART_RECOVERY`, que debe dar `0`.

## Comprobar copias en R2 o S3

Los archivos pueden quedar bajo una ruta que no coincide con el prefijo configurado. En un caso real, el prefijo `stalwart/data` acabó en `<proyecto>_stalwart/stalwart/data/`, con el nombre de volumen recortado. El listado de Dokploy se recorre carpeta a carpeta, así que una búsqueda vacía no significa que no exista la copia. Empieza por el nombre del proyecto, sin barra final.

## Fuentes

- Docker: https://stalw.art/docs/install/platform/docker/
- Asistente: https://stalw.art/docs/install/setup-wizard/
- Proxy inverso: https://stalw.art/docs/server/reverse-proxy/
- Traefik: https://stalw.art/docs/server/reverse-proxy/traefik
- Bloqueo automático: https://stalw.art/docs/server/auto-ban
- Desafíos ACME: https://stalw.art/docs/server/tls/acme/challenges/
- Proveedores DNS: https://stalw.art/docs/server/dns/provider-notes/
