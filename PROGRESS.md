# PROGRESS — bitácora

## 2026-10-10 — Investigación inicial (este repo nace)

**Estado**: planificación. Nada implementado, nada compilado, nada publicado.

### Qué se investigó

- Se partió del port bionic de Julia (`../Julia/julia-termux`), que funciona pero **no**
  resuelve paquetes con binario: `Pkg.add("FFTW")` muere en
  `dlopen failed: library "libm.so.6" not found`.
- Se midió en el dispositivo la causa raíz: `Base.BinaryPlatforms.HostPlatform()` devuelve
  `Platform("aarch64","linux"; libc="glibc")` (`docs/01-problema.md`).
- Se relevó todo el ecosistema (Yggdrasil, BinaryBuilder, BinaryPlatforms, JLLWrappers,
  JuliaBinaryWrappers, Pkg) y su estado respecto de Android (`docs/02-ecosistema.md`,
  `docs/03-estado-del-arte.md`).
- Se evaluaron 5 opciones (`docs/05-alternativas.md`) y se eligió **O4/O3: construir
  artefactos JLL para bionic con Yggdrasil/BinaryBuilder** como estrategia del repo.
- Se respondió una pregunta de diseño con medición: **un JLL no reutiliza la `.so` del
  sistema** (`docs/09-jll-hermetico-y-duplicacion.md`). Consecuencia: con Yggdrasil el
  binario queda **duplicado**; reutilizarlo es otro mecanismo (`Overrides.toml`).

### Hallazgos duros (resumen)

- No existe **ningún** artefacto `aarch64-linux-android` publicado en
  `JuliaBinaryWrappers/*`. Cero.
- `BinaryBuilderBase` **no** tiene shards de compilador bionic (sus 1014 targets son
  gnu/musl/apple/freebsd/windows).
- `BinaryBuilder.jl` issue **#846** (Termux, 2020) sigue **abierto**; no hay PRs Android.
- `Base.BinaryPlatforms` no admite `os=android`; en Linux `libc ∈ {glibc, musl}`.
  (Con `validate_strict=false` el tag `bionic` se acepta, pero no hay artefactos que
  matcheen.)
- El único port bionic maduro (TUR `tur-on-device/julia`) **parchea** BinaryPlatforms para
  `bionic` y **no usa JLLs** (`USE_BINARYBUILDER=0`, `USE_SYSTEM_*=1`).
- La comunidad que quiere JLLs usa **glibc-runner** (`termux/glibc-packages`) con el Julia
  glibc oficial; ahí `host_platform` es glibc y todo carga.

### Decisiones

1. **Estrategia**: Yggdrasil/BinaryBuilder (no musl, no glibc-runner como camino principal).
2. **Alcance**: conjunto inicial acotado de librerías; no prometer el ecosistema entero.
3. **Upstream vs fork**: decisión **abierta** (`docs/07-riesgos.md` §Decisiones abiertas).
4. **Duplicación de libs**: aceptada por defecto; mitigable con `Overrides.toml` si molesta.

### Próximo paso (cuando se retome)

Empezar por la **Fase 1** de `docs/04-plan.md`: soporte de plataforma Android/bionic en
`Base.BinaryPlatforms` (patch reproducible sobre un pin), con su criterio de aceptación.

### Documentación agregada en el cierre de la investigación

- `docs/11-fallos-y-limitaciones.md`: catálogo de fallos conocidos y limitaciones, con tag
  `[MEDIDO]`/`[CITADO]`/`[INFERIDO]`, matriz “qué funciona / qué no”, y **troubleshooting**
  de los mensajes de error (`libm.so.6 not found`, `@GLIBC_*`, `uv_cpu_info EACCES`,
  `signal 31`, `rc=127` musl, `Package X not found`, etc.).
- `docs/12-diseno-plataforma-bionic.md`: la **spec** con los cambios exactos de
  `binaryplatforms.jl`/`normalize_triplet.py` (patch de referencia de TUR, citado), valores
  del tag, entrada de `Artifacts.toml` y toolchain (NDK).
