# 14 — Clasificación de JLLs: override, symlink o Yggdrasil (2026-10-11)

`tools/classify-jll.jl` responde, por JLL, la pregunta que decide si Yggdrasil tiene que
construir algo: **¿la librería que Termux ya shipa satisface lo que el JLL declara?**  Un
`Overrides.toml` que apunte el artefacto a `$PREFIX` solo es sano si el paquete del
sistema expone *los mismos productos, en las mismas rutas, con la misma superficie de
símbolos*.

## Cómo mide

1. instala el JLL en un entorno temporal y **no lo carga** (`using Foo_jll` corre el
   `__init__` generado, que hace `dlopen` del artefacto: en esta plataforma eso es el
   `.so` glibc que no carga, así que el módulo revienta antes de poder preguntarle nada —
   medido: `InitError`, `libm.so.6`);
2. resuelve el artefacto que Pkg elegiría para este host (la misma llamada que hace Pkg)
   y lo baja si falta — ese peso **es** la duplicación que hoy cuesta cada JLL;
3. lee los productos del wrapper de la plataforma y, por cada uno, compara contra
   `$PREFIX`: ¿existe el archivo?, ¿resuelve el SONAME al lado?, ¿qué símbolos definidos
   tiene el build oficial que el del sistema no? (sin contabilidad del linker ni nodos de
   versión);
4. imprime un veredicto y, cuando pasa, la línea de `Overrides.toml` que corta la
   descarga.  La línea va **por hash** a propósito: la forma UUID+nombre es estable pero
   **no** evita la descarga (ver §9.7).

## La primera tabla (medida en el teléfono)

| JLL | veredicto | evidencia |
|---|---|---|
| `FFTW_jll` | **needs-jll** → **resuelto con un artefacto bionic** (§14.1) | 235 símbolos de API faltantes: `fftwf_cleanup_threads`, `fftwf_codelet_*_neon`, … — el artefacto oficial fusiona el API de threads en `libfftw3` y Termux usa el layout de upstream; además faltan los codelets NEON |
| `libpng_jll` | **override-needs-alias** | 240/240 símbolos coinciden; solo falta el *nombre* `libpng16.so.16` (Termux shipa `libpng16.so`) |
| `Zlib_jll` | **system-stub** | stub de stdlib: `dlopen("libz.so.1")`, lo responde `$PREFIX/lib` |
| `OpenSSL_jll` | **system-stub** | `libcrypto.so.3`, `libssl.so.3` en `$PREFIX/lib` |
| `LibCURL_jll` | **system-stub** | `libcurl.so.4` ← alias creado por la receta |
| `LibGit2_jll` | **system-stub** | `libgit2.so.1.9` ← alias de la receta |
| `MPFR_jll` | **system-stub** | `libmpfr.so.6` ← alias de la receta |
| `GMP_jll` | **system-stub** | `libgmp.so.10`, `libgmpxx.so.4` ← alias de la receta |

## El hallazgo que ordena todo

**Los stdlib JLLs de un Julia construido de fuentes ya son stubs** (upstream, no del
port): `## dummy stub for …`, `dlopen` por soname, `artifact_dir = dirname(Sys.BINDIR)`.
Medido: `GMP_jll.libgmp_path = $PREFIX/lib/libgmp.so`,
`Zlib_jll.libz_path = $PREFIX/lib/libz.so.1.3.2`, y el depot **no tiene** ningún artefacto
de stdlib.  O sea: la política "no bajes, usá la del sistema" ya está en Julia para los
stdlibs, y los nombres que Termux no shipa los crea el mecanismo de aliases de la receta
(`needed-library-aliases.sh`).  Lo que falta es **generalizarla a los JLLs de la
registry**, que sí son wrappers de BinaryBuilder con rutas de artefacto.

## Validación del veredicto (no alcanza con que suene bien)

`libpng_jll` predijo "alcanza un symlink" ⇒ se probó:

```
ln -sfn libpng16.so $PREFIX/lib/libpng16.so.16
"b56293e57ba0…" = "/data/data/com.termux/files/usr"      # Overrides.toml, por hash
# con el artefacto apartado del depot:
libpng_jll.libpng_path = /data/data/com.termux/files/usr/lib/libpng16.so
ccall png_access_version_number = 10659
```

Una JLL **funcionando en bionic sin compilar nada**, y el artefacto no volvió a bajarse.

> **A escala**: `docs/15` corre esta misma clasificación sobre 43 JLLs (los que Termux ya
> satisface más su clausura) y valida los overrides con una corrida real.  Resultado medido:
> 23 overrides gratis, 7 con gap real, y 5 bloqueadores raíz detrás de casi todos.

