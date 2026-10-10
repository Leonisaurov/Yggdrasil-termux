# 01 — El problema: causa raíz medida

Todo lo de acá está medido en el dispositivo (Julia 1.12.6 bionic, Termux aarch64) o
citado del fuente. Los comandos están incluidos para poder reproducirlo.

## 1. Julia se identifica como `linux-glibc`

```
$ julia -e 'using Base.BinaryPlatforms; println(HostPlatform())'
Platform("aarch64", "linux"; julia_version = "1.12.6", libc = "glibc", cxxstring_abi = "cxx11")
```

Pero:

```
$ julia -e 'println(Sys.MACHINE)'
aarch64-unknown-linux-android24
```

**El `android24` se pierde y `libc` queda en `glibc`.** Cómo:

1. `HostPlatform() = parse(Platform, host_triplet())` (`base/binaryplatforms.jl`).
2. `host_triplet()` arranca de `Base.BUILD_TRIPLET` y agrega `libgfortran`/`cxx`/`libstdcxx`.
3. El constructor `Platform(arch, os; ...)` en `base/binaryplatforms.jl` hace:

```julia
# Auto-map call_abi and libc where necessary:
if os == "linux" && !haskey(tags, "libc")
    # Default to `glibc` on Linux
    tags["libc"] = "glibc"
end
```

Bionic no es `glibc` ni `musl`, así que **cae al default: glibc**.

4. No hay ninguna variable de entorno que lo cambie: en todo `base/*.jl` no hay
   `JULIA_*PLATFORM` ni lectura de `ENV` en `binaryplatforms.jl`.

## 2. La validación oficial ni siquiera admite bionic

`base/binaryplatforms.jl` (validación de tags):

```julia
if tags["os"] == "linux"
    # Linux always has a `libc` entry
    if tags["libc"] ∉ ("glibc", "musl")
        throw_libc_mismatch()
    end
else
    if haskey(tags, "libc")
        throw_libc_mismatch()
    end
end
```

Hay que notar el matiz: `Platform(..., validate_strict=false)` es el **default**, así que
construir `Platform("aarch64","linux"; libc="bionic")` *funciona* y da triplet
`aarch64-linux-bionic`; solo explota con `validate_strict=true`. O sea: **el tag se puede
inventar, pero no hay artefactos que lo matcheen** (ver §3).

## 3. El JLL no publica artefacto Android

`Artifacts.toml` de `FFTW_jll` (bajado por `Pkg.add("FFTW")`):

```toml
[[FFTW]]
arch = "aarch64"
os = "macos"
    url = ".../FFTW.v3.3.12.aarch64-apple-darwin.tar.gz"

[[FFTW]]
arch = "aarch64"
libc = "glibc"
os = "linux"
    url = ".../FFTW.v3.3.12.aarch64-linux-gnu.tar.gz"     # ← lo que Pkg elige

[[FFTW]]
arch = "aarch64"
libc = "musl"
os = "linux"
    url = ".../FFTW.v3.3.12.aarch64-linux-musl.tar.gz"

[[FFTW]]
arch = "aarch64"
os = "freebsd"
```

**No hay entrada `android`.** Como `libc` es `glibc`, Pkg elige `aarch64-linux-gnu`.

Y no es solo FFTW: la búsqueda en la organización `JuliaBinaryWrappers` por
`aarch64-linux-android` / `bionic` da **cero** resultados (ver
[`03-estado-del-arte.md`](03-estado-del-arte.md)).

## 4. Por qué ese `.so` glibc no puede cargar en bionic

Dos motivos, y el segundo es el que no se arregla con symlinks.

**(a) Sonames.** `llvm-readelf -d libfftw3.so.3.7.11`:

```
NEEDED  libm.so.6   libpthread.so.0   libc.so.6
```

Bionic no tiene esos nombres (usa `libm.so`, `libc.so`, `libdl.so` sin los `.6`/`.0`).

**(b) ABI y *symbol versions*.** `llvm-readelf --dyn-syms`:

```
malloc@GLIBC_2.17     fopen@GLIBC_2.17     __errno_location@GLIBC_2.17
abort@GLIBC_2.17      longjmp@GLIBC_2.17   ...
```

Bionic **no implementa el versionado de símbolos de glibc** y su libc es otra
implementación (`errno`, `FILE*`, hilos, arranque). Aunque crearás `libm.so.6 → libm.so`,
seguiría fallando.

## 5. Qué haría falta

Un artefacto `.so` **compilado contra bionic** (el NDK) y publicado para una plataforma que
Julia reconozca como la del host. Eso es exactamente lo que este repo propone construir con
Yggdrasil/BinaryBuilder (ver [`04-plan.md`](04-plan.md)).

## Reproducir todo

```sh
julia -e 'using Base.BinaryPlatforms; println(HostPlatform())'
julia -e 'println(Sys.MACHINE)'
julia -e 'using Pkg; Pkg.activate(mktempdir()); Pkg.add("FFTW"); using FFTW'
A=$(find ~/.julia/packages -maxdepth 2 -type d -name 'FFTW_jll' | head -1)
find "$A" -name Artifacts.toml -exec grep -E '^\[|arch =|os =|libc =' {} \;
D=$(find ~/.julia/artifacts -maxdepth 3 -name 'libfftw3.so.3*' | head -1)
llvm-readelf -d "$D" | grep NEEDED
llvm-readelf --dyn-syms "$D" | grep UND | head
```
