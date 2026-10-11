# 09 — Los JLL son herméticos: no reutilizan la `.so` del sistema

> Esta es la respuesta a una pregunta de diseño central: *"si hacemos Yggdrasil, ¿Julia
> detecta que ya tengo la `.so` instalada y no la instala?"*.
> **Respuesta: no. Baja y usa su propia copia.**

## Por qué: el código lo dice

El wrapper que `JLLWrappers` genera para cada producto (ejemplo real de `FFTW_jll`, en
`src/wrappers/aarch64-linux-gnu.jl`):

```julia
@declare_library_product(libfftw3, "libfftw3.so.3")
@init_library_product(libfftw3, "lib/libfftw3.so", ...)
```

y el macro, en `JLLWrappers/src/products/library_generators.jl`, resuelve así:

```julia
path_name = <producto>_path     # preferencia, si el usuario la fijó
if path_name === nothing
    path_name = joinpath(artifact_dir, "lib/libfftw3.so")   # ← SU copia del artefacto
end
dlopen(path_name)
```

`artifact_dir` es el directorio que **Pkg bajó** a `~/.julia/artifacts/<hash>/`. **No hay
ningún paso que pregunte si `$PREFIX/lib/libfftw3.so` existe.** El JLL es una unidad
autocontenida ("hermética"): lo que trae es lo que usa.

## Consecuencias

1. **Con Yggdrasil (artefacto bionic) el binario queda duplicado**:
   `$PREFIX/lib/libfftw3.so` (Termux) **y** `~/.julia/artifacts/<hash>/lib/libfftw3.so`
   (JLL). Es el comportamiento normal de Julia en todas las plataformas.
2. **No hay deduplicación** ni detección del sistema. No es un bug: es el diseño.
3. **Riesgo de doble carga**: si en el mismo proceso se cargan la copia del sistema y la
   del JLL, hay dos copias de estado global (p. ej. el estado interno de FFTW). Normalmente
   no pasa porque cada consumidor usa la suya, pero hay que declararlo.

## Qué **sí** haría que use la del sistema (y es ortogonal a Yggdrasil)

| Mecanismo | Alcance | Requiere |
|---|---|---|
| `Overrides.toml` (por UUID + nombre de artefacto → path) | global, por JLL | ninguna cooperación del JLL |
| Preferencia `<producto>_path` (JLLWrappers) | por JLL/producto | que el JLL use JLLWrappers y no sea stdlib |
| Directorio `override/` en un JLL `dev`eado | por JLL | `Pkg.develop` + poblar el dir |
| `USE_SYSTEM_*` | **build** de Julia/paquete | estar compilando, no consumiendo un JLL |

Ejemplo con `Overrides.toml` (`~/.julia/artifacts/Overrides.toml`):

```toml
# por UUID + nombre de artefacto (el JLL busca lib/libfftw3.so bajo este path)
[<UUID de FFTW_jll>]
FFTW = "/data/data/com.termux/files/usr"

# o por producto
[FFTW_jll]
libfftw3_path = "/data/data/com.termux/files/usr/lib/libfftw3.so.3"
```

Y **se puede combinar**: artefacto bionic de Yggdrasil + `Overrides.toml` para que ese
artefacto sea, en realidad, las libs de Termux. Pero son dos decisiones separadas:

| Querés… | Yggdrasil | `Overrides.toml` |
|---|---|---|
| que **cargue** (compatibilidad bionic) | ✅ | — |
| que **no duplique** (use la del sistema) | — | ✅ |
| ambas | ✅ | ✅ |

## Decisión por defecto de este repo

- **Yggdrasil construye artefactos bionic** → objetivo principal (el JLL **carga**).
- **La duplicación se acepta**; si molesta, `Overrides.toml` la elimina lib por lib.
- **La duplicación NO es el problema a resolver**: el problema es que hoy **nada carga**.

---

