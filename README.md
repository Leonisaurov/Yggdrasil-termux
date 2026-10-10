# Yggdrasil-termux — artefactos JLL de Julia para Termux/Android (bionic)

> **Estado: investigación y planificación.** No hay nada implementado, compilado ni
> publicado. Este repositorio existe para poder ejecutar el plan **desde cero** sin volver
> a investigar. Fecha de la investigación: **2026-10-10**.

## El problema, en un párrafo

En Termux/Android el libc es **bionic**, no glibc ni musl. Julia resuelve las dependencias
binarias de los paquetes con **JLLs** (`*_jll`): paquetes que descargan un **artefacto**
precompilado (un `.tar.gz` con `.so`) y lo cargan con `dlopen`. Julia decide qué artefacto
bajar con `Base.BinaryPlatforms.HostPlatform()`, que en el teléfono devuelve
`Platform("aarch64","linux"; libc="glibc")` (bionic no es ninguna de las dos libc que Julia
conoce, así que cae a glibc). Resultado: **el artefacto glibc no carga en bionic** porque
pide `libm.so.6`/`libc.so.6`/`libpthread.so.0` y símbolos versionados `@GLIBC_2.17`, que
bionic no tiene. Paquetes puros de Julia funcionan; paquetes con binario glibc no.

## Qué propone este repositorio

Construir los artefactos JLL **para `aarch64-linux-android` (bionic)** usando la cadena
**Yggdrasil → BinaryBuilder → JLLWrappers**, y publicarlos, para que `Pkg.add` de un paquete
con binario funcione de forma nativa en Termux. Es el "arreglo correcto" a largo plazo
(Opción O4/O3 de `docs/05-alternativas.md`).

## Lo que este enfoque NO hace (decisión de diseño ya medida)

Los JLL son **herméticos**: el wrapper hace `joinpath(artifact_dir, "lib/libX.so")` y
`dlopen` de **su propia copia**. **No** detectan que la `.so` ya está instalada en
`$PREFIX/lib` ni la reutilizan. Con Yggdrasil tendrías el binario bionic correcto, pero
**duplicado** (Termux + `~/.julia/artifacts/`). Para reutilizar la del sistema hay que usar
`Overrides.toml`/`<producto>_path`, que es **ortogonal** a Yggdrasil. Detalle en
`docs/09-jll-hermetico-y-duplicacion.md`.

## Índice de la documentación

| Doc | Contenido |
|---|---|
| [`docs/00-contexto.md`](docs/00-contexto.md) | De dónde viene todo: el port `julia-termux` bionic que ya funciona. |
| [`docs/01-problema.md`](docs/01-problema.md) | La causa raíz medida (HostPlatform, sonames, symbol versions). |
| [`docs/02-ecosistema.md`](docs/02-ecosistema.md) | Yggdrasil, BinaryBuilder(Base), JLLWrappers, JuliaBinaryWrappers, Pkg, BinaryPlatforms, General, PkgServer. Cómo encajan. |
| [`docs/03-estado-del-arte.md`](docs/03-estado-del-arte.md) | Qué existe y qué no hoy (con fuentes). TUR, glibc-runner, otros ecosistemas. |
| [`docs/04-plan.md`](docs/04-plan.md) | **El plan por fases** para hacerlo desde cero. |
| [`docs/05-alternativas.md`](docs/05-alternativas.md) | O1 glibc-runner, O2 system-providers, O3 registry propio, O4 upstream, O5 musl. Tradeoffs. |
| [`docs/06-verificacion.md`](docs/06-verificacion.md) | Criterios de aceptación y cómo probar (rojo→verde, en dispositivo). |
| [`docs/07-riesgos.md`](docs/07-riesgos.md) | Riesgos, costos, límites y decisiones abiertas. |
| [`docs/08-referencias.md`](docs/08-referencias.md) | Todas las URLs y citas. |
| [`docs/09-jll-hermetico-y-duplicacion.md`](docs/09-jll-hermetico-y-duplicacion.md) | Por qué un JLL no reusa la lib del sistema, y qué sí lo haría. |
| [`docs/10-glosario.md`](docs/10-glosario.md) | Términos (JLL, artefacto, BinaryPlatforms, shard, ABI, …). |
| [`docs/11-fallos-y-limitaciones.md`](docs/11-fallos-y-limitaciones.md) | **Catálogo de fallos conocidos, limitaciones y troubleshooting** (con [MEDIDO]/[CITADO]). |
| [`docs/12-diseno-plataforma-bionic.md`](docs/12-diseno-plataforma-bionic.md) | **Spec exacta** de la plataforma bionic: los 3 cambios de `binaryplatforms.jl`, el tag, la entrada `Artifacts.toml`, el toolchain. |
| [`docs/13-distribucion-y-consumo.md`](docs/13-distribucion-y-consumo.md) | Cómo se distribuye y consume: registro propio vs `Overrides.toml`, hosting y licencias. |

## Cómo se usaría este repo

1. Leer `docs/04-plan.md` de punta a punta; las fases son incrementales y cada una tiene
   su criterio de aceptación en `docs/06-verificacion.md`.
2. Empezar por la Fase 1 (soporte de plataforma Android/bionic); sin eso, nada de lo demás
   se puede ni probar.
3. No prometer cobertura total: Yggdrasil tiene miles de recetas. El plan propone un
   **conjunto inicial acotado** (las libs más usadas) y medir cobertura real.

## Proyecto relacionado

El port nativo bionic de Julia que motivó todo esto vive en
[`../Julia/julia-termux`](../Julia/julia-termux) (release verificada en el dispositivo,
19/19 en `scripts/device-smoke.sh`). Ese port **ya resuelve** el caso de las librerías que
Julia trae adentro (`USE_SYSTEM_*` contra las libs de Termux); lo que falta es el ecosistema
de paquetes por `Pkg.add`.
