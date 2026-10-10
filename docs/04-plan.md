# 04 — El plan, por fases

**Objetivo final**: que `Pkg.add("<pkg con binario>")` funcione en Termux/Android bionic
porque existe un artefacto JLL `aarch64-linux-android` que Pkg elige.

**Principio**: cada fase es incremental, tiene **un entregable** y **un criterio de
aceptación** (`06-verificacion.md`). No se pasa a la siguiente sin ese criterio verde.

**Alcance declarado**: no se promete el ecosistema entero. Se arranca con **un JLL
(FFTW_jll) end-to-end** y después se extiende a un conjunto acotado de libs frecuentes.

---

## Fase 0 — Baseline y target

**Objetivo**: dejar reproducido el fallo y fijar las coordenadas del proyecto.

**Trabajo**
- Reproducir el rojo en el dispositivo (ya medido: `Pkg.add("FFTW")` →
  `libm.so.6 not found`). Guardar el log.
- Fijar el **triple/tag**: `aarch64-linux-android` con `libc="bionic"`. Decidir el
  `os_version`/API level (candidato: la del dispositivo, `android24` = minSdk 24) y el
  `cxxstring_abi` (`cxx11`, libc++ de Termux).
- Pinear **todos** los insumos por commit/tag: Julia (la del port `julia-termux`), NDK
  (rXX, revisión exacta), `BinaryBuilderBase`, `BinaryBuilder`, `JLLWrappers`, `Yggdrasil`.
- Definir el JLL piloto: **`FFTW_jll`** (lib chica, ya hay `fftw` en Termux para comparar
  símbolo a símbolo).

**Entregable**: `docs/` con la tabla de pins + el log rojo.

**Criterio**: el log rojo se reproduce desde cero con un comando documentado.

---

## Fase 1 — Plataforma Android/bionic en `Base.BinaryPlatforms`

**Objetivo**: que Julia pueda *nombrar* la plataforma y que el host la reporte.

**Trabajo**
- Patch reproducible sobre el pin de Julia (mismo enfoque que
  `tur-on-device/julia` patch `0001`):
  - `validate_tags`: admitir `libc="bionic"` en Linux.
  - `libc_str` / `libc_mapping`: `bionic` ↔ `-android` (y el parseo de
    `aarch64-unknown-linux-android24` → `os="linux", libc="bionic"`, `os_version="24"`).
  - Decidir si `HostPlatform()` devuelve `bionic` **siempre** en Android (cambia la
    selección para todos los JLL) o si es **opt-in** por env/preferencia.
- **Alternativa a considerar**: no parchear y usar `validate_strict=false` + un tag
  custom; más frágil.

**Entregable**: patch + build de Julia que reporte la plataforma bionic.

**Criterio**: en el dispositivo, `HostPlatform()` devuelve `libc="bionic"`, y un JLL con
artefacto bionic (aunque sea de prueba) lo **elige** Pkg. Rojo→verde: antes elige gnu,
después bionic.

**Riesgo**: es un cambio de comportamiento global; si se rompe la selección, nada carga.
Mitigación: opt-in y tests de no-regresión sobre `HostPlatform()`.

---

## Fase 2 — Shards de compilador bionic en `BinaryBuilderBase`

**Objetivo**: tener un toolchain reproducible para compilar C/C++ contra bionic.

**Trabajo**
- El toolchain es el **NDK** (clang + sysroot bionic), no GCC. Investigar el modelo de
  shards: BinaryBuilderBase descarga "shards" de compilador; para Android hay que
  **producir uno** (empaquetar el NDK con la estructura que espera) o extender el modelo
  para el NDK.
- Definir: sysroot, API level, `--target=aarch64-linux-android24`, `libc++_shared`.
- Probar a mano un `clang --target=...` con el NDK del host antes de automatizar.

**Entregable**: un shard/`Artifacts.toml` de toolchain Android que BinaryBuilderBase pueda
resolver.

**Criterio**: desde un runner, BinaryBuilderBase obtiene el toolchain y compila un
`hello.c` compartido que `dlopen`ea en el dispositivo.

**Riesgo**: alto — es la parte menos documentada. Si el modelo de shards no encaja, la
alternativa es un `Runner` que monte el NDK directamente (Fase 3).

---

## Fase 3 — Target en `BinaryBuilder.jl` / `Rootfs`

**Objetivo**: que una receta con `Platform("aarch64","linux"; libc="bionic")` corra.

