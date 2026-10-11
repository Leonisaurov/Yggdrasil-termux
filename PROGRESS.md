# PROGRESS — bitácora

## 2026-10-10 — Investigación inicial (este repo nace)

**Estado**: planificación. Nada implementado, nada compilado, nada publicado.

### Qué se investigó

- Se partió del port bionic de Julia (`../Julia/julia-termux`), que funciona pero **no**
  resuelve paquetes con binario: `Pkg.add("FFTW")` muere en
  `dlopen failed: library "libm.so.6" not found`.
- Se midió en el dispositivo la causa raíz: `Base.BinaryPlatforms.HostPlatform()` devuelve
  `Platform("aarch64","linux"; libc="glibc")` (`docs/01-problema.md`).
- Se relevó todo el ecosistema (Yggdrasil, BinaryBuilder, BinaryPlatforms, JLLWrappers,
  JuliaBinaryWrappers, Pkg) y su estado respecto de Android (`docs/02-ecosistema.md`,
  `docs/03-estado-del-arte.md`).
- Se evaluaron 5 opciones (`docs/05-alternativas.md`) y se eligió **O4/O3: construir
  artefactos JLL para bionic con Yggdrasil/BinaryBuilder** como estrategia del repo.
- Se respondió una pregunta de diseño con medición: **un JLL no reutiliza la `.so` del
  sistema** (`docs/09-jll-hermetico-y-duplicacion.md`). Consecuencia: con Yggdrasil el
  binario queda **duplicado**; reutilizarlo es otro mecanismo (`Overrides.toml`).

### Hallazgos duros (resumen)

- No existe **ningún** artefacto `aarch64-linux-android` publicado en
  `JuliaBinaryWrappers/*`. Cero.
- `BinaryBuilderBase` **no** tiene shards de compilador bionic (sus 1014 targets son
  gnu/musl/apple/freebsd/windows).
- `BinaryBuilder.jl` issue **#846** (Termux, 2020) sigue **abierto**; no hay PRs Android.
- `Base.BinaryPlatforms` no admite `os=android`; en Linux `libc ∈ {glibc, musl}`.
  (Con `validate_strict=false` el tag `bionic` se acepta, pero no hay artefactos que
  matcheen.)
- El único port bionic maduro (TUR `tur-on-device/julia`) **parchea** BinaryPlatforms para
  `bionic` y **no usa JLLs** (`USE_BINARYBUILDER=0`, `USE_SYSTEM_*=1`).
- La comunidad que quiere JLLs usa **glibc-runner** (`termux/glibc-packages`) con el Julia
  glibc oficial; ahí `host_platform` es glibc y todo carga.

### Decisiones

1. **Estrategia**: Yggdrasil/BinaryBuilder (no musl, no glibc-runner como camino principal).
2. **Alcance**: conjunto inicial acotado de librerías; no prometer el ecosistema entero.
3. **Upstream vs fork**: decisión **abierta** (`docs/07-riesgos.md` §Decisiones abiertas).
4. **Duplicación de libs**: aceptada por defecto; mitigable con `Overrides.toml` si molesta.

### Próximo paso (cuando se retome)

Empezar por la **Fase 1** de `docs/04-plan.md`: soporte de plataforma Android/bionic en
`Base.BinaryPlatforms` (patch reproducible sobre un pin), con su criterio de aceptación.

### Documentación agregada en el cierre de la investigación

- `docs/11-fallos-y-limitaciones.md`: catálogo de fallos conocidos y limitaciones, con tag
  `[MEDIDO]`/`[CITADO]`/`[INFERIDO]`, matriz “qué funciona / qué no”, y **troubleshooting**
  de los mensajes de error (`libm.so.6 not found`, `@GLIBC_*`, `uv_cpu_info EACCES`,
  `signal 31`, `rc=127` musl, `Package X not found`, etc.).
- `docs/12-diseno-plataforma-bionic.md`: la **spec** con los cambios exactos de
  `binaryplatforms.jl`/`normalize_triplet.py` (patch de referencia de TUR, citado), valores
  del tag, entrada de `Artifacts.toml` y toolchain (NDK).
- `docs/13-distribucion-y-consumo.md`: registro propio vs `Overrides.toml` (incluida la
  variante **por hash**, que **no requiere** el patch de plataforma y sirve para el piloto),
  hosting y licencias.

### Pendientes decididos por el usuario

- **Diferido a propósito**: qué hacer con la duplicación de libs y la integración de las
  libs del sistema (`Overrides.toml`/`<producto>_path`). Queda documentado, no implementado.

