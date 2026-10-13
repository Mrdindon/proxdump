# proxdump — copias de seguridad cifradas de Proxmox VE en almacenamiento en la nube

[English](README.md) | [Français](README.fr.md) | **Español** | [Deutsch](README.de.md) | [简体中文](README.zh-CN.md) | [Русский](README.ru.md)

`proxdump` copia las máquinas virtuales y los contenedores de un nodo
**Proxmox VE** con `vzdump`, **cifra** los archivos en el servidor y los
envía a **Microsoft OneDrive**, **Google Drive**, **Dropbox**, cualquier
**almacenamiento compatible con S3** (Backblaze B2, Cloudflare R2, Wasabi,
Amazon S3, MinIO…) o un **servidor SFTP**. Todo se maneja con menús en el
terminal; no hace falta aprender nada de `rclone`.

```
 PROXDUMP 1.0.0                                                          pve

   ╭─ Copia de seguridad ─────────────────────────────────────────────────╮
   │                                                                      │
   │ Copia 1 de 2: qemu 100 (web)                                         │
   │                                                                      │
   │ ⠹ Envío cifrado de vzdump-qemu-100-….vma.zst (2.5GB) a OneDrive…     │
   │   1.5GB / 2.5GB  40MB/s  restante: 24s                               │
   │                                                                      │
   │ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  61%  │
   ╰──────────────────────────────────────────────────────── 1m12s ───────╯

 Ctrl-C Interrumpir
```

## Características

- **Cifrado antes de salir del servidor**: el destino solo recibe datos
  ilegibles (XSalsa20-Poly1305, mediante `rclone crypt`). Los nombres de
  archivo siguen siendo legibles y llevan el sufijo `.encrypted`.
- **Cinco tipos de destino**, varios a la vez: el archivo se crea una sola
  vez y después se envía a cada destino elegido.
- **Verificado**: tras cada envío, la copia remota se compara con el archivo
  local mediante suma de comprobación.
- **Retención**: número de versiones conservadas, global o por huésped,
  aplicado después de cada copia.
- **Restauración** con el ID original, con un ID nuevo, o simple descarga
  del archivo descifrado. Los archivos son archivos `vzdump` estándar:
  también pueden restaurarse sin esta herramienta.
- **Programación**: varias programaciones (diarias o semanales, todos los
  huéspedes o una selección, uno o varios destinos), que también pueden
  ejecutarse al momento.
- **Conexiones guiadas**: autorización paso a paso para OneDrive, Google
  Drive y Dropbox en un servidor sin navegador web; formularios sencillos
  para S3 y SFTP.
- **Dos interfaces**: una nativa con temas de colores, ratón y ventana de
  progreso animada, o los diálogos clásicos de `whiptail`.
- **Seis idiomas**: inglés, francés, español, alemán, chino (simplificado)
  y ruso, para la interfaz y el registro.
- **Ligero**: un script de bash, `rclone`, `jq` y lo que un nodo Proxmox VE
  ya incluye.

## Cómo funciona

```
 huésped (VM/CT)               carpeta temporal local             destino(s)
┌─────────────┐   vzdump     ┌─────────────────────────┐  rclone  ┌──────────────────────┐
│ 100 web     │ ───────────▶ │ vzdump-qemu-100-….vma.zst│ ──────▶ │ pve-backups/<nodo>/  │
└─────────────┘              │ (sin cifrar, se elimina)  │  crypt │  ….vma.zst.encrypted │
                             └─────────────────────────┘          └──────────────────────┘
```

Para cada huésped: `vzdump` crea el archivo en una carpeta temporal, `rclone`
lo cifra y lo envía, se verifica la copia, se aplica la retención y se
elimina la carpeta temporal. Es `vzdump` quien decide qué contiene el
archivo, de modo que se respeta el ajuste «Copia de seguridad» de cada disco
en Proxmox VE.

## Destinos

| Destino | Conexión | A tener en cuenta |
|---|---|---|
| Microsoft OneDrive | Autorización en un navegador, token pegado en el servidor | 250 GB por archivo |
| Google Drive | Igual, con un cliente OAuth propio (gratuito) | 750 GB enviados al día |
| Dropbox | Autorización en un navegador, token pegado en el servidor | 350 GB por archivo |
| Almacenamiento compatible con S3 | Clave de acceso, secreto y bucket | Backblaze B2, Cloudflare R2, Wasabi, Amazon S3, Hetzner, OVHcloud, Scaleway, MinIO… |
| Servidor SFTP | Clave SSH generada por la herramienta, o contraseña | NAS, otro servidor, almacenamiento alquilado |

## Requisitos

- un nodo Proxmox VE (desarrollado y probado en PVE 9 / Debian 13), acceso
  root;
- al menos un destino con espacio suficiente;
- una carpeta local capaz de contener temporalmente el archivo más grande;
- para OneDrive, Google Drive y Dropbox: un ordenador con navegador web y
  [rclone](https://rclone.org/downloads/), una sola vez, para la
  autorización.

## Instalación

```bash
git clone https://github.com/Mrdindon/proxdump.git
cd proxdump
./install.sh
```

`install.sh` instala lo que falte (`rclone` desde su paquete oficial, `jq`,
`whiptail`, `curl`) y copia la herramienta en `/usr/local/bin/proxdump`.
Para actualizar: `git pull && ./install.sh`. Para desinstalar:
`./install.sh --uninstall` (la configuración se conserva).

## Primeros pasos

Ejecute `proxdump` como root y, en **Configuración**:

1. conecte al menos un destino;
2. defina la frase de cifrado y **anótela fuera del servidor**: sin ella,
   las copias de seguridad no se pueden recuperar;
3. revise la carpeta temporal local y las opciones de copia.

Después, **Copiar máquinas virtuales y contenedores** para una primera copia
y **Programación automática** para las siguientes.

## Línea de comandos

```bash
proxdump                                  # los menús
proxdump backup --all                     # todos los huéspedes, todos los destinos
proxdump backup --to s3,onedrive 100 101  # huéspedes y destinos indicados
proxdump list                             # copias almacenadas
proxdump prune                            # aplicar la retención
```

## Documentación

La documentación detallada está en inglés:

- [Connecting the destinations](docs/CONNECTIONS.md) — OneDrive, Google
  Drive, Dropbox, S3, SFTP, duración de los tokens de acceso;
- [Using proxdump](docs/USAGE.md) — idioma y apariencia, cifrado, copia,
  gestión, restauración, programación y línea de comandos;
- [Disaster recovery](docs/RECOVERY.md) — restaurar en un servidor nuevo,
  con o sin esta herramienta;
- [Reference](docs/REFERENCE.md) — archivos y seguridad, solución de
  problemas, limitaciones conocidas;
- [Development](docs/DEVELOPMENT.md) — probar sin una cuenta real,
  traducciones.

## Limitaciones

- Un nodo a la vez: la herramienta copia los huéspedes del nodo en el que se
  ejecuta.
- Solo copias completas (ni incrementales ni deduplicación).
- Se necesita espacio local para el archivo comprimido, tanto al copiar como
  al restaurar.
- Las traducciones no han sido revisadas por hablantes nativos: las
  correcciones son bienvenidas.

## Licencia

MIT — véase [LICENSE](LICENSE).
