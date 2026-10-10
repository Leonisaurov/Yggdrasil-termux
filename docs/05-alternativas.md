# 05 — Alternativas (y por qué se eligió Yggdrasil)

Opciones para "que los paquetes con binario funcionen en Termux/Android". La elegida es
**O4/O3** (ver al final por qué).

---

## O1 — Correr el Julia **glibc** oficial bajo `glibc-runner`

**Cómo**: `pkg install glibc-repo` → `glibc glibc-runner`; bajar el Julia
`aarch64-linux-gnu` oficial y correrlo con el runner.

- **Cobertura**: ~100% de los JLL (son glibc, es lo que esperan).
- **Costo**: bajo (instalar + bajar el tar oficial).
- **Contra**: no es bionic nativo; es otra libc montada encima (overhead, dos entornos,
  updates ajenos). El port bionic queda "académico" para el ecosistema.
- **Cuándo**: si el objetivo es *usar* Julia con todo, sin importar bionic.

## O2 — Capa de **system-providers** con `Overrides.toml` / `<producto>_path`

**Cómo**: redirigir el artefacto de cada JLL a un directorio con las libs **de Termux**
(que ya son bionic). `~/.julia/artifacts/Overrides.toml` permite, por UUID + nombre de
artefacto, apuntar a un path absoluto:

```toml
[<uuid de FFTW_jll>]
FFTW = "/data/data/com.termux/files/usr"      # el JLL busca lib/libfftw3.so ahí
# o, por producto:
[FFTW_jll]
libfftw3_path = "/data/data/com.termux/files/usr/lib/libfftw3.so.3"
```

- **Cobertura**: amplia — Termux tiene **789 paquetes y 1149 `.so`**; cubre las libs
  frecuentes si están empaquetadas.
- **Costo**: medio; **automatizable** (leer `Artifacts.toml` de cada JLL → mapear producto
  a lib de Termux → escribir el override).
- **Contra**: per-máquina y per-lib, no se publica; ABI/versión por caso; no cubre libs que
  Termux no tenga; hay que rehacer al cambiar versiones.
- **Ventaja**: es la continuación en runtime de lo que `julia-termux` ya hace en build
  (`USE_SYSTEM_*`).
- **Cuándo**: mantener bionic nativo y maximizar paquetes **sin** tocar el ecosistema.

## O3 — **Registry JLL bionic propio** (imagen acotada de O4)

**Cómo**: compilar con el NDK los top-N JLLs, publicar artefactos (`Artifacts.toml` +
host) y distribuirlos por un registro propio o `Overrides.toml`.

- **Cobertura**: 100% del N elegido.
- **Costo**: alto (build + host + recompilar por versión). Es lo que hace Python con
  `cibuildwheel` Android.
- **Cuándo**: como escalón práctico mientras O4 no exista.

## O4 — **Upstream: BinaryBuilder Android + BinaryPlatforms bionic + Yggdrasil**

**Cómo**: agregar el target Android a BinaryBuilderBase/BinaryBuilder, la plataforma a
`Base.BinaryPlatforms`, y recetas/artefactos Android en Yggdrasil/BinaryWrappers.

- **Cobertura**: total (a futuro), sin forks ni overrides.
- **Costo**: ecosistémico (meses, proceso upstream).
- **Cuándo**: es **el arreglo correcto**; el horizonte.

## O5 — musl

Descartada. Android no usa musl (usa bionic); los artefactos musl son dinámicos y necesitan
`ld-musl-aarch64.so.1` (no existe en Android); cargar un `.so` musl en un proceso bionic son
**dos libc**. Ver [`01-problema.md`](01-problema.md).

---

## Matriz de decisión

| | Cobertura | Costo | Mantenimiento | Nativos bionic | Depende de terceros |
|---|---|---|---|---|---|
| O1 glibc-runner | ~100% | bajo | bajo | ❌ | sí (Termux glibc-repo) |
| O2 system-providers | media-alta | medio | medio (por lib) | ✅ | Termux packages |
| O3 registry propio | del N elegido | alto | alto | ✅ | no |
| O4 upstream | total | ecosistémico | nulo (al final) | ✅ | sí (upstream) |
| O5 musl | ~0 | — | — | ❌ | — |

## Por qué **Yggdrasil (O4/O3)** como estrategia de este repo

- Es **el único camino con cobertura real y sin depender de la libc del vecino**.
- O2 es complementario (y muy útil), pero tiene techo: las libs que Termux ya empaquetó.
- O1 resuelve el "hoy" pero abandona bionic; se documenta como **válvula de escape**.
- O4 es grande, pero **parte es automatizable** y cada fase deja valor (plataforma →
  toolchain → receta → artefacto).

**Recomendación operativa**: este repo hace O4/O3 (empezando por el "camino corto" de
[`04-plan.md`](04-plan.md)); O2 se prototipa **en paralelo** como mitigación inmediata; O1
queda documentado para quien priorice cobertura sobre bionic.