## 2026-10-10 — Anexo: `juliac` (compilar `.jl` a binario) y el paquete

Investigado al margen de los JLL, pero anotado acá porque es otra limitación del
runtime bionic en el dispositivo:

- **Sí existe el camino**: Julia 1.12 trae `juliac`
  (`--output-exe` / `--output-lib` / `--output-sysimage`); `PackageCompiler.jl` es la
  vía clásica. No genera un binario autónomo: linkea `libjulia` **y**
  `libjulia-internal` (`--relative-rpath` deja las libs al lado).
- **Upstream no instala wrapper**: en `release-1.12` el script vive en
  `contrib/juliac/juliac.jl` → `share/julia/juliac/juliac.jl`; `Makefile:92` lo lista
  como dato compartido y **no hay regla** que ponga un nombre en `PATH` (tampoco en
  `cli/`, ni en el manual, ni en `NEWS.md`). El port `julia-termux` agrega `bin/juliac`
  (probado con prefijo reubicado, por symlink y por nombre pelado, 5/5).
- **Y no compila en este teléfono**: `juliac --output-exe hello hello.jl` muere en el
  paso `julia --output-o` con `std::bad_alloc` (308 s; **200 s** con `-O0` inyectado en
  una copia del script, que tampoco alcanza). No falta RAM nominal (12 GB, 7,5 GB
  disponibles) pero `Committed_AS` (220,9 GB) supera largamente `CommitLimit`
  (18,6 GB) **[MEDIDO] 2026-10-10**.
- **No arregla los JLL**: el `.so` del JLL se `dlopen`ea en runtime; son problemas
  ortogonales.

Detalle completo: `../Julia/julia-termux/PROGRESS.md` (Pendientes, item 7).

## 2026-10-10 — `juliac` medido: es RAM, y nuestro build pide ~19% más

Respuesta al "¿es problema de acá o de Julia?" que quedó abierto en el anexo anterior.
Se corrió `juliac --output-exe` con **nuestro** artefacto publicado dentro de un prefijo
Termux materializado en `ubuntu-24.04-arm` (workflow `probe-juliac-binary.yml` del repo
del port; run **38021823582**):

| Quién | Reloj | Pico RSS | Resultado |
|---|---|---|---|
| upstream aarch64 (runner 16 GB) | 2:30 | **6,12 GB** | rc=0, binario corre |
| upstream x86_64 (runner 16 GB) | 2:28 | 4,48 GB | rc=0, binario corre |
| **nuestra julia** (runner 16 GB) | 2:40 | **7,30 GB** | rc=0, binario corre (212 MB, `interpreter /system/bin/linker64`) |
| **nuestra julia** (teléfono) | ~5 min | 6,45 GB | `std::bad_alloc` |

Conclusión: **no es un bug de Julia ni del port**. El paso `julia --output-o` pide
~6-7 GB y el teléfono no los tiene libres con Android encima. Dos consecuencias:
`juliac` es usable donde haya ≥8 GB, y en el dispositivo no; y nuestro build bionic
pide **~1,2 GB más** que el oficial para el mismo hello world (+19%), diferencia que
conviene mirar si algún día se quiere compilar **en** el teléfono.

El probe necesitó 6 iteraciones y **todas** fueron del entorno del runner, no del
código del port: SIGPIPE de `ls | head` bajo `pipefail`, el shim `libm.so` que un
dispositivo tiene y un prefijo solo-.deb no, `bash -e` tragándose el rc de `juliac`,
el `Pkg.precompile()` que clona el registro, `JULIA_PKG_OFFLINE` que no alcanza con
depot sin registro, y `git` resolviendo al biónico del prefijo.  Ver
`../Julia/julia-termux/PROGRESS.md` (Pendientes 7).

## 2026-10-11 — Clasificación de JLLs y el parche de consumo

- `tools/classify-jll.jl`: clasifica por JLL si la librería de Termux satisface lo que el
  JLL declara (productos, SONAMEs, superficie de símbolos), sin cargar el JLL (su `__init__`
  hace `dlopen` del artefacto glibc y revienta acá).  Primera tabla medida: `FFTW_jll`
  needs-jll, `libpng_jll` override-needs-alias, seis stdlibs system-stub.
- Hallazgo estructural: **los stdlib JLLs de un Julia de fuentes ya son stubs de upstream**
  (`dlopen` por soname, `artifact_dir = dirname(Sys.BINDIR)`, cero artefactos en el depot).
  La política "no bajes, usá la del sistema" ya existe para los stdlibs; falta generalizarla
  a los JLLs de la registry.
