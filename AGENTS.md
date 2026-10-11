# AGENTS.md — guía operativa de Yggdrasil-termux

> Este repositorio es **de planificación**: hoy no compila nada. Su producto son los
> documentos de `docs/`. Cuando se pase a implementación, esta guía fija las reglas.

## Objetivo

Habilitar artefactos JLL de Julia para **`aarch64-linux-android` (bionic)**, de modo que
`Pkg.add` de un paquete con dependencia binaria funcione en Termux sin glibc. El plan está
en `docs/04-plan.md`.

## Reglas del workspace (aplican verbatim)

- **Plataforma**: Termux/Android aarch64, sin root, sin systemd, sin FHS.
  `PREFIX=/data/data/com.termux/files/usr`, `TMPDIR=$PREFIX/tmp`. **Nunca** `/tmp` ni
  `/usr/bin`. Shebangs absolutos (`#!/data/data/com.termux/files/usr/bin/bash`).
- **No compilar pesado en el dispositivo**: nada de `cargo`/`gcc`/`zig`/`nuitka`/ builds de
  LLVM/GCC. Los builds van a **CI** (GitHub Actions arm64) o se envuelven con `tcr`.
  Nunca `-j$(nproc)`: arrancar en `-j1`/`-j2`.
- **No instalar sin permiso**: el usuario instala paquetes a mano. El agente no corre
  `pkg`/`apt`/`npm`/`pip install` ni `./install.sh --global` sin OK explícito.
- **No destructivo sin permiso**: nada de `rm -rf` ni purgas de caché sin OK.
- **Temporales** siempre con `mktemp -d "$PREFIX/tmp/..."` + `trap 'rm -rf' EXIT`, y dejar
  todo limpio.
- **Verificación**: "compila" o "el test pasa" **no** es evidencia. Un artefacto JLL se
  prueba cargándolo y llamando un símbolo real en el dispositivo, y comparando contra el
  mismo símbolo provisto por Termux. Ver `docs/06-verificacion.md`.
- **CI**: monitorear con `gita notify <workflow>` (bloquea hasta terminar), nunca con
  `gh run watch` ni polling con `gh run view`.
- **Concurrencia**: no empujar mientras hay un run en curso si el workflow usa
  `concurrency` + `cancel-in-progress`.
- **Commits**: `<type>(<scope>): <summary>` — `fix|feat|docs|refactor|chore|ci|test|vendor`.
- **Secretos**: en `AGENTS.md`/`PROGRESS.md`/docs nunca claves, tokens, hosts privados ni
  datos de clientes. El contexto de los agentes sale del dispositivo con el repo adentro.

## Reglas específicas de este proyecto

- **Nunca editar upstream a mano.** Yggdrasil, BinaryBuilder, BinaryBuilderBase y
  JLLWrappers son repos de terceros: los cambios van como **forks + parches reproducibles**
  (scripts en `scripts/`), pineados por commit/tag. Ver el skill de pins de fuente
  vendorizada del workspace.
- **Primero medir, después proponer.** Cada afirmación del plan debe tener su medición real
  (comando + salida) o su cita con URL, en `docs/`.
- **El plan es incremental.** Cada fase de `docs/04-plan.md` se acepta con el criterio de
  `docs/06-verificacion.md` **antes** de pasar a la siguiente.
- **No prometer cobertura total.** Yggdrasil tiene miles de recetas y cada una es un build.
  El alcance se declara explícitamente (conjunto inicial acotado) y se mide.
- **Decisión de diseño ya tomada y medida**: los JLL son **herméticos** y no reutilizan la
  `.so` del sistema. Ver `docs/09-jll-hermetico-y-duplicacion.md`. Cualquier propuesta de
  "que use la del sistema" es el mecanismo `Overrides.toml`, ortogonal a Yggdrasil.

## Dónde mirar

| Quiero… | Archivo |
|---|---|
| el plan por fases | `docs/04-plan.md` |
| la causa raíz medida | `docs/01-problema.md` |
| qué existe y qué no (con fuentes) | `docs/03-estado-del-arte.md` |
| criterios de aceptación | `docs/06-verificacion.md` |
| **fallos conocidos y limitaciones** | `docs/11-fallos-y-limitaciones.md` |
| **la spec de la plataforma bionic** | `docs/12-diseno-plataforma-bionic.md` |
| cómo se distribuye/consume | `docs/13-distribucion-y-consumo.md` |
| todas las URLs | `docs/08-referencias.md` |
| el port de Julia que lo motivó | `../Julia/julia-termux/` |

## El código que genera un macro de JLLWrappers queda en el precompile cache del JLL

`@generate_main_file` emite el bloque que elige el wrapper en el **cuerpo del módulo** del JLL, así
que su resultado se hornea al precompilar.  Consecuencia medida: desarrollar un `JLLWrappers`
parcheado en un entorno y agregar los JLLs **no cambia nada** — siguen usando el código viejo y
fallan en silencio (`the module exposes no *_path binding`).  Hay que forzar
`Pkg.precompile()` (o cambiar la versión del JLLWrappers, que es lo que hace la distribución).
Y en general: un JLL que "no expone productos" no dice nada del artefacto ni del override; el
problema está un nivel más arriba, en la elección del wrapper.

## Trampas del registro propio (medidas 2026-10-11)

- `Pkg.Registry.add("<url>")` **no** agrega una URL: en Pkg 1.12 un String suelto se interpreta
  como *nombre* de registro (`RegistrySpec(name=…)`) y falla con "no path or url specified for
  registry".  Usar `Pkg.Registry.add(url = "...")`.
- En un registro, un rango es un `VersionSpec` **literal**, no notación caret: `julia = "1.0.0"`
  es exactamente 1.0.x.  Con la notación del `Project.toml` el resolver contesta "restricted by
  julia compatibility requirement" y **cae en silencio** a la versión de General.  General escribe
  `julia = "1"` y `Preferences = "1.2.1 - 1"`.
- Una entrada de registro **sin `Deps.toml`** resuelve el paquete sin dependencias: no se consulta
  el `Project.toml` del árbol.  Síntoma: "Package X does not have Y in its dependencies" al cargar.
- Un override uuid+name de `Overrides.toml` se traduce a overrides **por hash**
  (`Artifacts.process_overrides`), y para eso `artifact_meta` tiene que haber encontrado antes una
  entrada que matchee la plataforma.  Con `libc="bionic"` no matchea ninguna, así que el override
  **nunca llega**: no es un fallo del override, es un fallo anterior.
- `host_platform` es `nothing` en el código generado de todo JLL que no defina
  `augment_platform!`, y ese camino usa el `select_platform` de un argumento (que usa
  `HostPlatform()` por dentro).  Cualquier parche de selección de wrapper tiene que cubrir **las dos**
  ramas: el primer intento cubrió una sola y no se notó hasta medirlo con `--compiled-modules=no`
  (que descarta el cache como causa).
