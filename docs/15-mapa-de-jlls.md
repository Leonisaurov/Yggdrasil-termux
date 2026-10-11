# 15 — Mapa medido: qué JLLs resuelve Termux y qué queda para Yggdrasil (2026-10-11)

`docs/14` dejó la regla; esto es la medición a escala.  La pregunta que decide el tamaño del
proyecto era *cuántos JLLs necesitan de verdad un artefacto propio*, y la respuesta medida es
**siete de cuarenta y tres**, con **cinco bloqueadores raíz** detrás de casi todos ellos.

## Cómo se midió

```
mkdir -p "$TMPDIR/ygg-depot" && cp -a ~/.julia/registries "$TMPDIR/ygg-depot/"
JULIA_DEPOT_PATH="$TMPDIR/ygg-depot" JULIA_PKG_PRECOMPILE_AUTO=0 \
    julia tools/classify-jll.jl --sweep tools/jlls-closure.txt --md
```

Contra un **depot de scratch**, no el real, por dos razones: la comparación tiene que ser
contra el artefacto *oficial* (un `Overrides.toml` en el depot real redirige el JLL a un build
local, y entonces lo que responde la pregunta es la respuesta), y los artefactos que baja para
medir *son* la duplicación de la que trata el proyecto.

El universo son los JLLs cuyo producto ya está en `$PREFIX` (medido: 1877 `.so` en el
dispositivo) **más su clausura de dependencias** — 43 JLLs.  La clausura no es opcional: ver
§15.4.

## Las tres palancas, de más barata a más cara

| veredicto | qué significa | palanca |
|---|---|---|
| `system-stub` / `needs-alias` | JLL de stdlib: upstream ya lo resuelve por soname | ninguna (8 JLLs) |
| `override` / `override-needs-alias` | el sistema satisface todos los productos y símbolos | una línea de `Overrides.toml` (+ un symlink) |
| `needs-jll (absent exe)` | la librería está, falta un **programa** o un `.a` que el JLL declara | ver si otro paquete de Termux lo trae |
| `needs-jll (absent lib)` | el producto no está en la raíz | `pkg install`, o artefacto |
| `needs-jll (gap)` | el build del sistema exporta menos API | artefacto (o shim) |

## 15.1 El mapa

