# 11 — Fallos conocidos y limitaciones

Catálogo honesto de todo lo que **no** funciona o tiene un techo, para no redescubrirlo ni
prometer de más. Cada línea está marcada:

- **[MEDIDO]** — reproducido en este teléfono (Termux aarch64, Julia 1.12.6 bionic).
- **[CITADO]** — del fuente o de una fuente externa (ver `08-referencias.md`).
- **[INFERIDO]** — consecuencia lógica de lo anterior, todavía sin medir.

---

## 11.1 La falla central (lo que este repo ataca)

| Fallo | Síntoma | Causa raíz | Doc |
|---|---|---|---|
| **Un paquete con JLL no carga** | `dlopen failed: library "libm.so.6" not found: needed by …/libfftw3.so.3.7.11` | Pkg baja el artefacto **glibc**; bionic no puede ejecutarlo | `01-problema.md` |

**[MEDIDO]** `Pkg.add("FFTW"); using FFTW` muere ahí. Paquetes **puros** (sin binario) sí
funcionan.

---

## 11.2 Fallos del ecosistema (no son del port)

| Fallo | Detalle | Estado |
|---|---|---|
| **No hay artefactos Android publicados** | Cero entradas `aarch64-linux-android`/`bionic` en `JuliaBinaryWrappers/*` | **[CITADO]** |
| **BinaryBuilder no soporta Android** | 18 plataformas gnu/musl/apple/freebsd/windows; **0 shards** de compilador bionic | **[CITADO]** (issue #846, abierto desde 2020) |
| **`BinaryPlatforms` no modela Android** | En Linux `libc ∈ {glibc, musl}`; no hay `os="android"`. Con `validate_strict=false` el tag `bionic` *se acepta*, pero no hay artefactos que matcheen | **[CITADO] + [MEDIDO]** |
| **`libm.so.6` / `libc.so.6` / `libpthread.so.0`** | Sonames de glibc que bionic no tiene | **[MEDIDO]** |
| **Symbol versioning `@GLIBC_2.17`** | Bionic no implementa el versionado de símbolos de glibc → ni con symlinks se arregla | **[MEDIDO]** |
| **musl dinámico** | Pide `ld-musl-aarch64.so.1` (no existe en Android) → `rc=127` | **[MEDIDO]** (en el workspace: `mimocode`; el musl estático de `Kiro` sí corre) |
| **Dos libc en un proceso** | Cargar un `.so` musl o glibc dentro de un proceso bionic = comportamiento indefinido | **[INFERIDO]** |

---

## 11.3 Limitaciones del entorno Android/Termux

| Limitación | Síntoma | Causa | Alcance |
|---|---|---|---|
| **`Sys.cpu_info()`** | `IOError: uv_cpu_info: permission denied (EACCES)` | SELinux/sysfs del dispositivo | **`versioninfo()` también falla** (lo llama) **[MEDIDO]** |
| **Harness de tests** | `Base.runtests` → `signal 31 (Bad system call)` | seccomp de la app Android | Los ficheros de test sueltos **sí** corren (`include` directo) **[MEDIDO]** |
| **Sin runtime GCC** | Faltan `libgcc_s`, `libstdc++`, `libgfortran`, `libgomp` en bionic | Android no trae GCC runtime | Los `_jll` que los piden deben ir **guardados** (`do...catch`) **[MEDIDO]** |
| **Sin `libm.so.6`/`libc.so.6`** | Idem §11.2 | bionic usa otros sonames | Afecta a **cualquier** binario glibc **[MEDIDO]** |
| **Restricciones de `/proc`, `/sys`** | lecturas denegadas | SELinux/Android | Puede romper detección de CPUs, topología, etc. **[MEDIDO parcial]** |

> Estas limitaciones son **del dispositivo**, no del port: aplican igual a glibc-runner.

---

## 11.4 Limitaciones del runtime/paquete (Julia 1.12)

| Limitación | Detalle |
|---|---|
| **`Arpack`, `FFTW`, `MbedTLS` ya no son stdlibs** | **[MEDIDO]** `using FFTW` → `Package FFTW not found in current path` (hay que `Pkg.add`, y ahí entra §11.1) |
| **El `.deb` no trae docs HTML** | A diferencia del paquete de Termux; decisión de la receta (evita red en `make install`) |
| **`ccall((:f, handle))` cambió** | **[MEDIDO]** en 1.12 el slot de librería espera `String`/`Symbol`/`LazyLibrary`; usar `dlsym` + `ccall(ptr)` |
| **`Base.BLAS` ya no existe** | **[MEDIDO]** en 1.12 es `LinearAlgebra.BLAS` |
| **`Base.runtests` cambió de firma** | **[MEDIDO]** `ncores`, no `nthreads`/`verbose` |
| **`Sys.STDLIB` bakeado al prefijo de build** | **[MEDIDO]** un `.deb` extraído a un prefijo distinto resuelve stdlibs contra el prefijo de build |
| **`bin/juliac` no viene en el paquete** | **[MEDIDO]** upstream 1.12 no instala wrapper: el script está en `share/julia/juliac/juliac.jl` (`Makefile:92`) y no hay regla que ponga un nombre en `PATH`. El port lo agrega (2026-10-10) |
| **`juliac` necesita ~6-7 GB de RSS** | **[MEDIDO en CI 2026-10-10]** con un hello world: upstream aarch64 **6,12 GB** y x86_64 4,48 GB (rc=0, binario que corre); **nuestra** julia bionic **7,30 GB** (rc=0, binario Android aarch64 de 212 MB que corre). El teléfono muere a **6,45 GB** con Android repartiendo sus 7,5 GB → no es un bug de Julia ni del port, es RAM (y nuestro build pide ~19% más que el oficial). `-O0` **sube** el pico a 8,86 GB; `--heap-size-hint` no lo mueve (6,90 GB); `--output-incremental` lo bloquea el propio driver del `juliac` |
| **Pero `--trim` baja ese pico 16×** | **[MEDIDO]** `--trim=unsafe` + `JULIA_CPU_TARGET=generic`: **0,43 GB** y 9 s (vs 6,86 GB y 2:40), binario de **1,67 MB** (vs 212 MB), y **corre en el teléfono** (run 38070301714, ejecutado aquí). Dos condiciones: el programa no puede tener dispatch que el verificador no pruebe (`print` de Base pasa por `Any` → usar `ccall(:write, …)`; bajo `unsafe` una llamada no probada no emite código y no hay JIT: `Core.MissingCodeError`), y hay que compilar con `JULIA_CPU_TARGET=generic` o el teléfono rechaza el código del runner (`Target 0 (neoverse-n2): Rejecting this target due to use of runtime-disabled features`) |
| **`--trim=safe` no lo alcanza ni un programa sin `print`** | **[MEDIDO]** su verifier error #1 pasa a ser `Core._apply_iterate(Base.iterate, Base._string, a::Any)` en `load_openblas() @ OpenBLAS_jll/src/OpenBLAS_jll.jl:49` ← `__init__() @ …:101`: el init de un JLL **del propio sysimage**, no del programa. Es un muro de upstream/base, no del usuario |
| **Correr nuestra julia en un runner necesita emular el namespace de Android** | **[MEDIDO]** un prefijo hecho solo con `.deb` no tiene el `libm.so` que en un dispositivo responden el namespace de Android y el symlink del bootstrap (`$PREFIX/lib/libm.so`, **sin dueño**: `pacman -Qo` no lo reclama). Sin él, el artefacto ni imprime su versión: `Unable to load dependent library .../lib/julia/libm.so` |
| **El bionic del runner no resuelve DNS** | **[MEDIDO]** `juliac` arranca con `Pkg.precompile()`, que intenta clonar el registro General → `No address associated with hostname`. `JULIA_PKG_OFFLINE` no basta: con un depot **sin** registro, Pkg instala uno igual. Y llamar `git` pelado tampoco: `PATH` con `$PREFIX/bin` delante resuelve al git **biónico** (rc=128) |
| **`libjulia-internal.so` vive en `lib/julia/`** | **[MEDIDO]** el link de un binario nativo pide `-ljulia -ljulia-internal`, y esa lib no está en `lib/` |

---

## 11.5 Limitaciones del enfoque Yggdrasil

| Limitación | Detalle | Mitigación |
|---|---|---|
| **Duplicación de librerías** | El JLL es **hermético**: no reusa la `.so` del sistema, baja su copia | `Overrides.toml` / `<producto>_path` (`09-…md`) |
| **ABI/versión por lib** | Termux tiene `fftw 3.3.11`, el JLL espera `3.3.12` | Fijar/validar por lib; SONAME mayor |
| **Churn de versiones** | Cada actualización de un JLL implica recompilar el artefacto bionic | Automatizar el pipeline |
| **Alcance inabarcable** | Yggdrasil tiene **miles** de recetas y cada una es un build | Conjunto inicial acotado + tabla de cobertura |
| **Toolchain bionic no soportado** | Es la parte **no documentada** (fases 2-3 del plan) | "Camino corto" primero: NDK a mano |
| **Mantenimiento de forks** | BinaryBuilder(Base)/Yggdrasil/JLLs hay que rebasar | Empujar a upstream (Fase 6) |
| **Distribución** | Un JLL parcheado no está en el registro General | Registro propio (LocalRegistry) o `Overrides.toml` |
| **Licencias** | Los artefactos son de terceros | Respetar `LICENSE` de cada lib; declararlo |
| **Doble carga en un proceso** | Dos copias de estado global si se mezclan | Evitar mezclar sistema + JLL |

---

## 11.6 Matriz medida: qué funciona y qué no (en el dispositivo)

### ✅ Funciona
- **Lenguaje**: `-e`, aritmética, strings, regex (JIT PCRE2), excepciones, IO.
- **Stdlibs**: `LinearAlgebra`, `SparseArrays`, `SuiteSparse`, `Dates`, `Printf`,
  `Random`, `Statistics`, `SharedArrays`, `Sockets`, `Unicode`, `REPL`, `Profile`,
  `InteractiveUtils`, `LibGit2`.
- **BLAS/LAPACK** (libopenblas/LBT, LP64): `\`, `inv`, `cholesky`, `lu`, `eigvals`, GEMM.
- **Threads** (`@threads`, atómicos) y **Distributed** (`addprocs`).
- **Codegen LLVM**: `code_llvm` emite IR.
- **Pkg y red**: `Pkg.add`/`instantiate`/`test` de paquetes **puros**; registro; HTTPS/TLS.
- **Tests sueltos de Julia**: `ccall`, `regex` (170/170), `llvmcall`, `int`, `floatfuncs`,
  `abstractarray`, `operators`.

### ❌ No funciona
- **Paquetes con JLL binario** (la falla central, §11.1).
- **`Sys.cpu_info()` / `versioninfo()`** (§11.3).
- **`Base.runtests`** (§11.3).
- **`threads.jl`** (suite): no terminó en 20 min — **[INFERIDO]** lento, no roto.
- Paquetes que necesiten runtime GCC.
- Paquetes que sean stdlib en versiones viejas y ya no (`Arpack`/`FFTW`/`MbedTLS`).

---

## 11.7 Troubleshooting: mensajes y qué significan

| Mensaje | Significado | Qué hacer |
|---|---|---|
| `dlopen failed: library "libm.so.6" not found` | JLL glibc en bionic | Este repo (artefacto bionic) o `Overrides.toml` |
| `dlopen failed: library "libc.so.6" not found` | ídem | ídem |
| `symbol … @GLIBC_2.17 not found` | symbol versioning de glibc | ídem |
| `…: No such file or directory` sobre un **archivo que existe** | intérprete ausente (musl dinámico) | Estático, o bionic |
| `rc=127` con un `.so`/ELF | loader no encontrado | ídem |
| `uv_cpu_info: permission denied (EACCES)` | SELinux | Ambiental; capturar la excepción |
| `signal 31 (Bad system call)` | seccomp de Android | Ambiental |
| `ArgumentError: Package X not found in current path` | X ya no es stdlib | `Pkg.add` → §11.1 |
| `UndefVarError: Base.BLAS` | se movió | `LinearAlgebra.BLAS` |
| `TypeError: in dlopen, expected Union{String, Symbol, LazyLibrary}` | `ccall` con handle | `dlsym` + `ccall(ptr)` |
| `InitError: could not load library …` | wrapper del `dlopen` de arriba | Ver la línea de abajo |

---

## 11.8 Fallos ya resueltos en el port `julia-termux` (para no confundir)

Estos **no** son parte de este repo, pero aparecieron en el camino y están cerrados:

- `libz.so.1 not found` (libLLVM con RUNPATH `$ORIGIN`) → alias de `DT_NEEDED` derivados.
- TLS sin CA bundle (`share/julia/cert.pem`) → link a `etc/tls/cert.pem`.
- Pkgimages con `NOTYPE UND` → exclusión acotada en la receta.
- Bundle pacman con `OUTPUT_DIR` relativo → canonizado.
- Caché de CI que recompilaba por cambios de script → clave por receta + `restore-keys`.
- `gh release` sin `checkout` en el job publish → `GH_REPO`.

---

## 11.9 Fuera del alcance de este repo

- **glibc-runner** (`termux/glibc-packages`): la alternativa que **sí** da todos los JLL hoy,
  a costa de no ser bionic. Documentada en `05-alternativas.md`.
- **musl**: descartado (`05-alternativas.md`).
- **Portar el ecosistema entero**: no es el objetivo; el alcance es acotado y medido.