- Veredicto validado: `libpng` predijo "alcanza un symlink" y con el artefacto apartado la
  JLL cargó la libpng bionic del sistema (`ccall png_access_version_number` → 10659).
- `docs/09` §9.7: el override por hash evita la descarga; el UUID+nombre no (Pkg pierde el
  uuid).  El parche de consumo vive en julia-termux y quedó registrado en `docs/14`.

## 2026-10-11 — El artefacto bionic de FFTW: el primer `needs-jll` resuelto

- `scripts/build-fftw-bionic.sh` (en `../Julia/julia-termux`): construye el artefacto con el
  clang bionic en **dos pasadas** de `configure` (`--enable-threads --with-combined-threads
  --enable-neon --disable-fortran`, la segunda con `--enable-float`), con el tarball pineado
  por sha256.  **Medido**: `libfftw3.so.3.7.11` 1.395.769 B y `libfftw3f.so.3.7.11`
  1.396.537 B, SONAME `libfftw3.so.3` / `libfftw3f.so.3`, **207 codelets `_neon`** cada una,
  `init_threads` presente.
- **Libtool ignora `-version-info` en este host**: su `config.guess` no conoce el triplete
  Android (medido: `.la` con `library_names='libfftw3.so libfftw3.so'` aunque el Makefile
  traía `SHARED_VERSION_INFO = 10:11:7`) ⇒ el naming oficial se arma a mano (archivo real
  versionado + `patchelf --set-soname` + symlinks).
- **Aceptación**: programa C bionic que carga por soname, inicializa threads y ejecuta una
  transformada → `dc[1] = -4.000 9.657` (rc=0).  Gap restante: 102 símbolos, **todos**
  wrappers Fortran (`dfftw_*`/`sfftw_*`), que ningún consumidor de Julia usa.
- **Publicado y verificado en el dispositivo**: release `fftw-bionic` (1.555.734 B, sha256
  `3c3e8f50…`) bajado al teléfono; con el artefacto glibc apartado del depot y el override
  UUID+nombre, `FFTW_jll.libfftw3_path = …/fftw-bionic/lib/libfftw3.so`, `fft/ifft`, `rfft`,
  `plan/apply` y `dct/idct` correctos, y **el depot sin bajar nada**.
- Workflow propio (`build-bionic-artifact.yml`, ~4 min, grupo de concurrencia propio, no toca
  `packages/julia/**`): así un cambio del artefacto no invalida el caché del build de Julia
  (~60 min).  Tres corridas fallaron por trampas del entorno del runner (normalizar una ruta
  antes de crearla, el `/bin/sh` glibc con el `LD_PRELOAD` bionic → *invalid ELF header*, la
  caché del tarball recomputada tras el re-exec, y `tar | head` bajo `pipefail`); las tres
  quedaron registradas en `../Julia/julia-termux/AGENTS.md`.

## 2026-10-11 — El mapa a escala: 43 JLLs clasificados, 23 overrides validados

- `tools/classify-jll.jl` ahora barre (`--sweep`, un solo entorno para N JLLs) y emite la
  tabla en markdown y el bloque de overrides en la forma **estable** (UUID + nombre de
  artefacto, la que el `Pkg` parcheado honra).  El mapa completo: `docs/15`.
- **El barrido corrigió el clasificador tres veces** (todas medidas, todas en `docs/15` §15.2):
  los artefactos oficiales exportan `__bss_end__`/`__bss_start__`/`__end__`/`_bss_end__` (tipo
  `B`) y `_init`/`_fini` (`T`) y Termux no, así que cuatro símbolos fantasma convertían **diez**
  librerías en falsos `needs-jll`; `XZ_5.1.2alpha` es un nodo de versión (tipo `A`) y un
  `_ZSt4swap…` de HarfBuzz es débil (`W`); y un producto ausente puede ser una librería o un
  ejecutable, que no son la misma decisión (JpegTurbo/Expat/XZ estaban condenados por `cjpeg`,
  `xmlwf` y `liblzma.a` con la librería compartida satisfecha).
- **La clausura manda**: `Cairo`, `HarfBuzz`, `Glib`, `Libtiff`, `libwebp` y `XML2` pasaron la
  comparación de símbolos y después no cargaron, porque una dependencia seguía apuntando a su
  artefacto glibc.  Se agregó `tools/validate-overrides.jl`, que carga el JLL de verdad y exige
  que cada `<producto>_path` resuelva fuera de `<depot>/artifacts`: **19/24 PASS, 0 artefactos
  nuevos**.  Los cinco que no cargan tienen cinco bloqueadores raíz (Fontconfig 1 símbolo,
  Libffi 2, JpegTurbo 3 programas, XZ un `.a`, LERC ausente).