**Trabajo**
- Añadir el target a `supported_platforms()`/`Rootfs` (mapear triple → imagen/toolchain).
- `UserNSRunner`/`Runner` con el rootfs preparado para Android.
- Autoconf/CMake: variables `--host`/`--target`, `CMAKE_SYSTEM_NAME=Android`,
  `CMAKE_ANDROID_NDK`, `ANDROID_ABI=arm64-v8a`, `ANDROID_PLATFORM=android-24`.

**Entregable**: `build_tarballs.jl` de una lib trivial corre y produce `.tar.gz` para
bionic.

**Criterio**: el tarball contiene un `.so` bionic (`NEEDED libc.so`, sin `libm.so.6`) y
`dlopen`ea en el dispositivo.

---

## Fase 4 — Recetas Yggdrasil + host de artefactos

**Objetivo**: `FFTW_jll` con artefacto Android, instalable con `Pkg.add`.

**Trabajo**
- Fork/patch de la receta `F/FFTW/build_tarballs.jl` para incluir la plataforma bionic.
- Correr el build (en CI arm64, no en el teléfono).
- Publicar el artefacto: GitHub Releases en un **fork de `JuliaBinaryWrappers/FFTW_jll.jl`**
  (o un host propio).
- Generar el `Artifacts.toml` con la entrada `aarch64-linux-bionic` (url+sha) y el wrapper
  con JLLWrappers. Decidir **cómo se distribuye** el JLL parcheado:
  - (a) un fork del JLL publicado en un **registro propio** (LocalRegistry) que el usuario
    agrega, o
  - (b) `Overrides.toml` que apunte el artefacto a un path/hash propio (no requiere
    registry).
  - (b) es más simple para probar; (a) es más "de verdad".

**Entregable**: `Pkg.add("FFTW")` → `using FFTW` → `fft(x)` funciona en bionic.

**Criterio**: en el dispositivo, un cómputo FFT real da el resultado correcto y el `.so`
cargado es el bionic (verificado con `dlpath`/`llvm-readelf`).

**Riesgo**: mediano; ya hay precedente (TUR construye Julia nativo).

---

## Fase 5 — Extensión y automatización

**Objetivo**: pasar de 1 lib a un conjunto útil.

**Trabajo**
- **Lista priorizada** (ejemplos): openssl, zlib, libnghttp2, libssh2, libgit2, libpng,
  libjpeg-turbo, libtiff, libxml2, sqlite, gmp, mpfr, mpc, fftw, gsl, hdf5, netcdf,
  suitesparse, blas/lapack, libcurl, libtiff.
- Automatizar: script que, para un pin de Yggdrasil y una lista de recetas, aplique el
  patch Android, corra el build en CI y publique artefactos + `Artifacts.toml`.
- Medir **cobertura real**: cuántos de los top-N paquetes de Julia (por descargas) quedan
  usables.

**Entregable**: N ≥ 10-20 JLLs con artefacto bionic, con su tabla de cobertura.

**Criterio**: la tabla dice, por lib, "carga / no carga / no está" — sin promesas.

---

## Fase 6 — Upstream

**Objetivo**: dejar de mantener forks.

**Trabajo**
- PRs a `Base.BinaryPlatforms` (plataforma Android/bionic), `BinaryBuilderBase` (shard
  NDK), `BinaryBuilder` (target), Yggdrasil (recetas).
- Coordinar con el issue `BinaryBuilder.jl#846`.

**Criterio**: al menos el soporte de plataforma upstream; idealmente el toolchain.

---

## Camino corto (validación temprana, opcional)

Antes de Fase 2-3 (lo más caro), se puede validar el resto de la cadena **a mano**:
compilar `libfftw3.so` con el NDK **fuera** de BinaryBuilder, armar el `.tar.gz`, calcular
el `git-tree-sha1`/`sha256`, escribir el `Artifacts.toml`, y probar con `Overrides.toml`.
Si eso funciona end-to-end, las fases 2-3 son "solo" automatizar. **Este es el primer
experimento recomendado.**

---

## Estimación honesta

| Fase | Esfuerzo | Riesgo |
|---|---|---|
| 0 | horas | bajo |
| 1 | días | medio (efectos globales) |
| 2 | **semanas** | **alto** (parte no documentada) |
| 3 | semanas | alto |
| 4 | días | medio |
| 5 | continuo (por lib) | medio |
| 6 | meses (proceso upstream) | medio |

El cuello de botella son las fases 2-3. Por eso el "camino corto" primero.
