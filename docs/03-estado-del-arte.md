# 03 — Estado del arte (octubre 2026)

Todo afirmado acá tiene URL en [`08-referencias.md`](08-referencias.md). Lo que no existe,
se dice que **no existe**.

## 3.1 BinaryBuilder / BinaryBuilderBase

- **No soporta Android.** La lista oficial de plataformas es Linux (x86_64, i686, armv6l,
  armv7l, aarch64, ppc64le), Windows, macOS (x86_64, aarch64) y FreeBSD (x86_64, aarch64).
  `supported_platforms()` devuelve 18 plataformas, todas gnu/musl/apple/freebsd/windows.
- **No hay shards de compilador bionic**: el `Artifacts.toml` de BinaryBuilderBase tiene
  1014 shards `GCCBootstrap-*` para `*-linux-gnu`, `*-linux-musl`,
  `*-unknown-freebsd*`, `*-w64-mingw32`; **cero `android`/`bionic`**.
- **Issue abierto**: [`BinaryBuilder.jl#846`](https://github.com/JuliaPackaging/BinaryBuilder.jl/issues/846)
  ("Binary builder fails on Termux (aarch64-unknown-linux-android)", 2020). `staticfloat`:
  *"First off, we don't officially support Android, so you're going to be hitting
  codepaths that possibly noone else has ever hit."* Sigue abierto.
- **No hay PRs Android** en BinaryBuilder.jl, BinaryBuilderBase.jl ni Yggdrasil.

## 3.2 Julia `Base.BinaryPlatforms`

- No existe `os="android"` ni `libc="bionic"` en la validación oficial (linux:
  `libc ∈ {glibc, musl}`). Presente igual en `master`, `release-1.11/1.12/1.10`.
- No hay issue/PR de "Android platform support" en `JuliaLang/julia` ni `JuliaPackaging`.
- Precedente de agregar un ABI: Windows **ucrt**
  ([#59027](https://github.com/JuliaLang/julia/issues/59027), [PR #59029](https://github.com/JuliaLang/julia/pull/59029)).
- Política: [#28545](https://github.com/JuliaLang/julia/issues/28545) (cerrado): *"While
  Julia may happen to run on the necessary architectures for iOS and Android, at this time
  we do not actively target those platforms."*

## 3.3 Yggdrasil y `JuliaBinaryWrappers/*`

- **Cero** artefactos `aarch64-linux-android`/`bionic` publicados. La búsqueda de código en
  la organización no encuentra ninguno; los únicos `android` en Yggdrasil son **parches de
  código fuente** de terceros (CyrusSASL, Zstd, OpenCV, LLVM…), nunca una `Platform`
  Android.
- Aunque una receta declarara Android, **no hay shard de compilador bionic** para
  construirlo (§3.1).

## 3.4 Esfuerzos existentes en Termux

- **`termux-user-repository/tur` → `tur-on-device/julia`** (Julia 1.10.12, build nativo en
  dispositivo). Es el **único port que parchea `Base.BinaryPlatforms` para bionic**:
  - `0001-platform-and-triplet-detection.patch`: `libc ∉ ("glibc","musl")` pasa a incluir
    `"bionic"`; `libc_mapping["bionic"] = "-(android|bionic)[\\d\\.]*"`; `libc_str` →
    `"-android"`.
  - `0005-loader-and-system-libraries.patch`: parchea los stubs `*_jll` para `dlopen`
    tolerante de `libgcc_s`/`libgfortran`/`libstdcxx`/`libgomp` y symlinks a libs del
    sistema.
  - **No usa JLLs**: `USE_BINARYBUILDER=0`, `DISABLE_CSL=1`, `USE_SYSTEM_*=1`,
    `JULIA_PRECOMPILE=0`.
- **`termux/glibc-packages`** (`glibc-repo` + `glibc-runner`): la comunidad corre el Julia
  **glibc oficial** con eso y **todos los JLL glibc cargan**. Confirmado en Discourse
  (junix, 2026-04-09). Es la respuesta soportada hoy para "quiero el ecosistema".
- **Predecesor**: `its-pointless/julia` rama `android-termux` + `gcc_termux` (2020). README:
  *"installing packages that link to libs is a bit tricky and requires writing deps.jl
  yourself so they point to installed termux libs"*.
- **No existe** un registry/overlay JLL para Termux/bionic (ni "TermuxJLL" ni similar).

## 3.5 Cómo lo resuelven otros ecosistemas

| Ecosistema | Estrategia |
|---|---|
| **Python** | PEP 738 (Final, 3.13): wheels con tag `android_<api>_<abi>` (ej. `android_21_arm64_v8a`). `cibuildwheel` ya compila Android (PR #2349, 2025-07-23); PyPI sirve esos wheels. |
| **Rust** | Triples nativos `aarch64-linux-android`, `armv7-linux-androideabi`, etc. (`rustup target add`). |
| **Node** | Sin prebuilds Android; los addons nativos se compilan localmente contra bionic (node-gyp/N-API); Android es "experimental". |

**Patrón común**: compilar con el **NDK** para bionic y publicar en el **registry del
ecosistema con un tag por ABI**. Es exactamente el hueco que Julia no tiene.

## 3.6 Discusiones

- robsmith11 (Discourse #8086, 2019): diagnóstico canónico — *"many Julia packages that
  require a pre-built library will not work as-is since they are linked with glibc"* y *"the
  minimal Termux approach will only work with base Julia and packages that don't depend on
  BinaryBuilder"*.
- termux-packages#58 (histórico, 2017-2024): *"You can't run because of libc differences
  mostly"*.
- No hay un hilo dedicado a "JLLs en Android" ni a `libm.so.6 not found` en Julia.

## 3.7 Síntesis

| Pieza | Android/bionic hoy |
|---|---|
| BinaryBuilder / BinaryBuilderBase | ❌ sin target, sin shards |
| `Base.BinaryPlatforms` | ❌ sin `os=android`/`libc=bionic` |
| Yggdrasil | ❌ sin recetas Android |
| `JuliaBinaryWrappers/*` | ❌ cero artefactos android |
| JLLWrappers | ✅ genérico (sirve si el artefacto existe) |
| Pkg / Artifacts | ✅ genérico |
| Registry JLL para Termux | ❌ no existe |

El trabajo del plan (`04-plan.md`) es convertir esos ❌ en ✅, empezando por los dos
primeros, que son los que desbloquean todo lo demás.
