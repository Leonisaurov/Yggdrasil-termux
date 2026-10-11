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

Los cinco que no cargaban tenían **cinco bloqueadores raíz** — resueltos todos en §15.6:

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

## 15.6 Los cinco bloqueadores, resueltos (2026-10-11)

La regla del proyecto es no construir lo que el sistema ya da, así que cada bloqueador se
resolvió por la palanca más barata que lo cerrara de verdad. **Cuatro de los cinco no
necesitaron ningún build**, y el motivo es una medición, no una opinión:

| bloqueador | cómo se resolvió | evidencia |
|---|---|---|
| `Fontconfig_jll` (1 símbolo) | gap aceptado | el sistema es **más nuevo** (2.18.3 vs el 2.17.1 del JLL): `default_langs` desapareció aguas arriba |
| `Libffi_jll` (2) | gap aceptado | sistema 3.8.0 vs 3.4.7; los dos son entry points de **Go** (`ffi_call_go`, `ffi_prep_go_closure`) |
| `GettextRuntime_jll` (10) | **dir compuesto**: `libintl.so` construido acá + symlinks al sistema | `find $PREFIX -name 'libintl*'` da sólo headers y jars: **Termux no shipa `libintl`**, y Glib lo necesita |
| `JpegTurbo_jll` / `XZ_jll` / `Expat_jll` | override normal | los productos que faltan son **ejecutables** (`cjpeg`, `xmlwf`) o una `.a`: leído en el fuente de JLLWrappers, `@init_executable_product` **no valida que el archivo exista**, sólo calcula el path y suma el dir al `PATH` |
| `LERC_jll` | **artefacto propio** | Termux no empaqueta `libLerc`, y Libtiff lo necesita: compilado de Esri LERC 4.2.0 con el clang++ bionic |
| `Gettext_jll` (47) | gap aceptado | son **shims de portabilidad de gnulib** (`getrandom`, `copy_file_range`, `getprogname`): bionic ya los tiene, así que su ausencia es el resultado *correcto* |
| `Libglvnd_jll` (1), `XML2_jll` (236), `Arpack_jll` (2) | gaps aceptados | 1 variable TLS de GL con 3470/3470 y 1044/1044 iguales; libxml2 2.15.4 (más nuevo, **más** símbolos: 1400 vs 1369); 2 hooks Fortran de debug |

Los gaps aceptados viven en `tools/jlls-accepted-gaps.txt` **con su evidencia al lado**, y el
clasificador sólo los toma si están declarados: un gap nuevo no se puede colar.  Los artefactos
propios, en `tools/jlls-built-artifacts.txt`.

Y los nombres que el sistema no shipa van en `overrides/aliases.sh`, idempotente, con el mismo
criterio que `needed-library-aliases.sh` de julia-termux (el consumidor pide el SONAME, no el
path).

### El estado medido, al cerrar

```
julia tools/classify-jll.jl --sweep tools/jlls-closure.txt   # 53 JLLs
  ... needs-jll (gap) 0   ... needs-jll (absent lib) 0
julia tools/validate-overrides.jl --list tools/jlls-overrides.txt
  validated: 37 / 37
  artifact directories after: 26 (0 new)
```

**Cero `needs-jll` en toda la clausura**, 37 overrides validados cargando los JLLs de verdad, y
ningún artefacto nuevo bajado durante la validación.

Consumidores reales en el dispositivo, no sólo JLLs:

```
FFTW.jl      fft/ifft, rfft, plan/apply, dct/idct  → true
SQLite.jl    INSERT con parámetros + SELECT        → [42, 43]   libsqlite = $PREFIX/lib/libsqlite3.so
EzXML.jl     parsexml + findfirst                  → "42"       (valida el gap de 236 de XML2)
Cairo.jl     using Cairo carga Cairo+Pango+Glib+FriBidi+HarfBuzz sin InitError
```

### La clausura, convergida

Re-derivada de lo instalado después de esa vuelta, son **55 JLLs** (entraron `Pango_jll` y
`FriBidi_jll` por el consumidor) y siguen **cero `needs-jll`**: 7 stubs, 1 alias, 9 `override`,
16 `override-needs-alias`, 6 gaps aceptados, 3 artefactos propios, 3 con programas faltantes y 1
sin productos.  La tabla quedó en **37 entradas** y `validate-overrides.jl` da **37/37 con 0
artefactos nuevos** — el depot del usuario se quedó en 3 entradas (los dos artefactos de JLLs que
no están en la tabla, que se conservan).

`Cairo.jl` además mostró que la clausura es **más profunda de lo que uno escribe a mano**: su
dependencia `Pango_jll` arrastra `FriBidi_jll`, que no estaba en ninguna lista.  Por eso el
archivo de clausura se **deriva** de lo instalado después de cada barrido
(`ls ~/.julia/packages/*_jll/*`), en vez de escribirse: cada vuelta converge un nivel más.

