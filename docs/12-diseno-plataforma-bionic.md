# 12 — Diseño concreto de la plataforma bionic (spec)

Esto es **qué exactamente** hay que tocar y con qué valores, para poder hacerlo desde cero.
El **implementación de referencia** es el patch `0001` de TUR `tur-on-device/julia`
(Julia 1.10, el único port que ya lo hizo); acá se documenta y se generaliza.

## 12.1 Decisión: `libc="bionic"`, no `os="android"`

- **`libc="bionic"`** (lo de TUR): reusa toda la rama Linux de `BinaryPlatforms`; el cambio
  son 3 líneas en `binaryplatforms.jl` + 1 en `contrib/normalize_triplet.py`. El `os` queda
  `"linux"`, y `libc` distingue.
- **`os="android"`**: habría que tocar la validación de `os`, el parseo del triple, y
  varios `Makefile`/`Make.inc`; más invasivo y sin beneficio inmediato.
- **Recomendado**: `libc="bionic"`.

## 12.2 Los cambios exactos (patch de referencia, verificado)

Patch `0001-platform-and-triplet-detection.patch` de TUR:

```diff
--- a/contrib/normalize_triplet.py
+++ b/contrib/normalize_triplet.py
@@ -26,6 +26,7 @@ libc_mapping = {
     'gnu': "-gnu",
     'musl': "-musl",
+    'android': "-android[\\d\\.]*",
 }

--- a/base/binaryplatforms.jl
+++ b/base/binaryplatforms.jl
@@ -216,7 +216,7 @@ function validate_tags(tags::Dict)
     if tags["os"] == "linux"
         # Linux always has a `libc` entry
-        if tags["libc"] ∉ ("glibc", "musl")
+        if tags["libc"] ∉ ("glibc", "musl", "bionic")
             throw_libc_mismatch()
         end

@@ -570,6 +570,8 @@ function libc_str(p::AbstractPlatform)
     elseif lc === "glibc"
         return "-gnu"
+    elseif lc === "bionic"
+        return "-android"
     else
         return string("-", lc)

@@ -642,6 +644,7 @@ const libc_mapping = Dict(
     "glibc" => "-gnu",
     "musl" => "-musl",
+    "bionic" => "-(android|bionic)[\\d\\.]*",
 )
```

**Qué hace cada uno**:
| Cambio | Efecto |
|---|---|
| `libc_mapping["bionic"]` | parsear `aarch64-unknown-linux-android24` → `libc="bionic"` (el `24` lo come el regex) |
| `libc_str` → `-android` | el triple **canónico** de una plataforma bionic es `…-android` |
| `validate_tags` | `Platform(...; libc="bionic", validate_strict=true)` deja de lanzar |
| `normalize_triplet.py` | normalización de triplets en `contrib` |

## 12.3 Valores concretos

```julia
Platform("aarch64", "linux";
         libc = "bionic",
         cxxstring_abi = "cxx11")      # libc++ de Termux
# triplet-string canónico: "aarch64-linux-android"
```

- **`aarch64`**: el único arch a cubrir primero (`armv7l`/`x86_64` después).
- **`libc="bionic"`**.
- **`cxxstring_abi="cxx11"`** (Termux/libc++).
- **API level**: TUR **no** lo codifica (el regex lo descarta). Si se quiere distinguir
  (`android24` vs `android28`), usar el tag `os_version` de `BinaryPlatforms` — decisión
  abierta (`07-riesgos.md` §7.4.7).

## 12.4 Entrada en `Artifacts.toml`

Así tendría que verse la entrada del artefacto Android (ej. `FFTW_jll`):

```toml
[[FFTW]]
arch = "aarch64"
libc = "bionic"
os   = "linux"
    url  = "https://github.com/<host>/FFTW_jll.jl/releases/download/<tag>/FFTW.v3.3.12.aarch64-linux-android.tar.gz"
    sha256 = "<sha256 del tarball>"
    git-tree-sha1 = "<sha1 del árbol>"
```

Con `HostPlatform()` devolviendo `libc="bionic"`, la selección de artefacto lo elige.

## 12.5 Toolchain (NDK)

- **Target**: `aarch64-linux-android24` (API = la decisión de §12.3).
- **Sysroot**: el del NDK (bionic headers/libs).
- **C++**: `libc++_shared.so` del NDK — hay que decidir si el artefacto la **incluye** o si
  se linkea contra la de Termux.
- **CMake**: `CMAKE_SYSTEM_NAME=Android`, `CMAKE_ANDROID_NDK=<path>`,
  `ANDROID_ABI=arm64-v8a`, `ANDROID_PLATFORM=android-24`.
- **Autotools**: `--host=aarch64-linux-android`.

## 12.6 Qué **no** alcanza con el patch de TUR

1. El patch solo hace que la plataforma **exista y se pueda nombrar**. **No crea
   artefactos** — eso es Fase 2-4 del plan.
2. TUR, además, usa `USE_SYSTEM_*=1` y **no consume JLLs**; el patch le sirve para otra
   cosa (que las libs del sistema y los triplets cuadren). Para JLLs hace falta el
   artefacto.
3. El patch también trae `0005-loader-and-system-libraries.patch`, que:
   - agrega symlinks versionados a libs del sistema en `base/Makefile`
     (`symlink_system_library,CURL,libcurl,4`, `...LIBSUITESPARSE,libcamd,3`, …),
   - usa `ifneq (,$(findstring android,$(XC_HOST)))` para el camino Android.
   Es útil como **inventario de las libs que Julia pide por nombre versionado** (ver
   `01-problema.md`), pero es del **build de Julia**, no del JLL.

## 12.7 Cómo se verifica este diseño

```julia
using Base.BinaryPlatforms
p = Platform("aarch64", "linux"; libc="bionic", validate_strict=true)  # no debe lanzar
println(p)                       # aarch64-linux-android
println(libc(p))                 # bionic
println(HostPlatform())          # en el dispositivo: ... libc="bionic"
```

Rojo→verde: con el árbol sin el patch, `validate_strict=true` lanza
`ArgumentError: Invalid os/libc combination: linux/bionic` (control negativo).