- `docs/13-distribucion-y-consumo.md`: registro propio vs `Overrides.toml` (incluida la
  variante **por hash**, que **no requiere** el patch de plataforma y sirve para el piloto),
  hosting y licencias.

### Pendientes decididos por el usuario

- **Diferido a propósito**: qué hacer con la duplicación de libs y la integración de las
  libs del sistema (`Overrides.toml`/`<producto>_path`). Queda documentado, no implementado.

## 2026-10-10 — Anexo: `juliac` (compilar `.jl` a binario) y el paquete

Investigado al margen de los JLL, pero anotado acá porque es otra limitación del
runtime bionic en el dispositivo:

- **Sí existe el camino**: Julia 1.12 trae `juliac`
  (`--output-exe` / `--output-lib` / `--output-sysimage`); `PackageCompiler.jl` es la
  vía clásica. No genera un binario autónomo: linkea `libjulia` **y**
  `libjulia-internal` (`--relative-rpath` deja las libs al lado).
- **Upstream no instala wrapper**: en `release-1.12` el script vive en
  `contrib/juliac/juliac.jl` → `share/julia/juliac/juliac.jl`; `Makefile:92` lo lista
  como dato compartido y **no hay regla** que ponga un nombre en `PATH` (tampoco en
  `cli/`, ni en el manual, ni en `NEWS.md`). El port `julia-termux` agrega `bin/juliac`
  (probado con prefijo reubicado, por symlink y por nombre pelado, 5/5).
- **Y no compila en este teléfono**: `juliac --output-exe hello hello.jl` muere en el
  paso `julia --output-o` con `std::bad_alloc` (308 s; **200 s** con `-O0` inyectado en
  una copia del script, que tampoco alcanza). No falta RAM nominal (12 GB, 7,5 GB
  disponibles) pero `Committed_AS` (220,9 GB) supera largamente `CommitLimit`
  (18,6 GB) **[MEDIDO] 2026-10-10**.
- **No arregla los JLL**: el `.so` del JLL se `dlopen`ea en runtime; son problemas
  ortogonales.

Detalle completo: `../Julia/julia-termux/PROGRESS.md` (Pendientes, item 7).

## 2026-10-10 — `juliac` medido: es RAM, y nuestro build pide ~19% más

Respuesta al "¿es problema de acá o de Julia?" que quedó abierto en el anexo anterior.
Se corrió `juliac --output-exe` con **nuestro** artefacto publicado dentro de un prefijo
Termux materializado en `ubuntu-24.04-arm` (workflow `probe-juliac-binary.yml` del repo
del port; run **38021823582**):

| Quién | Reloj | Pico RSS | Resultado |
|---|---|---|---|
| upstream aarch64 (runner 16 GB) | 2:30 | **6,12 GB** | rc=0, binario corre |
| upstream x86_64 (runner 16 GB) | 2:28 | 4,48 GB | rc=0, binario corre |
| **nuestra julia** (runner 16 GB) | 2:40 | **7,30 GB** | rc=0, binario corre (212 MB, `interpreter /system/bin/linker64`) |
| **nuestra julia** (teléfono) | ~5 min | 6,45 GB | `std::bad_alloc` |

Conclusión: **no es un bug de Julia ni del port**. El paso `julia --output-o` pide
~6-7 GB y el teléfono no los tiene libres con Android encima. Dos consecuencias:
`juliac` es usable donde haya ≥8 GB, y en el dispositivo no; y nuestro build bionic
pide **~1,2 GB más** que el oficial para el mismo hello world (+19%), diferencia que
conviene mirar si algún día se quiere compilar **en** el teléfono.

