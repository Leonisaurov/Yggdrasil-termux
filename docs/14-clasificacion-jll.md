# 14 — Clasificación de JLLs: override, symlink o Yggdrasil (2026-10-11)

`tools/classify-jll.jl` responde, por JLL, la pregunta que decide si Yggdrasil tiene que
construir algo: **¿la librería que Termux ya shipa satisface lo que el JLL declara?**  Un
`Overrides.toml` que apunte el artefacto a `$PREFIX` solo es sano si el paquete del
sistema expone *los mismos productos, en las mismas rutas, con la misma superficie de
símbolos*.

## Cómo mide

1. instala el JLL en un entorno temporal y **no lo carga** (`using Foo_jll` corre el
   `__init__` generado, que hace `dlopen` del artefacto: en esta plataforma eso es el
   `.so` glibc que no carga, así que el módulo revienta antes de poder preguntarle nada —
   medido: `InitError`, `libm.so.6`);
2. resuelve el artefacto que Pkg elegiría para este host (la misma llamada que hace Pkg)
   y lo baja si falta — ese peso **es** la duplicación que hoy cuesta cada JLL;
3. lee los productos del wrapper de la plataforma y, por cada uno, compara contra
   `$PREFIX`: ¿existe el archivo?, ¿resuelve el SONAME al lado?, ¿qué símbolos definidos
   tiene el build oficial que el del sistema no? (sin contabilidad del linker ni nodos de
   versión);
4. imprime un veredicto y, cuando pasa, la línea de `Overrides.toml` que corta la
   descarga.  La línea va **por hash** a propósito: la forma UUID+nombre es estable pero
   **no** evita la descarga (ver §9.7).

## La primera tabla (medida en el teléfono)

| JLL | veredicto | evidencia |
|---|---|---|
| `FFTW_jll` | **needs-jll** | 235 símbolos de API faltantes: `fftwf_cleanup_threads`, `fftwf_codelet_*_neon`, … — el artefacto oficial fusiona el API de threads en `libfftw3` y Termux usa el layout de upstream; además faltan los codelets NEON |
| `libpng_jll` | **override-needs-alias** | 240/240 símbolos coinciden; solo falta el *nombre* `libpng16.so.16` (Termux shipa `libpng16.so`) |
| `Zlib_jll` | **system-stub** | stub de stdlib: `dlopen("libz.so.1")`, lo responde `$PREFIX/lib` |
| `OpenSSL_jll` | **system-stub** | `libcrypto.so.3`, `libssl.so.3` en `$PREFIX/lib` |
| `LibCURL_jll` | **system-stub** | `libcurl.so.4` ← alias creado por la receta |
| `LibGit2_jll` | **system-stub** | `libgit2.so.1.9` ← alias de la receta |
| `MPFR_jll` | **system-stub** | `libmpfr.so.6` ← alias de la receta |
| `GMP_jll` | **system-stub** | `libgmp.so.10`, `libgmpxx.so.4` ← alias de la receta |

## El hallazgo que ordena todo

**Los stdlib JLLs de un Julia construido de fuentes ya son stubs** (upstream, no del
port): `## dummy stub for …`, `dlopen` por soname, `artifact_dir = dirname(Sys.BINDIR)`.
Medido: `GMP_jll.libgmp_path = $PREFIX/lib/libgmp.so`,
`Zlib_jll.libz_path = $PREFIX/lib/libz.so.1.3.2`, y el depot **no tiene** ningún artefacto
de stdlib.  O sea: la política "no bajes, usá la del sistema" ya está en Julia para los
stdlibs, y los nombres que Termux no shipa los crea el mecanismo de aliases de la receta
(`needed-library-aliases.sh`).  Lo que falta es **generalizarla a los JLLs de la
registry**, que sí son wrappers de BinaryBuilder con rutas de artefacto.

## Validación del veredicto (no alcanza con que suene bien)

`libpng_jll` predijo "alcanza un symlink" ⇒ se probó:

```
ln -sfn libpng16.so $PREFIX/lib/libpng16.so.16
"b56293e57ba0…" = "/data/data/com.termux/files/usr"      # Overrides.toml, por hash
# con el artefacto apartado del depot:
libpng_jll.libpng_path = /data/data/com.termux/files/usr/lib/libpng16.so
ccall png_access_version_number = 10659
```

Una JLL **funcionando en bionic sin compilar nada**, y el artefacto no volvió a bajarse.

## La regla, y el reparto

1. ¿Termux shipa la librería?  Si no → **Yggdrasil**.
2. ¿El sistema expone los productos/símbolos que el JLL declara? → **override** (cero descarga, cero build); si solo falta el nombre → **override + symlink**.
3. Si el build del sistema exporta menos API (otra feature set) → **Yggdrasil o un shim**; `FFTW_jll` es el caso medido.
