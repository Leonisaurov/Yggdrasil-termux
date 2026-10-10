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
