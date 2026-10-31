---
name: stalwart-dokploy
description: Instala el servidor de correo Stalwart en Dokploy detrás de su Traefik, con imagen Alpine fijada, contenedor endurecido, TLS, DNS, uno o varios dominios, buzones y copias de seguridad, y migra los buzones por IMAP si sustituye a otro servidor. Puede gestionar el DNS con el MCP oficial de Cloudflare. Úsala siempre que alguien quiera desplegar, instalar o montar Stalwart o su propio correo autoalojado en Dokploy, o sustituir un servidor de correo existente en Dokploy, aunque no nombre la skill. También para "self-host email on Dokploy" o "deploy Stalwart". No es para Stalwart fuera de Dokploy.
---

# Stalwart en Dokploy

Lleva a alguien sin experiencia en correo hasta un servidor que envía y recibe, con copias comprobadas. El orden importa: varias fases existen para evitar fallos reales, explicados en cada una.

Responde en el idioma de la persona. Usa el MCP de Dokploy si existe; si no, dale los pasos de la interfaz de Dokploy. Stalwart cambia rápido: si la versión instalada ya no es la v1, contrasta los pasos con la [documentación de Docker](https://stalw.art/docs/install/platform/docker/).

## Qué hace cada quien

Quien instala debe hacer lo que implica credenciales propias: el asistente de Stalwart, los inicios de sesión, las variables con contraseñas, el token DNS, las contraseñas de las cuentas y su acceso SSH. No los introduzcas ni los pidas por el chat, porque quedarían en la conversación. Pídele que genere los secretos en su propia terminal, no a través de ti. Tú te encargas de Dokploy y de las comprobaciones, y del DNS si conecta el MCP de Cloudflare.

Abrir el puerto 25, cambiar el DNS y borrar un servicio antiguo afectan a sistemas reales. Confirma cualquier cambio que la petición no cubra.

Cuando le des un comando, indica dónde ejecutarlo (su ordenador o el servidor) y qué marcadores debe sustituir.

## Fase 0: Datos y comprobaciones previas

Pide solo lo que no puedas averiguar:

- Todos los dominios de correo y un único hostname (por defecto, `mail.<dominio>`).
- Proyecto de Dokploy donde desplegar.
- Proveedor DNS y si admite API. Consulta los [proveedores admitidos](https://stalw.art/docs/server/dns/provider-notes/).
- Si ya envía correo desde esos dominios con otro servicio.
- Si sustituye a un servidor con buzones que conservar. En ese caso, sigue también [references/migration.md](references/migration.md) antes de la fase 2.

Consulta el DNS de cada dominio antes de usarlo. Si su NS o sus registros no encajan con lo que describe, puede ser una errata en el nombre: confírmalo antes de tocar nada.

Comprueba antes de crear nada:

| Comprobación | Por qué |
|---|---|
| Otro servicio en 25, 465 o 993 | Impediría arrancar el contenedor |
| Firewall del proveedor: entrada en 25, 465 y 993 | Si está cerrado, nada llegará al servidor aunque el contenedor funcione |
| Puertos del host en uso, incluidos los de `127.0.0.1` | Elige un puerto libre para el túnel. El 8080 suele estar ocupado |
| RAM libre y disco | Stalwart usó unos 110 MiB casi sin correo. El correo y las copias necesitan disco |
| Salida por el puerto 25 | Muchos proveedores la bloquean y sin ella no se puede enviar. En el servidor: `nc -vz -w5 gmail-smtp-in.l.google.com 25` |
| DNS inverso de la IP | Debe resolver al hostname. Se configura en el proveedor del servidor y sin él el correo suele acabar en spam |
| Registro A del hostname, sin proxy de CDN | El asistente no lo crea: si falta, créalo o pide que lo creen ahora con la IP del servidor. Un proxy HTTP no deja pasar SMTP ni IMAP |
| Registros SPF, DKIM, DMARC y MX actuales | Guárdalos. La gestión automática de DNS puede reescribirlos |
| Rutas de un servidor de correo antiguo en Dokploy | Si se vuelve a desplegar, competirá con Stalwart por el dominio |

Detente y avisa si la salida por el puerto 25 está bloqueada y no se puede desbloquear: recibirá correo, pero no podrá enviarlo directamente.

**Otros remitentes del dominio:** con la gestión automática, Stalwart publica un SPF que solo autoriza a sus propios servidores y un DMARC con `p=reject`. Comprueba cómo se autentica cada servicio antes de decidir:

- Si firma con DKIM en el propio dominio (CNAME `*._domainkey`) y usa un subdominio de rebote con su propio MX y SPF, como Amazon SES, no depende del MX ni del SPF raíz y DMARC puede pasar por DKIM. Esos registros no se tocan. Pide una prueba real de envío de ese servicio tras el cambio y comprueba `dmarc=pass`.
- Si depende del SPF raíz, añádelo a ese SPF o usa un subdominio.
- Si el dominio ya está en uso o tiene varios remitentes, usa DNS manual para ese dominio (ver «Dominios adicionales»), porque así Stalwart no reescribe nada.

## DNS con el MCP de Cloudflare (opcional)

Si el DNS está en Cloudflare y no tienes herramientas para editarlo, ofrece conectar el [MCP oficial](https://github.com/cloudflare/mcp), para no dictar cada registro. Quien instala debe ejecutar esto en su ordenador:

```bash
claude mcp add --scope user --transport http cloudflare-api https://mcp.cloudflare.com/mcp
```

Después debe abrir `claude` en una terminal, escribir `/mcp`, elegir `cloudflare-api` y autenticarse en la página de Cloudflare, concediendo solo lo necesario para DNS si le deja elegir. Puede que haya que reiniciar la sesión para que aparezcan las herramientas. Este acceso es independiente del token DNS que usa Stalwart en la fase 3.

Reglas al usarlo:

1. Lee toda la zona y guarda una copia antes del primer cambio. Compárala con lo que vas a publicar.
2. Crea los registros que falten. Para cambiar o borrar uno que ya existe (MX, SPF, DMARC, verificaciones de otros servicios), explica antes el cambio y pide confirmación.
3. Nunca toques registros de otros servicios: `*._domainkey` ajenos, subdominios de rebote ni verificaciones.
4. Usa `proxied: false` en el hostname y en todos los CNAME de correo.
5. Comprueba cada zona por su nombre exacto. Un registro comodín con proxy (`*.<dominio>`) puede hacer que un nombre parezca existir antes de crearlo.

Al terminar, recuérdale que puede quitar el MCP con `claude mcp remove cloudflare-api --scope user` y revocar el acceso en Cloudflare. Si no conecta el MCP, dale los registros en una tabla para que los publique.

## Fase 1: Elegir la imagen

Busca la última versión estable en [las releases](https://github.com/stalwartlabs/stalwart/releases) y confirma que existe `vX.Y.Z-alpine` en [Docker Hub](https://hub.docker.com/r/stalwartlabs/stalwart/tags). Fija esa etiqueta exacta, no `latest`, para que el correo no se actualice solo.

Alpine pesa unos 25 MB menos (98 MB frente a 122 MB en la v1.0.1), pero eso no garantiza menor consumo de memoria. Solo en la imagen Debian usa RocksDB jemalloc, así que con mucha carga podría rendir mejor; no se ha medido. Se puede cambiar de imagen sin migrar datos. RocksDB integrado evita tener que mantener Postgres y Redis.

## Fase 2: Primer despliegue

Crea un compose de tipo `raw` a partir de [assets/docker-compose.yml](assets/docker-compose.yml), sustituye los marcadores y despliega. Si otro servidor ocupa los puertos de correo, quita antes `25`, `465` y `993` como indica la migración. **No añadas todavía ningún dominio en Dokploy:** el asistente no se puede completar a través de Traefik, y no debe quedar expuesto porque no tiene protección contra intentos de contraseña.

Lo correcto en este punto es que el contenedor esté `healthy` en modo de arranque. Los puertos de correo aparecerán cerrados desde fuera hasta terminar el asistente.

## Fase 3: Asistente

Para DNS-01, pídele que cree un token. En Cloudflare: permisos `Zone:Read` y `DNS:Edit`, limitado a su zona. No sirve un token restringido a `_acme-challenge`, porque rompe la gestión automática de DNS. Traefik ocupa los puertos 80 y 443, así que los desafíos por esos puertos no llegan a Stalwart y por eso se usa DNS-01. Si su proveedor no tiene API, avísale de que esta skill no cubre ese camino y remítele a la [guía de desafíos](https://stalw.art/docs/server/tls/acme/challenges/).

Dale estos pasos:

```bash
ssh -L <PUERTO_TUNEL>:127.0.0.1:<PUERTO_TUNEL> <USUARIO>@<IP_SERVIDOR>
```

```bash
docker ps --filter name=stalwart --format '{{.Names}}'
```

```bash
docker logs <CONTENEDOR> 2>&1 | grep -A8 'bootstrap mode'
```

Con el túnel abierto, debe entrar en `http://127.0.0.1:<PUERTO_TUNEL>/admin` con la contraseña temporal de los logs. Cambia en cada arranque, así que solo vale la última. Si esa contraseña aparece en una conversación o en una salida que hayas leído, reinicia el contenedor para cambiarla.

| Pantalla | Valor |
|---|---|
| Identidad | Hostname y dominio; deja activados el TLS automático y las claves DKIM |
| Almacenamiento | RocksDB y resto por defecto |
| Directorio | Interno |
| Logs | **Console**. El valor por defecto es «Log file», y con él el contenedor no muestra logs |
| DNS | Su proveedor, con el token |

Debe guardar las credenciales de `admin@<dominio>` de la última pantalla, porque solo se muestran una vez.

## Fase 4: Modo de recuperación antes de publicar

Esta fase evita el fallo más grave. Tras el asistente, el panel rechaza iniciar sesión por HTTP con `Unknown client id`, incluso por el túnel. Y si se publica la web con el valor por defecto, `clientIpSource: peer`, el primer escáner hará que Stalwart banee a Traefik para siempre y deje la web con 502.

Pídele que genere una contraseña en su propia terminal:

```bash
openssl rand -hex 24
```

En Dokploy, en la pestaña Environment del compose, debe añadir lo siguiente, guardar y desplegar:

```
STALWART_RECOVERY_MODE=1
STALWART_RECOVERY_ADMIN=admin:<CONTRASEÑA>
```

Mientras dure, Stalwart no envía ni recibe correo. Por el túnel, entrará con el usuario `admin` y esa contraseña, y en **Settings › Network › HTTP** (apartados General y Security) pondrá `clientIpSource` en `xForwardedFor` y `forwardedHops` en `1`. Si hay otro proxy o CDN delante de Traefik, debe ser `2` y además hay que configurar `trustedIPs` en Traefik.

**Riesgo que debe conocer:** Stalwart confía en esa cabecera en el puerto 8080, y los demás contenedores de `dokploy-network` pueden llegar a él. La documentación recomienda que esa red solo la compartan Traefik y Stalwart, algo que Dokploy no permite si comparte red con más servicios. Un contenedor comprometido podría falsear su IP, saltarse bloqueos y límites, y probar contraseñas sin que se le banee. Por eso las contraseñas deben ser largas y aleatorias.

Esta secuencia viene de la documentación y de despliegues reales. En el último, los bloqueos por escaneo afectaron a las IP reales de los escáneres, no a Traefik. Si algo no coincide, sigue los síntomas de [references/troubleshooting.md](references/troubleshooting.md).

## Fase 5: Publicar y cerrar

Las rutas se añaden en dos pasos. En recuperación no se ejecutan las tareas de DNS, y Traefik solo puede emitir un certificado cuando el host ya resuelve.

Cuando confirme que ha guardado los cambios:

1. Pídele que **borre** ambas variables de recuperación, sin dejarlas vacías: `STALWART_RECOVERY_ADMIN` da acceso total incluso en funcionamiento normal.
2. Borra del compose la línea del túnel.
3. Añade en Dokploy el dominio `<hostname>`, con servicio `stalwart`, puerto `8080`, HTTPS y Let's Encrypt, y despliega.
4. En el servidor, comprueba que las variables han desaparecido. El resultado debe ser `0`:

   ```bash
   docker inspect <CONTENEDOR> | grep -c STALWART_RECOVERY
   ```

5. Espera a que resuelvan los CNAME que publica Stalwart (`dig +short CNAME mta-sts.<dominio>`). Pueden tardar unos minutos.
6. Añade los dominios restantes con la misma configuración, y despliega de nuevo:
   - `mta-sts.<dominio>`
   - `autoconfig.<dominio>`
   - `autodiscover.<dominio>`
   - `ua-auto-config.<dominio>`

Si falta alguna ruta, ese CNAME apunta a un host sin certificado válido y, en el caso de MTA-STS, la política no se puede leer.

Publica el MX y, si lo desea, CAA a mano si no existen: el asistente no los crea. Después, ejecuta la comprobación:

```bash
bash scripts/verify.sh <hostname> <dominio> <IP_SERVIDOR>
```

La ruta del script es relativa a la carpeta de esta skill. Si la red local bloquea el puerto 25, el script lo avisa y no prueba su certificado; en ese caso, confirma el 25 con correo real y con los logs. No sondees rutas típicas de escáneres, como `/.env` o `/wp-login.php`, porque banearías la IP de quien prueba.

## Dominios adicionales

Todos los dominios comparten el mismo hostname y la misma IP, así que no necesitan otro certificado de correo ni otro PTR. En **Management › Domains › Create domain**:

| Opción | Valor recomendado | Motivo |
|---|---|---|
| DNS | Manual si el dominio ya está en uso; automático si es nuevo y el token lo cubre | En manual, Stalwart no reescribe el MX, el SPF ni el DMARC. A cambio, las claves DKIM no rotan solas |
| DKIM | Automático | Stalwart genera las claves RSA y Ed25519 |
| TLS | Manual | El correo entra por el hostname, que ya tiene certificado |

Con DNS manual, abre **Actions › View Zone File** en ese dominio y publica sus registros en este orden, sin copiar a ciegas el SPF, el MX ni el DMARC si conviven con otros servicios:

1. Claves DKIM. Antes del corte, si ya recibe correo en otro servidor.
2. CNAME sin proxy de `mta-sts`, `autoconfig`, `autodiscover` y `ua-auto-config`, y los TXT de `_smtp._tls` y `_ua-auto-config`. Añade los SRV de `_imaps._tcp` y `_submissions._tcp`. Omite los de servicios sin puerto publicado, como POP3.
3. Las cuatro rutas de esos CNAME en Dokploy, con puerto `8080`, y despliega. El contenedor se reinicia unos segundos.
4. Comprueba `https://mta-sts.<dominio>/.well-known/mta-sts.txt` y publica `_mta-sts` al final, para no anunciar una política que aún no se puede leer.
5. MX, SPF y DMARC, solo cuando ese dominio deba pasar a Stalwart.

## Fase 6: Buzón y prueba real

En `https://<hostname>/admin`, que puede redirigir a `/account`, con la cuenta `admin@<dominio>` del asistente, debe:

1. Revisar en **Settings › Telemetry › Tracers** que esté Console, y en **Settings › Network › HTTP** que `clientIpSource` siga en `xForwardedFor`. Comprueba tú que aparecen logs.
2. En **Management › Accounts**, crear la cuenta con nombre y dominio. No tiene campo de contraseña directo: se añade en **Authentication › Credentials › Add item**. El mínimo son 8 caracteres, pero usa una contraseña larga y aleatoria, porque un servidor de correo público recibe intentos constantes.
3. Añadir el alias `postmaster@<dominio>` en cada dominio, porque ahí llegan los informes DMARC y TLS-RPT.
4. Configurar un cliente con la dirección completa como usuario y el hostname como servidor en todos los dominios: IMAP en 993 y SMTP en 465, ambos con SSL/TLS. El hostname debe coincidir con el certificado.
5. Enviar desde cada dominio a una cuenta externa, responder y comprobar en la cabecera que SPF, DKIM y DMARC salen `PASS`, y en los logs que el mensaje entra.

El compose publica 465 y no 587, porque el 465 usa TLS desde el inicio y basta para los clientes actuales. Si un sistema antiguo solo admite 587, publica `587:587` en el compose y comprueba que Stalwart tiene ese listener.

En Mail de iPhone, revisa el servidor SMTP saliente en los ajustes de la cuenta: puerto 465, SSL activado y autenticación por contraseña. Si se queda con el 25, Stalwart responde `relay-not-allowed`.

Una IP o un dominio nuevos pueden acabar en spam aunque todo dé `PASS`; es reputación, no configuración. Marcar «No es spam» y responder ayuda, y conviene empezar con poco volumen.

## Fase 7: Copias de seguridad

Sin copias, un fallo de disco supone perder el correo. Si no hay destino S3 en Dokploy, pídele que cree uno. Crea dos copias de volumen del compose. `<appName>` es el nombre interno que Dokploy dio al compose, no el del proyecto; compruébalo con `docker volume ls`.

| Volumen | Prefijo | Horario | Conservar | Parar el contenedor |
|---|---|---|---|---|
| `<appName>_stalwart-data` | `stalwart/data` | `30 3 * * *` | 7 | Sí |
| `<appName>_stalwart-etc` | `stalwart/etc` | `20 3 * * 0` | 4 | No |

Parar el contenedor unos segundos da una copia coherente de RocksDB, y los remitentes reintentan. Los archivos son `.tar` sin comprimir y sin cifrado adicional, por lo que 7 copias ocupan unas 7 veces el tamaño del correo. Cada copia se crea antes en local, así que también necesita ese espacio libre en el disco.

Lanza una copia de cada y confirma que los archivos existen en el destino, porque que la tarea termine bien no lo demuestra. Recomienda probar una restauración antes de confiarles correo importante.

## Fase 8: Cierre

Resume qué se ha verificado y qué no, e indica lo pendiente:

- **MTA-STS:** queda en modo `testing`, donde un fallo no bloquea el correo. Tras un par de semanas sin errores en los informes, se puede pasar a `enforce` para que proteja de verdad. A partir de ahí, un problema de certificado puede impedir recibir correo.
- **Actualizaciones:** al estar fijada la versión, hay que actualizarla a mano. Lee antes las notas de la versión y haz una copia.
- **Servidor antiguo:** propón retirarlo solo cuando el nuevo reciba correo y todos los sistemas que enviaban por él estén cambiados. Déjalo parado unos días como vuelta atrás, y mantén su hostname hasta entonces.
- **Otros remitentes:** indica si falta una prueba real de envío tras el cambio.
- **MCP de Cloudflare:** recuerda que sigue conectado, si lo usó, y cómo quitarlo.

Si algo falla, consulta [references/troubleshooting.md](references/troubleshooting.md).
