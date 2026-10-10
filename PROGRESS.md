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
