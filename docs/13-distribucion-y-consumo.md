# 13 — Cómo se distribuye y consume el resultado

Una vez que existe el artefacto bionic, **hay que hacer que Pkg lo use**. Hay dos familias de
caminos, y conviene saberlas desde el principio porque una de ellas **no requiere la Fase 1**
(patch de plataforma) y sirve para el piloto.

## 13.1 Camino "de verdad": JLL parcheado + registro propio

**Idea**: el `FFTW_jll` que instala el usuario tiene que traer la entrada `android` en su
`Artifacts.toml` (y, si hace falta, el wrapper). Como el del registro General no la trae,
se publica uno parcheado.

- **Fork** de `JuliaBinaryWrappers/FFTW_jll.jl` con el `Artifacts.toml` + wrapper del pin
  elegido, y el artefacto subido a sus Releases.
- **Publicarlo en un registro propio** (`LocalRegistry.jl`):
  ```julia
  using LocalRegistry
  create_registry("YggdrasilTermux", "https://github.com/<user>/YggdrasilTermux"; description="...")
  register("FFTW_jll"; registry="YggdrasilTermux", ...)
  ```
  El usuario hace `Pkg.Registry.add(...)` una vez y después `Pkg.add("FFTW")` normal.
- **Requiere**: Fase 1 (que `HostPlatform()` sea bionic) para que Pkg elija la entrada
  android. **Y tiene prioridad de registro**: hay que evitar que el General gane
  (ver documentación de `LocalRegistry`/`Pkg` sobre precedencia de registros).

**Pros**: es el flujo "correcto", el usuario no configura nada raro.
**Contras**: hay que mantener el fork + el registro + los artefactos; churn por versión.

## 13.2 Camino corto: `Overrides.toml` (dos variantes)

`~/.julia/artifacts/Overrides.toml` permite redirigir la ubicación de un artefacto **sin
tocar el JLL ni la plataforma**. Dos variantes:

**(a) Por hash del artefacto** (la más simple, **no requiere Fase 1**):
```toml
# el hash del artefacto aarch64-linux-gnu de FFTW_jll (el que Pkg elegiría hoy)
78f35e74ff113f02274ce60dab6e92b4546ef806 = "/data/data/com.termux/files/usr/ygg-artifacts/FFTW-bionic"
```
Pkg cree que bajó el de gnu, pero `artifact_path` devuelve tu directorio bionic. **Sirve
para validar toda la cadena hoy**, sin patch de plataforma, sin registro, sin fork.
**Contra**: el hash cambia con cada versión del JLL (hay que regenerar el override); y afecta
a **todas** las plataformas de ese depot (acá solo importa Android).

**(b) Por UUID + nombre de artefacto** (la "de verdad" pero sin registro):
```toml
[<UUID de FFTW_jll>]
FFTW = "/data/data/com.termux/files/usr/ygg-artifacts/FFTW-bionic"
```
Más estable que (a) (no depende del hash), pero requiere que el directorio tenga el layout
que el JLL espera (`lib/libfftw3.so`, …).

**Recomendado para el piloto: (b) hoy, (a) para no tocar el JLL.**  Medido 2026-10-11: con
el parche de `Pkg` de `julia-termux` la forma (b) **sí** evita la descarga, así que la tabla
JLL→directorio se escribe una vez y no se reescribe con cada versión del JLL.  El artefacto
de §14.1 se consume así (el directorio solo tiene que tener el layout que el JLL espera:
`lib/libfftw3.so`, …).  Para la distribución final: 13.1.

## 13.3 Distribución de los artefactos (hosting)

| Opción | Cuándo |
|---|---|
| **GitHub Releases de un fork de `JuliaBinaryWrappers/<pkg>_jll.jl`** | lo más parecido al flujo real; `Artifacts.toml` apunta ahí |
| **Host propio (S3/HTTP estático)** | si no se quiere depender de GitHub; mismo formato de URL+sha |
| **Solo local (`Overrides.toml`)** | piloto / uso personal |

**Medido (2026-10-11)**: el artefacto bionic de FFTW vive en un **release del propio repo del
port** (`fftw-bionic` en `Leonisaurov/julia-termux`) con su `.sha256`, y se consume con la
entrada UUID+nombre de §13.2 (b).  No hace falta un fork de `JuliaBinaryWrappers/<pkg>_jll.jl`
para el piloto: el `Artifacts.toml` parcheado y el registro propio quedan para cuando haya
más de un puñado de artefactos que mantener.

Como el usuario de Termux suele tener red, Releases es lo natural.

## 13.4 Licencias y procedencia (no opcional)

- Los artefactos son de **terceros** (FFTW es GPL, OpenSSL Apache, etc.). Al publicar un
  build para Android hay que:
  - respetar la licencia de cada lib y **conservar los `LICENSE`/`COPYING`** dentro del
    artefacto (BinaryBuilder ya lo hace con los productos declarados);
  - **declarar la procedencia** en el `Artifacts.toml`/notas (fuente + versión + target);
  - no mezclar licencias incompatibles en un mismo bundle.