## 9.7 Medido en el dispositivo: el override evita la descarga, y dónde está el límite (2026-10-11)

Caso `FFTW_jll` (uuid `f5851436-0d7a-5f13-b9de-f02708fd171a`, artefacto `FFTW`, hash
`d6f6a596f02a9c173bc5d1c26b680ba8d2183839`), apartando el artefacto del depot con `mv`
(reversible) y observando si volvía a bajarse.

| Forma del override en `~/.julia/artifacts/Overrides.toml` | ¿Evita la descarga? | Por qué |
|---|---|---|
| `[<uuid>]` + `FFTW = "/data/…/usr"` | **NO** | `load_overrides` lo dice: *"all redirects mechanistically happen through the hash overrides"*.  La forma UUID+nombre se intercepta al cargar el `Artifacts.toml` (`process_overrides`, `Artifacts.jl:341`) y **recién ahí** genera la entrada de hash.  En el camino de descarga de Pkg, `select_downloadable_artifacts` y `ensure_artifact_installed` se llaman **sin `pkg_uuid`** (`Pkg/src/Artifacts.jl:576/578`) → `process_overrides` nunca corre → no hay entrada de hash → **baja igual** (`Installing 1 artifacts` / `Installed artifact FFTW 1.2 MiB`) |
| `"d6f6a596…" = "/data/…/usr"` | **SÍ** | `query_override(hash)` la lee del archivo dentro de `artifact_paths`, y `ensure_artifact_installed` hace `if !artifact_exists(hash)` con `artifact_exists(hash; honor_overrides=true)` (`Artifacts.jl:270`) → **no baja nada** (depot vacío) |

Consecuencia de diseño: la forma **estable** (UUID+nombre, que no cambia con la versión
del JLL) es justamente la que **no** evita la descarga, y la que funciona (hash) cambia
con cada versión.  Hacer que la estable sirva es un parche chico del lado de
`Pkg`/`Artifacts` (pasar `pkg_uuid`, o consultar los overrides UUID+nombre antes de
bajar) — **de julia-termux, no de Yggdrasil**.

### El límite no es bionic: es la superficie de productos

Con el override por hash, `FFTW_jll.libfftw3_path` pasó a
`/data/data/com.termux/files/usr/lib/libfftw3.so` (la bionic de Termux) y el JLL la
cargó.  Es decir, **el override no solo ahorra espacio: es lo que hace usable un JLL en
bionic**, porque el `.so` glibc del artefacto nunca se carga — que es exactamente cómo
se esquiva `libm.so.6` / `@GLIBC_2.17`.

Lo que el override **no** puede arreglar apareció enseguida:

```
ERROR: could not load symbol "fftw_init_threads": undefined symbol: fftw_init_threads
```

El artefacto del JLL trae **solo** `libfftw3.so*` y `libfftw3f.so*`, y su `libfftw3`
**exporta** `fftw_init_threads` (la receta de BinaryBuilder fusiona el API de threads);
Termux usa el layout de upstream: `libfftw3.so` **sin** ese símbolo y el símbolo en
`libfftw3_threads.so`.

**Regla**: el override sirve si y solo si el paquete del sistema expone **los mismos
productos, en las mismas rutas, con la misma superficie de símbolos** que el JLL declara.
Si no, no hay override que valga: eso lo tiene que producir Yggdrasil (un JLL bionic con
el layout del JLL oficial) o un shim chico.

### La pregunta que decide, por librería

El clasificador que la responde, con la primera tabla medida y su validación, está en [`14-clasificacion-jll.md`](14-clasificacion-jll.md) (`tools/classify-jll.jl`).

1. ¿Termux ya shipa la librería? (`pacman -Q <pkg>`) — si no, es caso Yggdrasil.
2. ¿El paquete del sistema expone los productos y símbolos que el JLL declara? — override, cero descarga y cero build.
3. Si no — Yggdrasil con el layout del JLL oficial, o un shim bionic.
