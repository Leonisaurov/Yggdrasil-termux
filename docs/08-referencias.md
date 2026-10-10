# 08 — Referencias (todas las fuentes)

## Julia / plataforma
- `Base.BinaryPlatforms` (validación `libc`, default glibc en Linux, `validate_strict`):
  https://github.com/JuliaLang/julia/blob/master/base/binaryplatforms.jl · release-1.12:
  https://github.com/JuliaLang/julia/blob/release-1.12/base/binaryplatforms.jl
- Sin soporte iOS/Android (política), issue cerrado:
  https://github.com/JuliaLang/julia/issues/28545
- Precedente de agregar ABI (Windows ucrt): https://github.com/JuliaLang/julia/issues/59027 ·
  https://github.com/JuliaLang/julia/pull/59029

## BinaryBuilder / BinaryBuilderBase
- Plataformas soportadas (sin Android): https://docs.binarybuilder.org/stable/building/
- `supported_platforms` / shards: https://github.com/JuliaPackaging/BinaryBuilderBase.jl/blob/master/src/Rootfs.jl
- Issue Termux/Android abierto (2020): https://github.com/JuliaPackaging/BinaryBuilder.jl/issues/846
- Guía de JLL y overrides: https://docs.binarybuilder.org/stable/jll/

## JLLWrappers / artefactos / overrides
- JLLWrappers (override dir, preferencias `<producto>_path`):
  https://github.com/JuliaPackaging/JLLWrappers.jl/blob/master/src/wrapper_generators.jl ·
  https://github.com/JuliaPackaging/JLLWrappers.jl/pull/27
- Pkg — Artifacts (`Overrides.toml` por depot, por hash o UUID+nombre):
  https://pkgdocs.julialang.org/v1/artifacts/
- `Artifacts.toml` de FFTW_jll (ejemplo real, sin entrada Android):
  https://github.com/JuliaBinaryWrappers/FFTW_jll.jl
- Org de artefactos: https://github.com/JuliaBinaryWrappers

## Yggdrasil / registry
- Recetas de build: https://github.com/JuliaPackaging/Yggdrasil
- Registro General: https://github.com/JuliaRegistries/General
- PkgServer: https://pkg.julialang.org

## Termux / Android
- `tur-on-device/julia` (patch bionic de BinaryPlatforms, sin JLLs):
  https://github.com/termux-user-repository/tur/tree/master/tur-on-device/julia
  - patch `0001-platform-and-triplet-detection.patch` (bionic en BinaryPlatforms)
  - patch `0005-loader-and-system-libraries.patch` (stubs `*_jll` con `dlopen` tolerante)
- `termux/glibc-packages` (`glibc-repo`, `glibc-runner`):
  https://github.com/termux/glibc-packages
- Predecesor: https://github.com/its-pointless/gcc_termux ·
  https://github.com/its-pointless/julia/tree/android-termux
- termux-packages #58 (libc differences): https://github.com/termux/termux-packages/issues/58
- Termux (repo principal): https://github.com/termux/termux-packages

## Discusiones
- Discourse #8086 (robsmith11, límite de JLLs en bionic):
  https://discourse.julialang.org/t/using-julia-on-android/8086
- Discourse #97289 (junix 2026-04-09, glibc-runner; fps 2025-11-21, nix-on-droid):
  https://discourse.julialang.org/t/how-to-set-up-julia-on-android-termux/97289

## Otros ecosistemas (patrón a imitar)
- Python — PEP 738 (wheels Android `android_<api>_<abi>`): https://peps.python.org/pep-0738/
- cibuildwheel Android (PR #2349): https://github.com/pypa/cibuildwheel/pull/2349 ·
  https://cibuildwheel.pypa.io/en/stable/platforms/
- Rust — platform support (triples `*-linux-android`):
  https://doc.rust-lang.org/nightly/rustc/platform-support.html
- Node — `process.platform` (Android experimental):
  https://github.com/nodejs/node/blob/main/doc/api/process.md

## Herramientas
- NDK de Android: https://developer.android.com/ndk
- `llvm-readelf` (ELF inspection): parte de LLVM/`llvm` de Termux.
- `gita` (monitoreo de CI del workspace): `gita notify <workflow>`.
