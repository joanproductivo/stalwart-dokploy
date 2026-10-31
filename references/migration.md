# Sustituir otro servidor y migrar buzones

Stalwart se prepara junto al servidor antiguo, sin puertos de correo públicos. El antiguo sigue recibiendo hasta un corte corto. No lo pares antes de ese momento.

## Antes de empezar

1. Guarda una copia del DNS de todos los dominios.
2. Lista los buzones del servidor antiguo, su tamaño y dónde guarda los datos. Inspecciona con comandos de solo lectura.
3. Lista lo que envía por él: webs, aplicaciones y clientes. Dejarán de enviar desde el corte hasta que cambien de host y contraseña.
4. Lista los servicios de envío externos del dominio. Sus registros no se tocan.

## Preparar Stalwart

En el compose, sustituye los puertos de correo por IMAP solo local, además del túnel:

```yaml
    ports:
      - "127.0.0.1:<PUERTO_TUNEL>:8080"
      - "127.0.0.1:11993:993"
```

Sigue las fases 2 a 5 de `SKILL.md`, salvo que el MX, el SPF y el DMARC de los dominios en servicio esperan al corte. El certificado por DNS-01 no necesita los puertos de correo. Usa DNS manual en esos dominios y publica ya sus claves DKIM. Crea las cuentas y pide que añadan las contraseñas nuevas.

## Copiar el correo

Ejecuta todo en el servidor. Los archivos de contraseña quedan allí para la pasada final. Cada `read` espera una contraseña sin mostrarla: primero la del servidor antiguo y luego la de Stalwart.

```bash
umask 077; mkdir -p /tmp/imapsync; read -rs P1; printf '%s' "$P1" > /tmp/imapsync/p1; read -rs P2; printf '%s' "$P2" > /tmp/imapsync/p2; unset P1 P2
```

```bash
docker run --rm --network host --user "$(stat -c %u:%g /tmp/imapsync/p1)" -v /tmp/imapsync:/s:ro gilleslamiral/imapsync imapsync --host1 127.0.0.1 --port1 993 --ssl1 --user1 <BUZON_ANTIGUO> --passfile1 /s/p1 --host2 127.0.0.1 --port2 11993 --ssl2 --user2 <BUZON_NUEVO> --passfile2 /s/p2 --automap --addheader --nofoldersizes --noresyncflags --maxmessagespersecond 3
```

Para otro puerto o host en el origen, cambia `--host1` y `--port1`. Si un buzón necesita otro mecanismo, añade `--authmech2 PLAIN`. Repite por cada buzón y compara los totales del final de la salida. `imapsync` puede repetirse sin duplicar gracias a `--addheader`. En el despliegue real apareció un error de inicio de sesión `PLAIN` también en pasadas correctas, sin causa aclarada, así que el criterio es que los totales cuadren.

## Corte

Avisa antes, porque hay una interrupción breve. Los servidores remitentes reintentan el correo.

1. Haz una pasada final de cada buzón y compara totales.
2. Para el servidor antiguo, sin borrarlo.
3. Restaura en el compose `25:25`, `465:465` y `993:993`, quita la línea de `11993` y despliega.
4. Cambia el MX de cada dominio al hostname de Stalwart, ajusta SPF y DMARC, y cambia el PTR en el proveedor del servidor.
5. Comprueba con `scripts/verify.sh` y con correo real en ambos sentidos, en cada dominio.
6. Si alguien ha enviado correo durante la ventana, revisa si quedó en el servidor antiguo.
7. Pide que cambien webs y clientes a `<hostname>`, puerto 465, SSL/TLS, con usuario y contraseña nuevos.
8. Pide una prueba de envío de cada servicio externo.
9. Cuando no haga falta otra pasada, debe borrar los archivos en el servidor:

```bash
rm -rf /tmp/imapsync
```

## Vuelta atrás

Mientras el antiguo siga intacto, se puede volver: para Stalwart, arranca el antiguo y restaura MX, SPF, DMARC y PTR desde la copia. El correo recibido en Stalwart durante ese tiempo habría que copiarlo de vuelta.

No borres el servidor antiguo, sus datos ni el registro de su hostname hasta pasados unos días sin problemas, con todos los remitentes cambiados, y con su confirmación expresa. Si se vuelve a desplegar, ocupará los mismos puertos y sus rutas competirán por el dominio.
