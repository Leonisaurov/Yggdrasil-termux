# 02 — El ecosistema de binarios de Julia, pieza por pieza

Cómo encaja todo, de la receta al `.so` cargado. Es la cadena que hay que "androidizar".

```
 receta            compila           hostea                índice              descarga
─────────        ──────────        ────────────          ──────────          ──────────
 Yggdrasil   →   BinaryBuilder  →  JuliaBinaryWrappers  →  General registry →  Pkg/Artifacts
 build_tarballs   BinaryBuilderBase  (GitHub Releases)     (JuliaRegistries)   (por hash)
 .jl              JLLWrappers        <pkg>_jll.jl                              ↓
                                                          PkgServer        ~/.julia/artifacts/
                                                       (pkg.julialang.org)   <hash>/lib/libX.so
```

## Piezas

### Yggdrasil (`github.com/JuliaPackaging/Yggdrasil`)
Repositorio de **recetas de build**, una por librería: `F/FFTW/build_tarballs.jl`. Es el
análogo a `packages/<pkg>/build.sh` de `termux-packages`. Cada receta declara:
- el código fuente y su hash,
- las dependencias entre librerías,
- los **productos** (`libfftw3.so`, headers, ejecutables),
- las **plataformas** a construir (`platforms = supported_platforms(...)`).

> Nota: **es un repo de recetas, no un servidor de paquetes.** El "servidor" es PkgServer.

### BinaryBuilder.jl / BinaryBuilderBase.jl
- **BinaryBuilder.jl**: la herramienta que ejecuta una receta dentro de un entorno
  reproducible (un Docker con el compilador cruzado de esa plataforma) y produce el
  artefacto.
- **BinaryBuilderBase.jl**: define las **plataformas soportadas** y los **shards de
  compilador** (GCC/LLVM bootstrap por target). Es donde vive la lista de targets y de
  donde salen los "shards" que se descargan para compilar.

### JLLWrappers.jl
Genera el código del paquete `*_jll` a partir de los productos. El wrapper:
- declara cada producto (`@declare_library_product libfftw3 "libfftw3.so.3"`),
- resuelve la ruta (`@init_library_product libfftw3 "lib/libfftw3.so" …`): usa la
  preferencia `<producto>_path` si existe, si no `joinpath(artifact_dir, "lib/libfftw3.so")`,
- hace `dlopen` y expone el handle.

### JuliaBinaryWrappers (`github.com/JuliaBinaryWrappers/<pkg>_jll.jl`)
Cada JLL tiene su repo; los **artefactos viven como assets de sus GitHub Releases** (y el
`Artifacts.toml` apunta ahí con URL + hash). Ahí es donde hoy **no hay nada Android**.

### Artifacts.toml
Declara, por plataforma, el artefacto: `url`, `sha256`, `git-tree-sha1`. Es lo que Pkg lee
para elegir y bajar.

### Pkg + Base.Artifacts
- `Base.BinaryPlatforms.HostPlatform()` decide la plataforma efectiva.
- `Pkg` selecciona el artefacto que matchea y lo baja a `~/.julia/artifacts/<hash>/`.
- Mecanismos de override: `~/.julia/artifacts/Overrides.toml` (por hash o por UUID+nombre
  de artefacto) y la preferencia `<producto>_path`. Ver
  [`09-jll-hermetico-y-duplicacion.md`](09-jll-hermetico-y-duplicacion.md).

### Base.BinaryPlatforms
Modela `arch`, `os`, `os_version`, `libc`, `call_abi`, `libgfortran_version`,
`libstdcxx_version`, `cxxstring_abi`, `julia_version`. **No conoce Android** y en Linux solo
admite `libc ∈ {glibc, musl}`. Es el punto exacto donde habría que intervenir.

### Registro General + PkgServer
- **General registry** (`JuliaRegistries/General`): el **índice** (repo git) donde se
  publica el paquete `*_jll`.
- **PkgServer** (`pkg.julialang.org`): sirve el registro y los tarballs de paquetes. Los
  **artefactos** suelen venir de GitHub Releases, no del PkgServer.

## Consecuencia para este proyecto

Para que un JLL tenga Android hacen falta **cuatro** cambios coordinados:

1. `Base.BinaryPlatforms`: que exista/acepte la plataforma Android (bionic).
2. `BinaryBuilderBase`: shards de compilador para `aarch64-linux-android` (NDK).
3. `BinaryBuilder`: soportar el target en `supported_platforms`/Rootfs.
4. `Yggdrasil`: recetas que pidan esa plataforma **y** un host donde publicar los
   artefactos (`JuliaBinaryWrappers` fork o servidor propio), con su `Artifacts.toml`.

Ver el plan en [`04-plan.md`](04-plan.md).
