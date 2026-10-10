# 00 — Contexto: de dónde viene esto

## El port que motivó todo

`../Julia/julia-termux` es un port **nativo bionic** de Julia 1.12.6 para Termux/Android
aarch64. Está construido como un paquete de `termux-packages` en modo *on-device* sobre un
runner `ubuntu-24.04-arm`, con el LLVM bundled y las librerías del sistema tomadas de
Termux (`USE_SYSTEM_GMP/MPFR/OPENBLAS/LIBGIT2/CURL/... := 1`). Estado verificado
(2026-10-10):

- Release mutable **`julia-latest`** publicada con `.deb`, `.pkg.tar.xz`, bundle `.tar.gz`
  y `SHA256SUMS.txt`.
- `scripts/device-smoke.sh` en el teléfono: **19 pass / 0 fail** (`SMOKE: PASS`) sobre el
  bundle publicado.
- `Pkg.test` de un paquete **puro** (`Example`) pasa.

O sea: el lenguaje, las stdlibs, BLAS/LAPACK, LLVM, hilos, `Distributed`, `Pkg` y la red
(TLS) funcionan.

## El hueco

`Pkg.add` de un paquete con **dependencia binaria** (un JLL) falla. Caso medido:

```
$ julia -e 'using Pkg; Pkg.add("FFTW"); using FFTW'
ERROR: LoadError: InitError: could not load library
  "~/.julia/artifacts/d6f6a59.../lib/libfftw3.so"
dlopen failed: library "libm.so.6" not found: needed by
  ~/.julia/artifacts/d6f6a59.../lib/libfftw3.so.3.7.11 in namespace (default)
```

El artefacto que Pkg bajó es **glibc**, y bionic no puede ejecutarlo. La causa raíz
completa está en [`01-problema.md`](01-problema.md).

## Por qué es un problema de ecosistema y no de la receta

La receta de `julia-termux` puede resolver **sus propias** dependencias en build time con
`USE_SYSTEM_*` (y lo hace). Pero los paquetes que el usuario agrega después con `Pkg.add`
no pasan por esa receta: pasan por la maquinaria genérica de JLLs, que elige artefactos
según la plataforma que Julia cree que es. Ahí es donde no hay soporte Android.

## Qué mirar después de este doc

- La causa técnica: [`01-problema.md`](01-problema.md).
- Cómo encaja la cadena de herramientas: [`02-ecosistema.md`](02-ecosistema.md).
- Qué existe hoy: [`03-estado-del-arte.md`](03-estado-del-arte.md).
- Qué haríamos: [`04-plan.md`](04-plan.md).
