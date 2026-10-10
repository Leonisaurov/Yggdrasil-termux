# 06 — Verificación y criterios de aceptación

Regla del proyecto: **"compila" o "el test pasa" no es evidencia.** Un artefacto JLL se
acepta cuando **carga y hace algo real** en el dispositivo, y se compara contra el mismo
símbolo provisto por Termux.

## 6.1 El rojo (baseline)

Antes de cada fase, el estado actual debe fallar de forma **reproducible y documentada**:

```
$ julia -e 'using Pkg; Pkg.activate(mktempdir()); Pkg.add("FFTW"); using FFTW'
ERROR: ... dlopen failed: library "libm.so.6" not found ...
```

Guardar el log completo (comando + salida) en `PROGRESS.md` con fecha y run/commit.

## 6.2 El verde (por fase)

| Fase | Criterio de aceptación |
|---|---|
| 0 | El rojo se reproduce desde cero con un comando documentado. |
| 1 | En el dispositivo: `HostPlatform()` reporta bionic, y un JLL de prueba con artefacto bionic es **elegido** por Pkg (antes elegía gnu). |
| 2 | Desde un runner, BinaryBuilderBase obtiene el toolchain y compila un `.so` que `dlopen`ea en el dispositivo. |
| 3 | `build_tarballs.jl` con plataforma bionic produce un `.tar.gz`; el `.so` tiene `NEEDED libc.so` (sin `libm.so.6` ni `@GLIBC_*`). |
| 4 | `Pkg.add("FFTW")` → `using FFTW` → un cómputo FFT **real** da el resultado correcto en el dispositivo. |
| 5 | Tabla por lib: carga / no carga / no está. Sin promesas. |
| 6 | PR upstream aceptado (o, mínimo, soporte de plataforma). |

## 6.3 Cómo se prueba (en el dispositivo)

1. **Carga**: `using <Pkg>` y `dlopen` del producto.
2. **Funcional**: una operación con resultado verificable (no "no tiró error").
   Ej. FFTW: `ifft(fft(x)) ≈ x`.
3. **Identidad del binario**: confirmar **cuál** `.so` se cargó, con
   `dlpath(handle)` / `llvm-readelf -d`:
   - el artefacto bionic debe tener `NEEDED libc.so` (no `libm.so.6`);
   - no debe aparecer `@GLIBC_*` en sus símbolos.
4. **Comparación con Termux**: mismo cómputo usando la lib de `$PREFIX/lib` (vía
   `Overrides.toml` o `dlopen` directo) para descartar que "funciona por casualidad".
5. **Limpieza**: `JULIA_DEPOT_PATH` en `$PREFIX/tmp` con `trap 'rm -rf' EXIT`; dejar el
   dispositivo limpio.

## 6.4 Herramientas

- `julia-termux/scripts/device-smoke.sh` para el estado general del runtime.
- Un script nuevo (en la implementación) `scripts/verify-jll-android.sh` que haga 1-4 y
  devuelva `PASS`/`FAIL` por lib.
- Para builds: **CI arm64**, nunca el teléfono. Monitoreo con `gita notify`.

## 6.5 Anti-metas

- ❌ "El build salió verde, entonces el JLL sirve."
- ❌ "Carga, entonces funciona." (Puede cargar y devolver mal.)
- ❌ Declarar cobertura sin la tabla medida.

## 6.6 No-regresión

Cada fase debe incluir un test que **falle sin el cambio**. Ejemplos:
- Fase 1: un test que exija `libc="bionic"` en `validate_strict=true` (hoy lanza
  `ArgumentError`).
- Fase 3: un test que verifique que el `.so` no tiene `NEEDED libm.so.6`.
- Fase 4: el cómputo FFT contra un valor esperado.

Un check que siempre pasa es peaje decorativo.