| `GettextRuntime_jll` | needs-jll (gap) | envsubst, gettext, libasprintf, libintl, ngettext | 3.8 MB | 10 symbols |
| `Giflib_jll` | override | libgif | 0.5 MB | — |
| `Graphite2_jll` | override-needs-alias | libgraphite2 | 0.4 MB | names: libgraphite2 |
| `LERC_jll` | needs-jll (absent lib) | libLerc | 0.7 MB | products absent: libLerc (lib) |
| `Libffi_jll` | needs-jll (gap) | libffi | 0.2 MB | 2 symbols |
| `Libglvnd_jll` | needs-jll (gap) | libEGL, libGL, libGLESv1_CM, libGLESv2, libGLX, libGLdisp… | 7.2 MB | 1 symbols |
| `Libiconv_jll` | override-needs-alias | libcharset, libiconv | 5.3 MB | names: libcharset, libiconv |
| `Libmount_jll` | override-needs-alias | libmount | 23.1 MB | names: libmount |
| `Libuuid_jll` | override-needs-alias | libuuid | 12.3 MB | names: libuuid |
| `Xorg_libX11_jll` | override-needs-alias | libX11, libX11_xcb | 25.8 MB | names: libX11_xcb |
| `Xorg_libXau_jll` | override-needs-alias | libXau | 0.2 MB | names: libXau |
| `Xorg_libXdmcp_jll` | override-needs-alias | libXdmcp | 0.4 MB | names: libXdmcp |
| `Xorg_libXext_jll` | override-needs-alias | libXext | 1.2 MB | names: libXext |
| `Xorg_libXrender_jll` | override-needs-alias | libXrender | 1.7 MB | names: libXrender |
| `Xorg_libxcb_jll` | override-needs-alias | libxcb, libxcb_composite, libxcb_damage, libxcb_dpms, lib… | 21.4 MB | names: libxcb_shm, libxcb_dri3, libxcb_screensaver, libxcb_xv, libxcb_dri2, libxcb_randr, libxcb_composite, libxcb_xfixes, libxcb_shape, libxcb_xinput, libxcb_res, libxcb_xf86dri, libxcb_sync, libxcb_xvmc, libxcb_xtest, libxcb, libxcb_xkb, libxcb_glx, libxcb_dpms, libxcb_xinerama, libxcb_record, libxcb_present, libxcb_damage, libxcb_render |
| `Xorg_xtrans_jll` | no-products |  | 0.0 MB | — |
| `FFTW_jll` | needs-jll (gap) | libfftw3, libfftw3f | 2.7 MB | 470 symbols |
| `libpng_jll` | override | libpng | 1.2 MB | — |
| `Cairo_jll` | override | libcairo, libcairo_gobject, libcairo_script_interpreter | 6.4 MB | — |
| `Pixman_jll` | override-needs-alias | libpixman | 0.9 MB | names: libpixman |
| `Fontconfig_jll` | needs-jll (gap) | fc_cache, fc_cat, fc_conflist, fc_list, fc_match, fc_patt… | 3.0 MB | 1 symbols |
| `FreeType2_jll` | override-needs-alias | libfreetype | 5.0 MB | names: libfreetype |
| `HarfBuzz_jll` | override-needs-alias | libharfbuzz, libharfbuzz_gobject, libharfbuzz_subset | 5.0 MB | names: libharfbuzz, libharfbuzz_subset, libharfbuzz_gobject |
| `Glib_jll` | override | libgio, libgirepository, libglib, libgmodule, libgobject,… | 29.6 MB | — |
| `JpegTurbo_jll` | needs-jll (absent exe) | cjpeg, djpeg, jpegtran, libjpeg, libturbojpeg | 5.1 MB | products absent: cjpeg (exe), djpeg (exe), jpegtran (exe) |
| `Libtiff_jll` | override-needs-alias | libtiff | 10.3 MB | names: libtiff |
| `libwebp_jll` | override-needs-alias | cwebp, dwebp, gif2webp, img2webp, libwebp, libwebpdecoder… | 7.1 MB | names: libwebpdecoder, libwebpdemux, libwebpmux, libwebp |
| `XML2_jll` | needs-jll (gap) | libxml2, xmlcatalog, xmllint | 9.4 MB | 236 symbols |
| `Expat_jll` | needs-jll (absent exe) | libexpat, xmlwf | 1.1 MB | products absent: xmlwf (exe) |
| `Zstd_jll` | override | libzstd, zstd, zstdmt | 1.6 MB | — |
| `Bzip2_jll` | override | libbzip2 | 1.9 MB | — |
| `XZ_jll` | needs-jll (absent exe) | liblzma, liblzma_a, lzmadec, lzmainfo, xz, xzdec | 6.5 MB | products absent: liblzma_a (file) |
| `SQLite_jll` | override | libsqlite, sqlite3 | 3.5 MB | — |
| `PCRE2_jll` | system-stub | libpcre2_8 | 0.0 MB | — |
| `OpenSSL_jll` | system-stub | libcrypto, libssl | 0.0 MB | — |
| `LibCURL_jll` | system-stub | libcurl | 0.0 MB | — |
| `LibGit2_jll` | system-stub | libgit2 | 0.0 MB | — |
| `libsodium_jll` | override-needs-alias | libsodium | 4.3 MB | names: libsodium |
| `Arpack_jll` | needs-jll (gap) | libarpack | 0.4 MB | 2 symbols |
| `GMP_jll` | system-stub | libgmp, libgmpxx | 0.0 MB | — |
| `MPFR_jll` | system-stub | libmpfr | 0.0 MB | — |
| `Zlib_jll` | system-stub | libz | 0.0 MB | — |
| `OpenBLAS_jll` | needs-alias | libopenblas, openblas_soname | 0.0 MB | — |

**Duplicación medida**: los artefactos oficiales de estos 43 JLLs ocupan **209,3 MB** en el
depot, y ninguno carga (son glibc).  Ese es el costo de hoy, por stack.

## 15.2 Lo que el barrido le corrigió al clasificador

La primera corrida marcó **diez** librerías como `needs-jll` que no lo eran.  Las dos clases de
falso positivo, las dos medidas:

- **Bookkeeping del linker**: los artefactos oficiales exportan `__bss_end__`, `__bss_start__`,
  `__end__`, `_bss_end__` (tipo `B` medido con `nm`) y los builds de Termux no.  Cuatro
  símbolos fantasma convertían Bzip2, Zstd, SQLite, libsodium, XML2, Cairo, Pixman, HarfBuzz,
  Glib y Fontconfig en falsos `needs-jll`.  `_init`/`_fini` (`T`) fueron la segunda tanda.
