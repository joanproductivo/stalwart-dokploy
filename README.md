# Stalwart en Dokploy

Skill para que un agente como Claude Code instale el servidor de correo [Stalwart](https://github.com/stalwartlabs/stalwart) en [Dokploy](https://dokploy.com), detrás de su Traefik. Guía a quien instala desde las comprobaciones previas hasta un servidor que envía y recibe, con copias de seguridad.

## Qué incluye

- Imagen Alpine con versión fijada y contenedor endurecido.
- TLS, DNS, DKIM, SPF, DMARC y MTA-STS en modo `testing`.
- Uno o varios dominios, sin romper otros servicios que envían desde ellos.
- Migración de buzones por IMAP para sustituir otro servidor.
- Copias de volumen a un destino S3 configurado en Dokploy.
- Gestión opcional del DNS con el [MCP oficial de Cloudflare](https://github.com/cloudflare/mcp).
- Comprobación externa de solo lectura y guía de problemas conocidos.

## Instalación

En Claude Code, clona el repositorio en tu carpeta de skills:

```bash
git clone https://github.com/joanproductivo/stalwart-dokploy.git ~/.claude/skills/stalwart-dokploy
```

Después pide algo como «Instala Stalwart en Dokploy». Conviene tener conectado el MCP de Dokploy; sin él, el agente te dará los pasos de la interfaz.

## Requisitos

- Un servidor con Dokploy y acceso SSH.
- Salida por el puerto 25 y entrada en 25, 465 y 993.
- Control del DNS del dominio y del DNS inverso de la IP.
- Un destino S3 para las copias.

Quien instala introduce sus propias credenciales. La skill indica no pedirlas por el chat.

## Estructura

| Ruta | Contenido |
|---|---|
| `SKILL.md` | Proceso de instalación |
| `references/migration.md` | Sustituir otro servidor y migrar buzones |
| `references/troubleshooting.md` | Síntomas y soluciones |
| `assets/docker-compose.yml` | Plantilla del compose |
| `scripts/verify.sh` | Comprobación externa de solo lectura |

## Limitaciones

Stalwart cambia rápido: la skill se escribió para la v1. La guía de migración sale de un caso real con un solo buzón migrado y no se ha seguido de principio a fin en una instalación nueva. Prueba a restaurar una copia antes de confiarle correo importante.