El probe necesitó 6 iteraciones y **todas** fueron del entorno del runner, no del
código del port: SIGPIPE de `ls | head` bajo `pipefail`, el shim `libm.so` que un
dispositivo tiene y un prefijo solo-.deb no, `bash -e` tragándose el rc de `juliac`,
el `Pkg.precompile()` que clona el registro, `JULIA_PKG_OFFLINE` que no alcanza con
depot sin registro, y `git` resolviendo al biónico del prefijo.  Ver
`../Julia/julia-termux/PROGRESS.md` (Pendientes 7).

## 2026-10-11 — Clasificación de JLLs y el parche de consumo

- `tools/classify-jll.jl`: clasifica por JLL si la librería de Termux satisface lo que el
  JLL declara (productos, SONAMEs, superficie de símbolos), sin cargar el JLL (su `__init__`
  hace `dlopen` del artefacto glibc y revienta acá).  Primera tabla medida: `FFTW_jll`
  needs-jll, `libpng_jll` override-needs-alias, seis stdlibs system-stub.
- Hallazgo estructural: **los stdlib JLLs de un Julia de fuentes ya son stubs de upstream**
  (`dlopen` por soname, `artifact_dir = dirname(Sys.BINDIR)`, cero artefactos en el depot).
  La política "no bajes, usá la del sistema" ya existe para los stdlibs; falta generalizarla
  a los JLLs de la registry.
- Veredicto validado: `libpng` predijo "alcanza un symlink" y con el artefacto apartado la
  JLL cargó la libpng bionic del sistema (`ccall png_access_version_number` → 10659).
- `docs/09` §9.7: el override por hash evita la descarga; el UUID+nombre no (Pkg pierde el
  uuid).  El parche de consumo vive en julia-termux y quedó registrado en `docs/14`.

## 2026-10-11 — El artefacto bionic de FFTW: el primer `needs-jll` resuelto

- `scripts/build-fftw-bionic.sh` (en `../Julia/julia-termux`): construye el artefacto con el
  clang bionic en **dos pasadas** de `configure` (`--enable-threads --with-combined-threads
  --enable-neon --disable-fortran`, la segunda con `--enable-float`), con el tarball pineado
  por sha256.  **Medido**: `libfftw3.so.3.7.11` 1.395.769 B y `libfftw3f.so.3.7.11`
  1.396.537 B, SONAME `libfftw3.so.3` / `libfftw3f.so.3`, **207 codelets `_neon`** cada una,
  `init_threads` presente.
- **Libtool ignora `-version-info` en este host**: su `config.guess` no conoce el triplete
  Android (medido: `.la` con `library_names='libfftw3.so libfftw3.so'` aunque el Makefile
  traía `SHARED_VERSION_INFO = 10:11:7`) ⇒ el naming oficial se arma a mano (archivo real
  versionado + `patchelf --set-soname` + symlinks).
- **Aceptación**: programa C bionic que carga por soname, inicializa threads y ejecuta una
  transformada → `dc[1] = -4.000 9.657` (rc=0).  Gap restante: 102 símbolos, **todos**
  wrappers Fortran (`dfftw_*`/`sfftw_*`), que ningún consumidor de Julia usa.
- **Publicado y verificado en el dispositivo**: release `fftw-bionic` (1.555.734 B, sha256
  `3c3e8f50…`) bajado al teléfono; con el artefacto glibc apartado del depot y el override
  UUID+nombre, `FFTW_jll.libfftw3_path = …/fftw-bionic/lib/libfftw3.so`, `fft/ifft`, `rfft`,
  `plan/apply` y `dct/idct` correctos, y **el depot sin bajar nada**.
- Workflow propio (`build-fftw-bionic.yml`, ~4 min, grupo de concurrencia propio, no toca
  `packages/julia/**`): así un cambio del artefacto no invalida el caché del build de Julia
  (~60 min).  Tres corridas fallaron por trampas del entorno del runner (normalizar una ruta
  antes de crearla, el `/bin/sh` glibc con el `LD_PRELOAD` bionic → *invalid ELF header*, la
  caché del tarball recomputada tras el re-exec, y `tar | head` bajo `pipefail`); las tres
  quedaron registradas en `../Julia/julia-termux/AGENTS.md`.
