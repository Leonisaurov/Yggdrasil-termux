# 07 — Riesgos, costos y decisiones abiertas

## 7.1 Riesgos técnicos

| Riesgo | Probabilidad | Impacto | Mitigación |
|---|---|---|---|
| El modelo de **shards** de BinaryBuilderBase no encaja con el NDK | alta | alto (bloquea Fase 2) | Probar primero el "camino corto" (compilar con el NDK fuera de BinaryBuilder) |
| Cambiar `HostPlatform()` a bionic **rompe** la selección de artefactos existentes | media | alto | Hacerlo **opt-in** (env/preferencia) y test de no-regresión |
| La ABI del NDK vs la de Termux difiere (libc++, API level) | media | medio | Fijar `cxxstring_abi`/API y comparar símbolos |
| Cada receta de Yggdrasil tiene *quirks* (autoconf, cmake, patches) | alta | medio (por lib) | Empezar por libs simples y medir |
| Recompilar por versión (churn del ecosistema) | alta | medio | Automatizar el pipeline |
| **Duplicación** de libs (artefacto + sistema) | cierta | bajo | Aceptar; mitigar con `Overrides.toml` (`09-...md`) |
| Dos copias de una lib en el mismo proceso | baja | medio | Evitar mezclar; documentar |
| Mantenimiento de forks | alta | medio | Empujar a upstream (Fase 6) |
| Alcance inabarcable (miles de JLLs) | cierta | alto | Alcance acotado + tabla de cobertura honesta |

## 7.2 Costos

- **Tiempo**: las fases 2-3 (toolchain) son el 80% del esfuerzo y las menos documentadas.
- **CI**: builds arm64 con NDK; hay que cuidar minutos/artefactos.
- **Mantenimiento**: forks de BinaryBuilder(Base)/Yggdrasil/JLLs que hay que rebasar.

## 7.3 Riesgos de expectativa (los más importantes)

- **"Va a funcionar todo"**: no. Habrá libs que no compilen, que necesiten parches, o que
  Termux no empaquete. La honestidad está en la tabla de cobertura.
- **"Es más rápido que glibc-runner"**: para *cobertura*, no; glibc-runner gana hoy. Este
  proyecto apunta a **bionic nativo**, no a cobertura máxima inmediata.
- **"Se reutiliza la lib del sistema"**: no; los JLL son herméticos
  (`09-jll-hermetico-y-duplicacion.md`).

## 7.4 Decisiones abiertas

1. **¿Fork o upstream?** ¿Se mantienen forks de BinaryBuilder(Bases)/Yggdrasil/JLLs, o se
   empuja directo a upstream y se espera? (Recomendado: fork para investigar → upstream.)
2. **¿Cómo se reporta Android?** ¿`HostPlatform()` = bionic **siempre** en Android, u
   **opt-in** por env/preferencia? (Recomendado: opt-in al principio.)
3. **¿Tag/`os`?** ¿`libc="bionic"` (como TUR) o `os="android"`? ¿Qué implica en
   `Artifacts.toml` y en la comparación de plataformas?
4. **¿Dónde se publican los artefactos?** ¿Fork de `JuliaBinaryWrappers`, un host propio, o
   `Overrides.toml` por hash (sin registry)?
5. **¿Cómo se distribuye el JLL parcheado?** ¿Registro propio (LocalRegistry) o
   `Overrides.toml`? (Recomendado: `Overrides.toml` para el piloto.)
6. **¿Se ataca la duplicación?** ¿Se acepta que cada JLL traiga su copia, o se apunta a las
   libs de Termux con `Overrides.toml`?
7. **API level / `os_version`.** ¿`android24` (como el dispositivo) o el mínimo razonable?
8. **`cxxstring_abi`.** ¿`cxx11` (libc++ de Termux)?
9. **¿Se hace O2 en paralelo?** Como mitigación inmediata para las libs que Termux ya tiene.

## 7.5 Criterios de abandono (para no invertir de más)

- Si el "camino corto" (NDK a mano + `Overrides.toml`) **no** logra un FFTW bionic que
  funcione en el dispositivo, el problema no es de automatización: parar y reconsiderar O2/O1.
- Si aparece bloqueo de política upstream (no aceptan Android), decidir si se mantiene el
  fork indefinidamente o se vuelca a O2/O1.