- El **wrapper JLL** (`FFTW_jll`) tiene su propia licencia (MIT, típicamente).
- Dejar claro en la doc que el artefacto es **bionic/Android**, no el oficial.

## 13.5 ¿Qué ve el usuario final?

Dos escenarios:

1. **Con registro propio (13.1)**: `Pkg.add("FFTW")` normal, y el artefacto android se
   elige solo (si `HostPlatform()` es bionic).
2. **Con `Overrides.toml` (13.2)**: el usuario (o un instalador) escribe el override una
   vez; después `Pkg.add("FFTW")` usa el binario bionic.

En **ambos**, el JLL **sigue bajando "su" artefacto** (o el override evita la descarga): no
reutiliza la `.so` de Termux. Ver [`09-jll-hermetico-y-duplicacion.md`](09-jll-hermetico-y-duplicacion.md).

## 13.6 Relación con las alternativas

- Esto **no** es O2 (system-providers): O2 hace que el JLL use la lib **ya instalada en
  Termux**. Acá construimos un artefacto **propio** (bionic) y hacemos que Pkg lo use. Son
  complementarios: se puede usar el artefacto bionic **y** un override que apunte a Termux.

## 13.7 El fork y el registro, publicados (2026-10-11)

Para que un host que reporta `libc="bionic"` funcione sin escribir a mano ningún `Overrides.toml`
hacen falta tres piezas. Dos están hechas y verificadas; la tercera está diagnosticada y es una
sola función.

| Pieza | Estado |
| --- | --- |
| `HostPlatform()` reporta bionic | hecho (patch en `julia-termux`, construido, **sin publicar**) |
| `JLLWrappers` cae al wrapper `-gnu` en bionic | hecho, publicado y verificado |
| `Artifacts` encuentra la entrada del artefacto en bionic | **falta** (§13.9) |

**Repos**: `github.com/Leonisaurov/JLLWrappers.jl` (fork, versión **1.8.2**, `master`) y
`github.com/Leonisaurov/TermuxRegistry` (registro). El fork conserva el UUID de General, así que el
resolver ve una versión más alta y la prefiere: **nada más del entorno tiene que cambiar**.

```
Pkg.Registry.add(url = "https://github.com/Leonisaurov/TermuxRegistry")
```

### 13.7.1 Tres trampas, todas medidas

1. **`Pkg.Registry.add("<url>")` no agrega una URL.** En Pkg 1.12
   `add(reg::Union{String,RegistrySpec})` trata un String suelto como **nombre**
   (`RegistrySpec(name = …)`, `Pkg/src/Registry/Registry.jl:44-45`) y muere con *"no path or url
   specified for registry"*. Hay que usar `url=` o `RegistrySpec(url=…)`.
2. **La notación de rangos de un registro no es la del `Project.toml`.** Ahí un rango es un
   `VersionSpec` **literal**: `julia = "1.0.0"` significa *exactamente* 1.0.x y
   `Preferences = "1.2.1"` significa *exactamente* 1.2.1. Con la notación caret (la del
   `Project.toml`) el resolver contesta `restricted by julia compatibility requirement` y **cae en
   silencio a la versión de General**. La forma correcta es la que usa General: `julia = "1"` y
   `Preferences = "1.2.1 - 1"`.
3. **`Deps.toml` no es opcional.** Una entrada de registro sin `Deps.toml` resuelve el paquete
   **sin dependencias** (Pkg no consulta el `Project.toml` del árbol para esto): el JLLWrappers
   quedó sin `Preferences` y los 37 overrides cayeron en cascada con *"Package JLLWrappers does not
   have Preferences in its dependencies"*.

### 13.9 La pieza que falta: `Artifacts` y la plataforma

Con el host en bionic el fallo **cambia** y es el definitivo:

```
Cannot locate artifact 'FFTW' for aarch64-linux-android-cxx11-julia_version+1.12.6
```

`Artifacts.artifact_slash_lookup` (`stdlib/Artifacts/src/Artifacts.jl:657`) pide
`artifact_meta(name, dict, toml; platform)` y con bionic **ninguna entrada matchea** → `nothing` →
error.  El override uuid+name **no puede salvarlo**: `process_overrides` (línea 341) lo traduce a
overrides *por hash*, y para eso primero hay que haber encontrado una entrada y su hash.

El arreglo es la misma palanca que el fallback del wrapper, pero **fail-closed**: en
`artifact_meta`, si `select_platform(dl_dict, platform)` devuelve `nothing` y
`libc(platform) == "bionic"`, reintentar con la plataforma del mismo `arch`/`os` y `libc="glibc"`
**sólo si ese hash está en `Overrides.toml`**; si no lo está, devolver `nothing` y dejar el error
fuerte.  Así no hay forma de que un artefacto glibc se cuele: sin override declarado, el JLL no
carga y lo dice.

Es un patch de stdlib, así que va en el sysimage: cuesta **un rebuild** (~80 min en CI), el mismo
que ya se hizo para el patch de plataforma.