- **Nodos de versión y símbolos débiles**: `XZ_5.1.2alpha` es tipo `A` (absoluto) y un
  `_ZSt4swap…` de HarfBuzz es débil (`W`): ninguno puede ser API faltante.  El filtro por
  **tipo** (`A`/`W`/`V`/`w`/`v`) es correcto por definición; el de nombres es empírico.

Y una tercera, de diseño: un producto ausente puede ser una **librería** o un **ejecutable**, y
no son la misma decisión.  La primera versión los mezclaba y mandaba JpegTurbo, Expat y XZ a
Yggdrasil por `cjpeg`, `xmlwf` y `liblzma.a` — con la librería compartida perfectamente
satisfecha.

## 15.3 Un override vale lo que vale su clausura

`Cairo_jll`, `HarfBuzz_jll`, `Glib_jll`, `Libtiff_jll`, `libwebp_jll` y `XML2_jll` pasaron la
comparación de símbolos y después **no cargaron**: `using Cairo_jll` falla con *"The following 2
direct dependencies failed to precompile"* porque `Fontconfig_jll` y `Glib_jll` seguían
apuntando a su artefacto glibc, y JLLWrappers' `__init__` corre el de cada dependencia.

Validación con `tools/validate-overrides.jl` (carga el JLL de verdad y exige que **cada**
`<producto>_path` resuelva fuera de `<depot>/artifacts`, o sea que no haya bajado nada):

```
validated: 19 / 24        # FFTW + los 23 ganadores del barrido
artifact directories after: 22 (0 new)
```

Y con **consumidores reales**, no sólo con el JLL: `using FFTW` (su artefacto bionic) y
`using SQLite` — este último con el override del sistema, `INSERT` con parámetros y `SELECT`
de vuelta:

```
SELECT a = [42, 43]   ok = true
libsqlite = /data/data/com.termux/files/usr/lib/libsqlite3.so
depot: 22 entradas (sin cambios: no bajó nada)
```

Los cinco que no cargan tienen **cinco bloqueadores raíz**:

| bloqueador | veredicto | bloquea |
|---|---|---|
| `Fontconfig_jll` | gap de **1** símbolo de datos (`default_langs`) | Cairo, HarfBuzz |
| `Libffi_jll` | gap de **2** (`ffi_call_go`, `ffi_prep_go_closure`) | Glib, y por él Cairo, HarfBuzz |
| `JpegTurbo_jll` | faltan **3 programas** (`cjpeg`, `djpeg`, `jpegtran`) | Libtiff, libwebp |
| `XZ_jll` | falta **`liblzma.a`** (la compartida está) | Libtiff, libwebp |
| `LERC_jll` | producto **ausente** (`libLerc`) | Libtiff |

Es decir: de los 43, **19 se resuelven hoy con overrides validados**, 8 son stubs de stdlib, y
el resto espera a esos cinco.  Dos de ellos (Fontconfig, Libffi) son diferencias de 1-2 símbolos
—candidatos a pedirle a Termux un build que los exporte—, dos son *programas* que quizá otro
paquete de Termux traiga, y uno es un paquete que no existe (`LERC`).

## 15.4 Los que sí son trabajo de Yggdrasil

Siete con gap real medido: `FFTW_jll` (470 símbolos — **ya resuelto** con el artefacto bionic,
docs/14 §14.1), `XML2_jll` (236 en la versión de JLL que resolvió hoy), `GettextRuntime_jll`
(10), `Libffi_jll` (2), `Libglvnd_jll` (1), `Fontconfig_jll` (1), `Arpack_jll` (2 hooks
Fortran `dbgini_`/`staini_`).  Más `LERC_jll` (ausente).

Ojo con un detalle del método: el gap de `XML2_jll` salió de 4 a 236 entre dos corridas porque
la segunda resolvió una versión **más nueva** del JLL.  Un gap es una propiedad del par
(versión del JLL, build del sistema), no del nombre.

## 15.5 Cómo reproducirlo

```bash
julia tools/classify-jll.jl --sweep tools/jlls-closure.txt --md      # el mapa
julia tools/validate-overrides.jl --list tools/jlls-overrides.txt    # la validación
```

El depot de scratch se borra al final: `rm -rf "$TMPDIR/ygg-depot"`.