- `overrides/termux-overrides.toml`: 24 entradas (FFTW + los 23 ganadores), aplicadas y
  validadas en el dispositivo.  Duplicación medida del stack: **209,3 MB** de artefactos
  oficiales en 43 JLLs, ninguno de los cuales carga.

## 2026-10-11 — Los cinco bloqueadores, cerrados sin construir casi nada

- El barrido dejó cinco bloqueadores raíz.  **Cuatro no necesitaron build**, y el motivo es una
  medición: Fontconfig y Libffi son gaps aceptables (el sistema es *más nuevo* y el símbolo
  desapareció aguas arriba; los de Libffi son entry points de Go), y JpegTurbo/Expat/XZ sólo
  tenían productos **no validados** — leído en el fuente de JLLWrappers,
  `@init_executable_product` no chequea que el archivo exista, sólo calcula el path.
- `GettextRuntime_jll` sí necesitó trabajo: `find $PREFIX -name 'libintl*'` muestra que Termux
  **no shipa `libintl`** (sólo headers y jars) y Glib lo necesita.  Se compiló gettext 1.0
  (`make -C gettext-runtime/intl`, sha256 85d99b79…) y el override es un **dir compuesto**:
  `libintl.so` propio + symlinks al `libasprintf.so` y a los programas del sistema.
- `LERC_jll`: Termux no empaqueta `libLerc` y Libtiff lo necesita → **artefacto propio**,
  compilado de Esri LERC 4.2.0 (sha256 a1fb593e…) con el clang++ bionic; `libLerc.so.4` sólo
  pide `libc++_shared`/`libc`/`libm`.
- Mecanismos nuevos, los dos con evidencia al lado: `tools/jlls-accepted-gaps.txt` (6 gaps
  declarados; el clasificador **no** los toma si no están escritos) y
  `tools/jlls-built-artifacts.txt` (3 JLLs cuyo override apunta a un artefacto propio).
  `overrides/aliases.sh` crea los nombres que el sistema no shipa (`libpng16.so.16`,
  `libfribidi.so.0`), idempotente.
- **Medido al cerrar**: `needs-jll (gap) 0` y `needs-jll (absent lib) 0` en los 53 JLLs de la
  clausura; `validate-overrides.jl` → **37/37**, 0 artefactos nuevos.  Consumidores reales:
  FFTW.jl, SQLite.jl, EzXML.jl (valida el gap de 236 de XML2) y `using Cairo` cargando
  Cairo+Pango+Glib+FriBidi sin InitError.
- La clausura es más profunda de lo que se escribe a mano: `Cairo.jl` reveló `Pango_jll` →
  `FriBidi_jll`.  Por eso `tools/jlls-closure.txt` se **deriva** de lo instalado después de cada
  barrido y converge un nivel por vuelta.

## 2026-10-11 — Clausura convergida, remoto, depot limpio y artefactos con CI

- **Remoto**: el repo es `Leonisaurov/Yggdrasil-termux` (público), con los 14 commits empujados y
  su fila + bloque de quick commands en `PORTS.md` del workspace.
- **Depot limpio**: 156 MB → 3.4 MB.  Se mapeó cada artefacto del depot a su JLL leyendo los
  `Artifacts.toml` de los paquetes (el hash no dice nada por sí solo) y se borraron **sólo** los 23
  cubiertos por un override; quedan los dos de JLLs que no están en la tabla (`LLVMOpenMP_jll` y
  `Xorg_xtrans_jll`, que se conservan a propósito).  Verificado después: **37/37** y **0
  artefactos nuevos**, o sea que los 23 eran peso muerto.
- **Artefactos reproducibles**: `scripts/build-lerc-bionic.sh` y
  `scripts/build-gettext-runtime-bionic.sh` (en julia-termux, como el de FFTW), cada uno pineado
  por sha256 de la fuente y con un test de aceptación de verdad — LERC hace un round trip por la
  API C (`115 bytes compressed, exact`) y gettext-runtime llama `gettext`/`dgettext` desde un
  programa bionic.  Los dos corrieron en el dispositivo antes de commitear (el primer test de
  LERC pasaba 9 argumentos a una función de 10; las firmas ahora salen del `Lerc_c_api.h`).