### Los tres artefactos, publicados y verificados (2026-10-11)

| artefacto | release | sha256 | verificado bajando la release |
|---|---|---|---|
| FFTW 3.3.11 | `fftw-bionic` | `3c3e8f50…` | sí (docs/14 §14.1) |
| LERC 4.2.0 | `lerc-bionic` | `e521e9543d959747…` | sí — instalado en el dispositivo y los 37 overrides revalidados |
| gettext-runtime 1.0 | `gettext-runtime-bionic` | `12aaaf371bf791ea…` | sí — igual, y sus cinco symlinks resuelven |

Los tres salen del mismo workflow (`build-bionic-artifact.yml`, input `recipe`) y de scripts que
se corrieron en el dispositivo antes de commitearlos.  Dos trampas del entorno del runner
aparecieron en la primera corrida y quedaron documentadas: cmake agarrando el **ninja del host**
(glibc) y muriendo en el `LD_PRELOAD` bionic —el mismo muro que `/bin/sh`, un nivel más abajo— y
el prefijo del CI sin `gettext`, que hacía colgar los symlinks del dir compuesto (el input
`packages` de la acción lo resuelve).

## 15.7 Lo que falta para el camino del registro, y una trampa medida

El paso estructural (docs/13 §13.1) necesita dos mitades que ya están en marcha:

1. **La plataforma** — `base-binaryplatforms.jl.patch` enseña la gramática (`bionic` en
   `validate_tags`, `-android` ⇄ `bionic` en el mapa y en `libc_str`) y la receta fija
   `BB_TRIPLET_LIBGFORTRAN_CXXABI=aarch64-linux-android-cxx11` en la línea de `make`, porque el
   build corre en un runner Ubuntu y si no el triplete que el sysimage embebe sigue diciendo
   `gnu`.  Gate estático en verde (incluye su propio chequeo del triplete).
2. **El fork del JLL + el registro** — el `Artifacts.toml` del fork necesita una entrada
   `libc = "bionic"` con el `git-tree-sha1` del artefacto, y el registro un `Versions.toml` con
   una versión **mayor** que la del General (`3.3.12+1` contra `3.3.12+0`) para que gane la
   precedencia.

**La trampa medida**: el `git-tree-sha1` no es el sha256 del tarball, es el hash del *árbol* del
directorio ya extraído (medido con `Pkg.GitTools.tree_hash`: FFTW `2c72b050…`, LERC `bc253a9c…`,
gettext-runtime `59b26fe1…`).  Y el tarball que hoy publicamos **no sirve** para una entrada de
`Artifacts.toml`: envuelve todo en `fftw-bionic/`, y Pkg extrae el tarball tal cual, así que el
JLL buscaría `artifact_dir/lib/libfftw3.so` y encontraría `artifact_dir/fftw-bionic/lib/…`.
Para `Overrides.toml` está bien (la entrada apunta al *directorio*, no al tarball), y por eso los
37 overrides validados no se ven afectados; para el registro hay que republicar los tres con la
raíz del tarball **en la raíz del artefacto**, que es como los empaqueta BinaryBuilder.

Los dos wrappers de plataforma del fork (`aarch64-linux-android.jl` y `aarch64-linux-bionic.jl`,
idénticos) se copian del `-gnu`: el contenido es independiente de la plataforma y está medido que
funciona en el dispositivo (los 37 overrides cargan con el wrapper gnu sin tocar nada).

### 15.7.1 La plataforma no alcanza: falta el wrapper, y falla en silencio (medido)

El patch de plataforma funciona: con el paquete instalado en el dispositivo,
`HostPlatform()` pasa a `Platform("aarch64","linux"; libc="bionic")` y `Platform(bionic)`
construye y renderiza como `aarch64-linux-android`.  Pero **rompe todo lo demás**, y la medición
es clara:

```
validated: 0 / 37
FFTW.jl    UndefVarError: `libfftw3_no_init` not defined in `FFTW`
SQLite.jl  UndefVarError: `libsqlite` not defined in `SQLite.C`
EzXML.jl   InitError: UndefVarError: `libxml2` not defined in `EzXML`
Cairo.jl   UndefVarError: `libcairo` not defined in `Cairo`
```

La causa está en `JLLWrappers/src/toplevel_generators.jl`: arma `valid_wrappers` con las
plataformas que declara el `Artifacts.toml`, mapea cada una al archivo `src/wrappers/<triplet>.jl`
que exista, y elige el **mejor match** contra el host.  Con el host en `bionic` no hay ningún
wrapper bionic en esos paquetes, y un `libc` distinto **descalifica**: `select_platform` devuelve
`nothing`, y el código lo único que hace es

```julia
if best_wrapper === nothing
    @debug("Unable to load ...; unsupported platform ...")
```

