# 10 — Glosario

- **JLL** (`*_jll`): paquete de Julia que envuelve una librería nativa. No compila: baja un
  **artefacto** y lo `dlopen`ea. Ej.: `FFTW_jll`, `OpenSSL_jll`.
- **Artefacto**: el binario precompilado (un `.tar.gz` con `.so`/`.a`/headers/ejecutables)
  que un JLL descarga a `~/.julia/artifacts/<hash>/`.
- **`Artifacts.toml`**: declara, por plataforma, `url` + `sha256` + `git-tree-sha1` del
  artefacto. Es lo que Pkg lee para elegir.
- **Yggdrasil**: repo de **recetas** de build (`build_tarballs.jl`), una por librería.
- **BinaryBuilder.jl**: ejecuta una receta en un entorno reproducible y produce el
  artefacto.
- **BinaryBuilderBase.jl**: define **plataformas soportadas** y **shards de compilador**
  (toolchains por target).
- **Shard**: paquete del toolchain (compilador + sysroot) que BinaryBuilderBase baja para
  compilar un target dado.
- **JLLWrappers.jl**: genera el código del `*_jll` (productos, rutas, `dlopen`).
- **JuliaBinaryWrappers**: organización de GitHub donde cada `*_jll.jl` publica sus
  artefactos como assets de release.
- **`Base.BinaryPlatforms`**: modelo de plataforma de Julia (`arch`, `os`, `libc`,
  `call_abi`, `cxxstring_abi`, …). `HostPlatform()` decide qué artefacto baja Pkg.
- **Tag / triple**: etiquetas de una plataforma (`aarch64`, `linux`, `glibc`, …) y su
  representación en string (`aarch64-linux-gnu`).
- **SONAME**: el nombre "canónico" de una `.so` (`libz.so.1`), con el que el loader
  resuelve dependencias.
- **`DT_NEEDED`**: la lista de SONAMEs que un binario necesita en runtime.
- **Symbol versioning**: versionado de símbolos de glibc (`malloc@GLIBC_2.17`). Bionic no
  lo implementa.
- **glibc / musl / bionic**: las tres libc. Android usa **bionic**. Termux es bionic.
- **NDK**: Android Native Development Kit (clang + sysroot bionic); el "toolchain" para
  compilar contra Android.
- **API level / `os_version`**: versión de Android objetivo (ej. `android24`, minSdk 24).
- **`cxxstring_abi`**: ABI de la std::string de C++ (`cxx11` en Termux/libc++).
- **PkgServer**: servidor (`pkg.julialang.org`) que sirve el registro y los tarballs de
  paquetes (los artefactos suelen venir de GitHub Releases).
- **Registro General**: el índice de paquetes de Julia (repo git `JuliaRegistries/General`).
- **`Overrides.toml`**: archivo por depot (`~/.julia/artifacts/Overrides.toml`) que redirige
  la ubicación de un artefacto (por hash o por UUID + nombre).
- **`<producto>_path`**: preferencia de JLLWrappers para apuntar un producto a una ruta
  concreta (ej. `libfftw3_path`).
- **JLL hermético**: un JLL usa la copia de su artefacto; **no** consulta el sistema.
- **`USE_SYSTEM_*`**: flags de build de Julia para linkear contra libs del sistema (es lo
  que hace el port `julia-termux` para sus propias dependencias).