## 14.1 El primer `needs-jll` resuelto: el artefacto bionic de FFTW (2026-10-11)

`FFTW_jll` era el caso que decidía si Yggdrasil tenía razón de existir: la librería **está**
en Termux, pero no sirve para el JLL.  Medido: el build de Termux trae el layout de
upstream (`fftw_init_threads` en `libfftw3_threads.so`) y el artefacto oficial fusiona el
API de threads dentro de `libfftw3` (es lo que pide el wrapper: `libfftw3_no_init`), y sus
codelets NEON no están en el paquete del sistema.  De ahí los 235 símbolos de diferencia.

La conclusión no fue "override" ni "shim": fue **construir el artefacto**, con la misma
receta que el oficial pero con el clang bionic, y distribuirlo como artefacto +
`Overrides.toml`.  Es la Fase 4 del plan, **sin BinaryBuilder**.

**Cómo se construye** (`../Julia/julia-termux/scripts/build-fftw-bionic.sh`, reproducible:
tarball pineado + sha256):

- **dos pasadas** de `configure` (fftw construye una precisión por vez):
  `--enable-shared --disable-static --enable-threads --with-combined-threads --enable-neon
  --disable-fortran`, la segunda con `--enable-float`.  `--with-combined-threads` es
  justamente el flag que produce el layout que el JLL espera, y `--enable-neon` los codelets;
- **el naming oficial se arma a mano**: libtool **ignora `-version-info` en este host** (su
  `config.guess` no conoce el triplete Android: medido, el `.la` salió
  `library_names='libfftw3.so libfftw3.so'` mientras el Makefile sí traía
  `SHARED_VERSION_INFO = 10:11:7`) ⇒ archivo real `.so.3.7.11`,
  `patchelf --set-soname libfftw3.so.3`, y los dos symlinks;
- **aceptación, no "compiló"**: un programa C bionic que carga por el nombre que el JLL
  declara, inicializa el API de threads y ejecuta una transformada — medido
  `dc[1] = -4.000 9.657`, `soname=libfftw3.so.3`, `threads=1`, `neon_codelets=207` por lib.

**El gap que queda**: 102 símbolos, **todos wrappers Fortran** (`dfftw_*`/`sfftw_*`), que
fftw genera con un compilador Fortran que este entorno no tiene.  Ningún consumidor de
Julia los usa (FFTW.jl va por la API C); el clasificador los reporta como la única
diferencia contra el artefacto oficial.

**Medido end-to-end en el teléfono, con el artefacto publicado** (release `fftw-bionic` de
`Leonisaurov/julia-termux`, 1.555.734 B, sha256 `3c3e8f50…`, bajado y verificado en el
dispositivo):

```
libfftw3_path  = /data/data/com.termux/files/home/.local/opt/fftw-bionic/lib/libfftw3.so
libfftw3f_path = …/fftw-bionic/lib/libfftw3f.so
fft/ifft ok = true   rfft ok = true   plan/apply ok = true   dct/idct ok = true
depot: solo Overrides.toml   # el artefacto glibc oficial apartado ⇒ no se bajó nada
```

O sea: **FFTW.jl funciona en bionic**, con el override por UUID+nombre (estable entre
versiones del JLL, gracias al parche de `Pkg` que describe la sección siguiente) y sin duplicar la descarga.

**El workflow es barato y aparte**: `build-bionic-artifact.yml` tiene su propio grupo de
concurrencia y **no toca `packages/julia/**`**, así que no puede invalidar el caché del
build de Julia (que cuesta ~60 min); construye el artefacto en ~4 min.

## El lado del consumo ya tiene parche (2026-10-11)

La forma **estable** de override (UUID+nombre) no evitaba la descarga porque el camino de
descarga de `Pkg` perdía el uuid; `julia-termux` ahora lo parchea
(`packages/julia/patches/Pkg-Operations.jl.patch`, aplicado a la copia instalada porque Pkg
es un submodule).  Con eso la tabla JLL→paquete de Termux se publica **una vez** y no se
reescribe con cada versión del JLL — que era el motivo por el que la forma por hash, aunque
funciona, no servía como política.

## La regla, y el reparto

1. ¿Termux shipa la librería?  Si no → **Yggdrasil**.
2. ¿El sistema expone los productos/símbolos que el JLL declara? → **override** (cero descarga, cero build); si solo falta el nombre → **override + symlink**.
3. Si el build del sistema exporta menos API (otra feature set) → **Yggdrasil o un shim**; `FFTW_jll` es el caso medido y ya resuelto con un artefacto bionic (§14.1).