- **Un workflow para los tres**: `build-fftw-bionic.yml` → `build-bionic-artifact.yml`, con un
  input `recipe` (fftw, lerc, gettext-runtime) resuelto en un paso que mapea script, directorio,
  tag y nota de release; concurrencia **por receta** (un dispatch de lerc no cancela un fftw en
  curso) y sigue sin tocar `packages/julia/**`.
- **Clausura convergida**: re-derivada de lo instalado, **55 JLLs** y **cero `needs-jll`**; tabla
  de 37 entradas, `validate-overrides.jl` **37/37** con 0 descargas.

## 2026-10-11 — Los tres artefactos en CI, publicados y verificados desde la release

- `build-fftw-bionic.yml` → **`build-bionic-artifact.yml`** con un input `recipe` (fftw, lerc,
  gettext-runtime) resuelto en un paso que mapea script, directorio, tag y nota de release;
  concurrencia **por receta** y sigue sin tocar `packages/julia/**`.  Tres corridas verdes en
  paralelo (una por receta) y tres releases: `fftw-bionic`, `lerc-bionic`
  (sha256 `e521e9543d959747…`) y `gettext-runtime-bionic` (sha256 `12aaaf371bf791ea…`).
- Dos fallos de la primera corrida, los dos de entorno y ninguno del artefacto: cmake agarraba
  el **ninja del host** (`/usr/local/bin/ninja`, glibc) y moría con el `LD_PRELOAD` bionic
  (`invalid ELF header`) —el mismo muro que `/bin/sh`, un nivel más abajo—; y el prefijo del CI
  no tiene `gettext`, así que los cuatro symlinks del dir compuesto colgaban.  Arreglos:
  Makefiles en LERC (como FFTW, que sí pasó) y el paso de resolución **antes** de materializar
  el prefijo para poder pedirle los paquetes extra que cada receta necesita.
- **Verificado bajando las releases al dispositivo**: sha256 OK, el dir compuesto resuelve sus
  cinco productos, y con esos artefactos `validate-overrides.jl` da **37/37** con **0
  artefactos nuevos**.  Consumidores: EzXML.jl y `using Cairo` (Cairo+Pango+Glib+FriBidi).
- Los construidos a mano quedaron como `.handbuilt` al lado de los publicados.

## 2026-10-11 — La plataforma bionic: patch hecho, medido, y la mitad que falta

- `base-binaryplatforms.jl.patch` (gramática: `bionic` en `validate_tags`, `-android` ⇄ bionic en
  el mapa y en `libc_str`) + la receta fijando `BB_TRIPLET_LIBGFORTRAN_CXXABI=aarch64-linux-android-cxx11`
  en la línea de `make` (el build corre en un runner Ubuntu, así que el triplete que el sysimage
  embebe salía `gnu`).  Build **verde** (~80 min) y **sin publicar**.
- **Medido en el dispositivo, instalando ese paquete**: `Base.BUILD_TRIPLET =
  aarch64-linux-android-cxx11`, `HostPlatform() = Platform("aarch64","linux"; libc="bionic")`,
  `Platform(bionic)` construye y renderiza `aarch64-linux-android`.  El patch de plataforma
  funciona.
- **Y rompe todo**: `0/37` overrides y los consumidores con `UndefVarError: libfftw3_no_init not
  defined` / `libsqlite` / `libxml2` / `libcairo`.  Causa medida en
  `JLLWrappers/src/toplevel_generators.jl`: arma `valid_wrappers` desde el `Artifacts.toml`,
  elige el mejor match contra el host, y un `libc` distinto **descalifica** → `select_platform`
  devuelve `nothing` → el código sólo hace `@debug` y **deja los productos sin definir**.
  Silencio, a un nivel de distancia del síntoma.
- **Dispositivo restaurado** desde la release `julia-latest` (que no se movió): `HostPlatform()`
  vuelve a glibc, `37/37`, FFTW/SQLite/EzXML/Cairo andando.
- La otra mitad, en `docs/15` §15.7.1: un wrapper `aarch64-linux-android.jl` por fork (correcto,
  cuesta un fork por JLL) o **un JLLWrappers con fallback al `-gnu`** cuando el host es bionic y no
  hay wrapper bionic — un paquete, no sysimage, así que se prueba en el teléfono sin rebuild.
- Dos pitfalls nuevos en `AGENTS.md`: el lint del CI corre shellcheck y el gate local no (una
  asignación con sintaxis de Makefile en un script de shell pasa local y muere en CI), y en la
  receta las líneas `X := Y` son contenido de `Make.user`, no shell.