o sea **deja los productos sin definir y sigue**.  De ahí los `UndefVarError` en el consumidor, a
un nivel de distancia del problema.

Consecuencia, y es la parte que importa para el plan: el patch de plataforma es **necesario pero
no suficiente**, y **no se puede publicar** hasta que exista la otra mitad.  El paquete con el
patch quedó construido y **sin publicar** (la release `julia-latest` sigue teniendo el que
funciona, que es de donde se restauró el dispositivo: 37/37 y los cuatro consumidores de vuelta).

La otra mitad tiene dos formas, y la segunda es la buena:

1. **Un wrapper por JLL**: el fork publica `src/wrappers/aarch64-linux-android.jl` (copia del
   `-gnu`, que es independiente de la plataforma) junto a la entrada `bionic` de su
   `Artifacts.toml`.  Con el `libc_mapping` parcheado, `parse_wrapper_platform("aarch64-linux-android")`
   devuelve exactamente la plataforma bionic, así que el match es exacto y el wrapper carga.  Es
   el camino correcto pero cuesta un fork por JLL.
2. **Un JLLWrappers con fallback**, que es lo que arregla a *todos* los JLLs de una vez: si el
   host es bionic y no hay wrapper bionic, usar el `-gnu` (los productos son independientes de la
   plataforma y los flags de `dlopen` del wrapper gnu están medidos funcionando en el dispositivo:
   los 37 overrides cargan con él).  `JLLWrappers` es un **paquete**, no parte del sysimage, así
   que esto se puede probar en el teléfono sin rebuild: se edita el del depot, se reinstala el
   paquete con el patch (ya está bajado) y se corre la misma validación de 37.

### 15.7.2 El fallback funciona, y necesita re-precompilar (medido)

`patches/JLLWrappers-bionic-fallback.patch` (27 líneas en
`JLLWrappers/src/toplevel_generators.jl`): cuando el host es bionic y `select_platform` no
encuentra wrapper, elige el del **mismo `arch` y `os`**, prefiriendo glibc.  Medido en el
dispositivo con el julia que reporta `libc="bionic"` y ese JLLWrappers desarrollado en el entorno:

```
best_wrapper  = .../FFTW_jll/CnY1I/src/wrappers/aarch64-linux-gnu.jl     <- el fallback
libfftw3_path = /data/data/com.termux/files/home/.local/opt/fftw-bionic/lib/libfftw3.so
```

Es decir: el wrapper gnu (que declara los productos y los flags de `dlopen`, nada específico de la
plataforma) y el artefacto saliendo del `Overrides.toml` — exactamente lo que hacía falta para que
el patch de plataforma **no rompa nada**.

**La trampa, y es la razón por la que el primer intento dio 0/37**: el código que genera
`@generate_main_file` se ejecuta en el **cuerpo del módulo** del JLL, así que su resultado queda
horneado en el `precompile` cache.  `Pkg.develop` del JLLWrappers parcheado **no invalida** ese
cache: los JLLs siguen usando el código viejo y fallan igual, en silencio ("the module exposes no
`*_path` binding").  Con `Pkg.precompile()` forzado, funciona.  En la distribución esto no es un
problema: el JLLWrappers parcheado entra al registro con **versión mayor**, y eso sí cambia la
clave del cache de cada JLL.

Con esto, la secuencia para publicar el patch de plataforma queda definida y sin incógnitas:

1. Fork de `JLLWrappers` con el patch, versión `+1` sobre la del General, y una entrada en el
   registro propio.
2. Publicar el julia con el patch de plataforma (`build-package.yml` con `publish=true`), que hoy
   está construido y sin publicar.
3. En el dispositivo: `Pkg.Registry.add` una vez, y verificar que los 37 overrides siguen dando
   37/37 **sin** desarrollar nada a mano.

### 15.7.3 `host_platform` es `nothing` para casi todos los JLLs (medido)

El fallback de `JLLWrappers` (v1 de 1.8.1) estaba en la rama
`if host_platform !== nothing` y **nunca corría**.  En `toplevel_generators.jl:132-135`:

```julia
if @isdefined(augment_platform!)
    const host_platform = augment_platform!(HostPlatform())
else
    const host_platform = nothing
end
```

`augment_platform!` sólo lo define el JLL que necesita aumentar la plataforma (p. ej. los de CUDA);
FFTW_jll no lo define, así que `host_platform === nothing` y el código llama al `select_platform` de
**un** argumento, que usa `HostPlatform()` por dentro.  Medido en el dispositivo con
`libc="bionic"`: `best_wrapper = nothing` y `libfftw3_path` indefinido, **igual precompilado que
con `--compiled-modules=no`** — o sea, no era el cache.  El fallback tiene que correr sobre el
resultado de **las dos** ramas; eso es 1.8.2, y 1.8.1 quedó `yanked`.
