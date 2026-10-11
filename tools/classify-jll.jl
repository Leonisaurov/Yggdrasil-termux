#!/data/data/com.termux/files/usr/bin/julia
#
# classify-jll.jl — can the library Termux already ships satisfy what a JLL declares?
#
# The question this answers, per JLL, is the one that decides whether Yggdrasil has to
# build anything at all: an `Overrides.toml` entry pointing the artifact at $PREFIX is
# only sound if the system's copy exposes **the same products, at the same paths, with
# the same symbol surface** the JLL declares.  Measured on 2026-10-11 with FFTW_jll:
# the override loaded Termux's bionic libfftw3.so (so the override is what makes a JLL
# usable on bionic at all, since the glibc .so is never loaded) and then died on
#   undefined symbol: fftw_init_threads
# because the official artifact merges FFTW's threads API into libfftw3 while Termux
# ships upstream's split layout.  This script finds that class of mismatch before
# anyone wires an override.
#
# It never loads the JLL: `using Foo_jll` runs the generated __init__, which dlopens the
# artifact - on this platform that is exactly the glibc .so that cannot load, so the
# module blows up before it can be asked anything (measured: InitError, libm.so.6).
# Everything is read instead: the wrapper source for the declared products, and the
# artifact on disk for the SONAMEs and the symbol surface.
#
# Note on the platform: HostPlatform() here reports libc="glibc" (Sys.MACHINE is
# aarch64-unknown-linux-android24, but BinaryPlatforms only knows glibc and musl), which
# is why a JLL happily selects and downloads the *glibc* artifact on this device.  That
# download is the duplication this project is about, and it is also the measurement of
# how much of it each JLL costs today.
#
# Usage:
#   julia classify-jll.jl [--prefix DIR] [--show-symbols N] [--md] JLL [JLL ...]
#   julia classify-jll.jl --sweep tools/jlls-sweep.txt [--md]
#
# Run it against a scratch depot, not the real one:
#   mkdir -p "$TMPDIR/ygg-depot" && cp -a ~/.julia/registries "$TMPDIR/ygg-depot/"
#   JULIA_DEPOT_PATH="$TMPDIR/ygg-depot" JULIA_PKG_PRECOMPILE_AUTO=0 \
#       julia tools/classify-jll.jl --sweep tools/jlls-sweep.txt --md
# Two reasons.  The comparison has to be against the **official** artifact: an
# `Overrides.toml` in the real depot redirects a JLL to a local build (FFTW's does), and
# then this script would compare that build against $PREFIX - the artifact answering the
# question would be the answer.  And the artifacts it downloads to measure are exactly the
# duplication the project is about, so they belong in a scratch depot that is deleted
# afterwards, not in the user's.
#
# `--sweep FILE` reads one JLL per line (`#` comments allowed) and installs them into a
# single shared environment, so a whole stack is one resolve instead of N.  `--md` adds a
# markdown table of the findings, which is how docs/15 is written - the table in the docs
# is generated, not transcribed.
#
# Verdicts, cheapest lever first:
#   system-stub         stdlib stub: already resolves to the system, downloads nothing
#   needs-alias         a stub whose soname nothing answers (a symlink fixes it)
#   override            every product exists, its SONAME resolves, no missing symbols:
#                       one Overrides.toml line stops the download, nothing is built
#   override-needs-alias  same, plus a name to create (a symlink answers it)
#   needs-jll (absent lib)  the system root does not have a declared *library* at all.
#                       Read the note: this is either "the Termux package is not installed"
#                       (then the lever is `pkg install`, still nothing to build) or "Termux
#                       does not package it" (then it is Yggdrasil's job)
#   needs-jll (absent exe)  the library is there, but the JLL also declares an executable or
#                       a static file the system root lacks.  The library is overridable;
#                       JLLWrappers' __init__ still checks every product, so the JLL will not
#                       load until that program exists too (measured: JpegTurbo's
#                       cjpeg/djpeg/jpegtran, Expat's xmlwf, XZ's liblzma.a)
#   needs-jll (gap)     the product is there but exports less API than the official build:
#                       a different feature set, and no name will conjure the symbols.
#                       This is FFTW, and it is the case that produces artifacts
#   no-artifact         no artifact matches this platform: the JLL cannot be used here
#                       without an override in the first place
#
# Exit status: 0 if every JLL was classified, 1 if one could not be inspected.

using Pkg
using Artifacts
using TOML
using Base.BinaryPlatforms: HostPlatform

function parse_args(args)
    prefix = get(ENV, "PREFIX", "/data/data/com.termux/files/usr")
    show_symbols = 5
    markdown = false
    sweep = nothing
    jlls = String[]
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--prefix" && i < length(args)
            prefix = args[i + 1]; i += 2
        elseif a == "--show-symbols" && i < length(args)
            show_symbols = parse(Int, args[i + 1]); i += 2
        elseif a == "--sweep" && i < length(args)
            sweep = args[i + 1]; i += 2
        elseif a == "--md"
            markdown = true; i += 1
        else
            push!(jlls, a); i += 1
        end
    end
    if sweep !== nothing
        for line in eachline(sweep)
            s = strip(line)
            (isempty(s) || startswith(s, "#")) && continue
            push!(jlls, split(s)[1])
        end
    end
    return prefix, show_symbols, markdown, jlls
end

const PREFIX, SHOW, MARKDOWN, JLLS = parse_args(ARGS)

function sh(cmd::Cmd)
    out = IOBuffer()
    ok = success(pipeline(cmd; stdout = out, stderr = devnull))
    return ok, String(take!(out))
end

"Defined dynamic symbols of an ELF shared object (empty when it is not one)."
function defined_symbols(path::AbstractString)
    ok, out = sh(`nm -D --defined-only $path`)
    ok || return Set{String}()
    syms = Set{String}()
    for line in split(out, '\n')
        f = split(strip(line))
        length(f) == 3 || continue
        # Weak symbols are optional by definition, so a missing one can never break a
        # consumer; absolute ones are linker artifacts - measured on the XZ artifact,
        # `XZ_5.1.2alpha` is type `A`, a version node.  Both were reported as missing API
        # by the first sweep.
        f[2] in ("A", "W", "V", "w", "v", "U") && continue
        # nm prints `symbol@@VERSION` (and `symbol@VERSION` for a single one): the version
        # tag is a property of the build, not a different symbol.  Without this, libpng
        # reported one "missing" symbol that was only `PNG16_0@@PNG16_0`.
        push!(syms, replace(f[3], r"@.*$" => ""))
    end
    return syms
end

# Linker bookkeeping, not API.  Measured on the official artifacts: every one of them
# exports `__bss_end__`, `__bss_start__`, `__end__`, `_bss_end__` as type `B`, and Termux's
# builds do not - so only a name filter stops those four from turning ten libraries into
# false `needs-jll` verdicts.  The first sweep did exactly that; this is the fix.
const ELF_BOOKKEEPING = r"^_+(bss_start|bss_end|end|edata|data_start|init|fini|dso_handle|TMC_END__|IO_stdin_used|gmon_start__|ITM_.*|cxa_.*|libc_csu_.*|dl_relocate_static_pie|stack_chk.*)_*$"

# A version node (`PNG16_0`, `GLIBC_2.17`, `XZ_5.1.2alpha`) names a version script entry,
# not something a consumer can call: libpng's artifact exports one, and counting it made the
# verdict look like a missing API symbol when the build was fine.
const VERSION_NODE = r"^[A-Za-z_][A-Za-z0-9_]*_[0-9]+(\.[0-9]+)*[A-Za-z]*$"

"The symbols a consumer could actually call: the artifact's, minus the bookkeeping."
api_symbols(syms) = Set{String}(s for s in syms if !occursin(ELF_BOOKKEEPING, s) && !occursin(VERSION_NODE, s))

"""
True when the system library defines the symbol but does not export it dynamically.

The difference matters for the fix: a symbol the build *lacks* means a different feature set
(rebuild or shim), while one it merely *hides* - Termux builds with a version script or
-fvisibility=hidden - means the same source compiled with a smaller export surface, and the
answer is to make the system export it.  Measured on fontconfig: `default_langs` is in
Termux's libfontconfig but not in its dynamic table, and that single data symbol is what
keeps the whole Cairo stack from being overridable.  Inconclusive when the library is
stripped, which is common in Termux packages.
"""
function hidden_in_system(path::AbstractString, sym::String)
    ok, out = sh(`nm --defined-only $path`)
    ok || return false
    for line in split(out, '\n')
        f = split(strip(line))
        length(f) == 3 || continue
        replace(f[3], r"@.*$" => "") == sym && return true
    end
    return false
end

"SONAME of an ELF shared object, or \"\" when it has none."
function soname(path::AbstractString)
    ok, out = sh(`readelf -d $path`)
    ok || return ""
    m = match(r"SONAME\)[^\[]*\[(.*?)\]", out)
    return m === nothing ? "" : m.captures[1]
end

"Directory size in kB, the way `du` would report it."
function dir_kb(path::AbstractString)
    ok, out = sh(`du -sk $path`)
    ok || return 0
    m = match(r"^(\d+)", strip(out))
    return m === nothing ? 0 : parse(Int, m.captures[1])
end

"""
Products a JLL declares, read from the wrapper sources.  Returns the wrapper that best
matches the artifact on disk and a name => (kind, soname, relpath) map.
"""
function declared_products(jll_dir::AbstractString, artifact_dir::AbstractString)
    wrappers = joinpath(jll_dir, "src", "wrappers")
    isdir(wrappers) || return (nothing, Dict{String,NamedTuple}())
    best_name, best_prods, best_score = nothing, Dict{String,NamedTuple}(), -1
    for f in sort(readdir(wrappers; join = true))
        endswith(f, ".jl") || continue
        txt = read(f, String)
        prods = Dict{String,NamedTuple}()
        for (kind, re) in (("lib", r"@declare_library_product\(\s*([A-Za-z0-9_]+)\s*,\s*\"([^\"]*)\""),
                           ("exe", r"@declare_executable_product\(\s*([A-Za-z0-9_]+)\s*\)"),
                           ("file", r"@declare_file_product\(\s*([A-Za-z0-9_]+)\s*\)"))
            for m in eachmatch(re, txt)
                name = m.captures[1]
                son = length(m.captures) > 1 ? m.captures[2] : ""
                prods[name] = (kind = kind, soname = son,
                               relpath = get(prods, name, (kind = kind, soname = "", relpath = "")).relpath)
            end
        end
        for m in eachmatch(r"@init_library_product\(\s*([A-Za-z0-9_]+)\s*,\s*\"([^\"]*)\"", txt)
            name = m.captures[1]
            prods[name] = (kind = get(prods, name, (kind = "lib", soname = "", relpath = "")).kind,
                           soname = get(prods, name, (kind = "lib", soname = "", relpath = "")).soname,
                           relpath = m.captures[2])
        end
        for m in eachmatch(r"@init_(?:executable|file)_product\(\s*([A-Za-z0-9_]+)\s*,\s*\"([^\"]*)\"", txt)
            name = m.captures[1]
            prods[name] = (kind = get(prods, name, (kind = "file", soname = "", relpath = "")).kind,
                           soname = "", relpath = m.captures[2])
        end
        isempty(prods) && continue
        # The wrapper for this platform is the one whose files are in the artifact.
        score = count(p -> ispath(joinpath(artifact_dir, p.relpath)), values(prods))
        if score > best_score
            best_name, best_prods, best_score = basename(f), prods, score
        end
    end
    return (best_name, best_prods)
end

"True when the JLL is one of upstream's source-build stubs: dlopen by soname, no artifact."
function is_stub(jll_dir::AbstractString, jll::String)
    f = joinpath(jll_dir, "src", "$(jll).jl")
    return isfile(f) && occursin("dummy stub", read(f, String))
end

"""
Products a stub declares: the soname constants of its non-Windows/non-Apple branch.  The
stub never names an artifact path - `dlopen` gets the soname and the loader resolves it
against the system, which is upstream's design for a source-built Julia (USE_BINARYBUILDER=0).
"""
function stub_products(jll_dir::AbstractString, jll::String)
    f = joinpath(jll_dir, "src", "$(jll).jl")
    prods = Dict{String,NamedTuple}()
    for m in eachmatch(r"const\s+([A-Za-z0-9_]+)\s*=\s*\"([^\"]*\.so[^\"]*)\"", read(f, String))
        prods[m.captures[1]] = (kind = "soname", soname = m.captures[2], relpath = m.captures[2])
    end
    return prods
end

# Where the loader looks for a bare soname on this port.  $PREFIX/lib/julia is where the
# recipe's alias mechanism puts the versioned names Termux does not ship (libgmp.so.10 →
# libgmp.so), so a soname found there is a name the port created, not one Termux ships.
const SONAME_DIRS = [joinpath(PREFIX, "lib"), joinpath(PREFIX, "lib", "julia"), "/system/lib64"]

const VERDICT_LABEL = Dict(
    :override => "override",
    :override_needs_alias => "override-needs-alias",
    :needs_jll_absent => "needs-jll (absent lib)",
    :needs_jll_exe => "needs-jll (absent exe)",
    :needs_jll_gap => "needs-jll (gap)",
    :system_stub => "system-stub",
    :needs_alias => "needs-alias",
    :no_artifact => "no-artifact",
    :no_products => "no-products",
    :error => "error",
)

"Everything one classification learned, so a sweep can aggregate instead of re-reading logs."
struct Finding
    jll::String
    uuid::String                             # the JLL's uuid: what the stable override is keyed by
    verdict::Symbol
    artifacts::Vector{Tuple{String,String}}  # (name, git-tree-sha1) of the official artifact
    kb::Int                                  # its size on disk: the duplication this JLL costs
    products::Vector{String}
    absent::Vector{String}                   # declared products the system root does not have
    gaps::Dict{String,Vector{String}}        # product -> API symbols the system build lacks
    sonames::Dict{String,String}             # product -> soname missing next to the system lib
    note::String
end

empty_finding(jll, verdict, note) = Finding(jll, "", verdict, Tuple{String,String}[], 0, String[],
    String[], Dict{String,Vector{String}}(), Dict{String,String}(), note)

"""
Classify one JLL.  With `env` the caller owns the environment (the sweep installs a whole
stack once); without it a throwaway one is made, which is what a single-JLL run wants.
"""
function classify(jll::String; env::Union{Nothing,String} = nothing)
    println("\n=== $jll ===")
    if env === nothing
        env = mktempdir()
        Pkg.activate(env; io = devnull)
        try
            Pkg.add(jll; io = devnull)
        catch err
            println("  COULD NOT INSTALL: ", first(sprint(showerror, err), 200))
            return empty_finding(jll, :error, "install failed")
        end
    end
    pkgid = Base.identify_package(jll)
    # Not Pkg.dependencies()[pkgid]: that reflects a manifest snapshot this process may
    # have cached before the add.  find_package() reads the active environment's manifest
    # and hands back the entry file, so two dirnames give the package directory.
    entry = Base.find_package(jll)
    if entry === nothing
        println("  could not locate $jll on the load path")
        return empty_finding(jll, :error, "not on the load path")
    end
    jll_dir = dirname(dirname(entry))

    # A stdlib JLL from a source-built Julia is a stub: no artifact is ever used, and the
    # question is only whether the system answers the sonames it asks for.  Those are the
    # 22 stdlibs this port already resolves without downloading anything - measured:
    # GMP_jll.libgmp_path = $PREFIX/lib/libgmp.so, Zlib_jll.libz_path =
    # $PREFIX/lib/libz.so.1.3.2, artifact_dir = $PREFIX.
    if is_stub(jll_dir, jll)
        prods = stub_products(jll_dir, jll)
        println("  stdlib stub (upstream's source-build design): dlopen by soname, no artifact")
        if isempty(prods)
            println("  could not read its sonames")
            return empty_finding(jll, :error, "stub without sonames")
        end
        f = empty_finding(jll, :system_stub, "stdlib stub: dlopen by soname, no artifact")
        f = Finding(f.jll, pkgid.uuid === nothing ? "" : string(pkgid.uuid), f.verdict,
                    f.artifacts, f.kb, sort(collect(keys(prods))), f.absent,
                    f.gaps, f.sonames, f.note)
        for name in sort(collect(keys(prods)))
            son = prods[name].soname
            found = findfirst(d -> ispath(joinpath(d, son)), SONAME_DIRS)
            if found === nothing
                println("  MISSING  $name wants $son, which nothing answers")
                f = Finding(f.jll, f.uuid, :needs_alias, f.artifacts, f.kb, f.products, f.absent,
                            f.gaps, f.sonames, "a stub whose soname nothing answers")
            else
                dir = SONAME_DIRS[found]
                note = dir == joinpath(PREFIX, "lib", "julia") ? "  <- created by the recipe's alias mechanism" : ""
                println("  $(rpad(name, 16)) $son  answered by $dir$note")
            end
        end
        println("  => verdict: ", VERDICT_LABEL[f.verdict])
        return f
    end
    # find_artifacts_toml only looks for Artifacts.toml, and every *stdlib* JLL (Zlib,
    # GMP, MPFR, OpenSSL, LibCURL, LibGit2, OpenBLAS …) keeps its metadata in
    # StdlibArtifacts.toml instead, so it is checked here by name.  Those stdlibs are the
    # ones this port already resolves without downloading anything, so mis-reading them
    # as "ships no artifact" would have hidden the comparison that matters most.
    at = Pkg.Artifacts.find_artifacts_toml(jll_dir)
    if at === nothing
        candidate = joinpath(jll_dir, "StdlibArtifacts.toml")
        isfile(candidate) && (at = candidate)
    end
    if at === nothing
        println("  no Artifacts.toml: this JLL ships no artifact")
        return empty_finding(jll, :no_artifact, "no Artifacts.toml")
    end
    is_stdlib = basename(at) == "StdlibArtifacts.toml"
    is_stdlib && println("  stdlib JLL with artifact metadata (not a stub: it does use one)")

    host = HostPlatform()
    selected = Artifacts.select_downloadable_artifacts(at; platform = host, pkg_uuid = pkgid.uuid)
    if isempty(selected)
        println("  no artifact matches $host: the JLL cannot be used here at all")
        println("  => verdict: no-artifact (an override is not optional, it is the only way in)")
        return empty_finding(jll, :no_artifact, "no artifact matches $(host)")
    end

    artifacts = Tuple{String,String}[]
    kb = 0
    artifact_dir = nothing
    for (name, meta) in selected
        hash = Base.SHA1(meta["git-tree-sha1"])
        dir = Artifacts.artifact_path(hash)
        if !isdir(dir)
            try
                Pkg.Artifacts.ensure_artifact_installed(name, meta, at; platform = host, io = devnull)
                dir = Artifacts.artifact_path(hash)
            catch err
                println("  could not install artifact '$name': ", first(sprint(showerror, err), 120))
                continue
            end
        end
        push!(artifacts, (name, meta["git-tree-sha1"]))
        kb += dir_kb(dir)
        println("  artifact '$name'  hash $(meta["git-tree-sha1"][1:12])…  $(dir_kb(dir)) kB")
        artifact_dir === nothing && (artifact_dir = dir)
    end
    artifact_dir === nothing && (println("  no artifact on disk"); return empty_finding(jll, :error, "no artifact on disk"))

    wrapper, prods = declared_products(jll_dir, artifact_dir)
    if isempty(prods)
        println("  the JLL declares no product")
        return empty_finding(jll, :no_products, "no declared products")
    end
    println("  wrapper: $wrapper   products: $(join(sort(collect(keys(prods))), ", "))")

    absent, absent_libs, gaps, sonames = String[], String[], Dict{String,Vector{String}}(), Dict{String,String}()
    for name in sort(collect(keys(prods)))
        p = prods[name]
        art = joinpath(artifact_dir, p.relpath)
        sys = joinpath(PREFIX, p.relpath)
        if !isfile(sys)
            # The kind decides the verdict, not just the message: a missing *library* means
            # the JLL cannot be satisfied, while a missing executable or static file leaves
            # the shared library perfectly overridable - the first sweep called all three
            # `absent` and hid that difference (JpegTurbo's cjpeg/djpeg/jpegtran, Expat's
            # xmlwf, XZ's liblzma.a).
            println("  MISSING  $name ($(p.kind)): the system root has no $(p.relpath)")
            println("           (is the Termux package that provides it installed?)")
            push!(absent, "$name ($(p.kind))")
            p.kind == "lib" && push!(absent_libs, name)
            continue
        end
        # The SONAME is what a dlopen by name asks for, and the JLL declares it: the
        # consumer gets the name, not the path.
        art_soname = isempty(p.soname) ? soname(art) : p.soname
        soname_ok = isempty(art_soname) || isfile(joinpath(dirname(sys), art_soname))
        syms_art = p.kind == "lib" ? api_symbols(defined_symbols(art)) : Set{String}()
        syms_sys = p.kind == "lib" ? api_symbols(defined_symbols(sys)) : Set{String}()
        gap = sort!(collect(setdiff(syms_art, syms_sys)))
        # The two kinds of gap are not the same decision.  A missing name is answered by a
        # symlink - which is what julia-termux's needed-library-aliases.sh already does for
        # its own libs - while a missing symbol means this build is a different feature set
        # and no name will conjure it.
        isempty(gap) || (gaps[name] = gap)
        (!isempty(gap) || soname_ok) || (sonames[name] = art_soname)
        println("  $(rpad(name, 16)) $(p.kind)  $(p.relpath)")
        println("      system   $(dir_kb(sys)) kB")
        if !soname_ok
            # Cheap to close and worth saying so: the consumer asks the loader for the
            # soname, not the path, and a symlink answers that - which is the same shape
            # as needed-library-aliases.sh in julia-termux.
            println("      soname   $art_soname ABSENT next to it  <- a symlink would answer this")
        elseif !isempty(art_soname)
            println("      soname   $art_soname resolves")
        end
        if p.kind == "lib"
            println("      symbols  official $(length(syms_art)), system $(length(syms_sys)), missing $(length(gap))")
            if !isempty(gap) && SHOW > 0
                println("      missing  ", join(gap[1:min(end, SHOW)], ", "),
                        length(gap) > SHOW ? " …" : "")
                hidden = filter(s -> hidden_in_system(sys, s), gap)
                isempty(hidden) ||
                    println("      hidden   $(length(hidden)) of them are in the system build but not exported: ",
                            join(hidden[1:min(end, SHOW)], ", "))
            end
        end
    end

    # The verdict is read off the collected evidence at the end, in order of how hard it is
    # to answer: a symbol the system build does not export cannot be conjured (Yggdrasil or
    # a shim); a missing library is a package question; a missing program leaves the library
    # overridable but the JLL's __init__ still checks it; a missing name is a symlink.
    verdict = if !isempty(gaps)
        :needs_jll_gap
    elseif !isempty(absent_libs)
        :needs_jll_absent
    elseif !isempty(absent)
        :needs_jll_exe
    elseif !isempty(sonames)
        :override_needs_alias
    else
        :override
    end

    note = verdict === :needs_jll_gap ?
        "the system build exports less API: $(sum(length, values(gaps))) symbols" :
        verdict === :needs_jll_absent ? "the system root lacks the libraries: $(join(absent_libs, ", "))" :
        verdict === :needs_jll_exe ? "the library is fine; the system root lacks $(join(absent, ", "))" :
        verdict === :override_needs_alias ? "missing names: $(join(keys(sonames), ", "))" :
        "the system satisfies every declared product"
    f = Finding(jll, pkgid.uuid === nothing ? "" : string(pkgid.uuid), verdict, artifacts, kb,
                sort(collect(keys(prods))), absent, gaps, sonames, note)
    println("  => verdict: ", VERDICT_LABEL[verdict])
    if verdict in (:override, :override_needs_alias)
        # The stable form: keyed by the JLL's uuid and the artifact name, so it survives the
        # JLL being updated.  It needs the patched Pkg julia-termux ships (docs/14) - without
        # it Pkg loses the uuid on the download path and fetches the artifact anyway.
        for (aname, hash) in artifacts
            println("     Overrides.toml: [$(pkgid.uuid)]  $aname = \"$PREFIX\"    (hash $hash)")
        end
    elseif verdict === :override_needs_alias
        println("     the system has the API; create the missing names (a symlink each) and then the line above")
    end
    return f
end

println("classify-jll.jl — prefix $PREFIX")
println("host: $(HostPlatform())")

findings = Finding[]
if isempty(JLLS)
    println("\nno JLL given: see --sweep")
else
    # One environment for the whole sweep: N JLLs, one resolve.  A JLL that fails to
    # resolve as part of the batch is retried alone, so one bad entry does not cost the run.
    env = mktempdir()
    Pkg.activate(env; io = devnull)
    if length(JLLS) > 1
        println("\ninstalling $(length(JLLS)) JLLs into one environment…")
        try
            Pkg.add(JLLS; io = devnull)
        catch err
            println("  the batch add failed (", first(sprint(showerror, err), 120), "); retrying one by one")
        end
        for jll in JLLS
            Base.find_package(jll) === nothing || continue
            try
                Pkg.add(jll; io = devnull)
            catch err
                println("  could not add $jll on its own: ", first(sprint(showerror, err), 120))
            end
        end
    end
    for jll in JLLS
        push!(findings, classify(jll; env = env))
    end
end

println("\n=== summary ===")
counts = Dict{Symbol,Int}()
for f in findings
    counts[f.verdict] = get(counts, f.verdict, 0) + 1
end
for (v, n) in sort!(collect(counts); by = first)
    println("  $(rpad(VERDICT_LABEL[v], 22)) $n")
end

if !isempty(findings)
    duplicated = sum(f -> f.kb, findings; init = 0)
    println("\n  official artifacts on disk for these JLLs: $(round(duplicated / 1024, digits = 1)) MB")
    println("  (that is the duplication today: every one of them is downloaded and none of them loads)")

    free = [f for f in findings if f.verdict in (:override, :override_needs_alias)]
    stub = [f for f in findings if f.verdict in (:system_stub, :needs_alias)]
    absent = [f for f in findings if f.verdict === :needs_jll_absent]
    exe = [f for f in findings if f.verdict === :needs_jll_exe]
    gap = [f for f in findings if f.verdict === :needs_jll_gap]

    if !isempty(stub)
        println("\n  already resolved by the port's stdlib stubs: ", join(getfield.(stub, :jll), ", "))
    end
    if !isempty(free)
        println("\n  free win — one Overrides.toml line each, nothing to build: ", join(getfield.(free, :jll), ", "))
        println("  # ~/.julia/artifacts/Overrides.toml  (stable form: needs the patched Pkg)")
        for f in free
            for (aname, _) in f.artifacts
                println("  [$(f.uuid)]\n  $aname = \"$PREFIX\"    # $(f.jll)")
            end
        end
    end
    if !isempty(absent)
        println("\n  system root lacks the library (check whether Termux packages it): ",
                join(getfield.(absent, :jll), ", "))
    end
    if !isempty(exe)
        println("\n  library satisfied, but the JLL also declares programs the system lacks: ",
                join(getfield.(exe, :jll), ", "))
        for f in exe
            println("    $(f.jll): $(f.note)")
        end
    end
    if !isempty(gap)
        println("\n  Yggdrasil's job — the system build exports less API: ", join(getfield.(gap, :jll), ", "))
        for f in gap
            println("    $(f.jll): $(f.note)")
        end
    end
end

if MARKDOWN && !isempty(findings)
    println("\n=== markdown ===")
    println("| JLL | verdict | products | official artifact | missing |")
    println("|---|---|---|---|---|")
    for f in findings
        missing = if !isempty(f.gaps)
            n = sum(length, values(f.gaps))
            # Two symbols as a taste, not the whole list: the first sweep printed all 235
            # of FFTW's into one table cell.
            example = first(values(f.gaps))
            "$n symbols ($(join(example[1:min(2, length(example))], ", "))…)"
        elseif !isempty(f.absent)
            "products absent: $(join(f.absent, ", "))"
        elseif !isempty(f.sonames)
            "names: $(join(collect(keys(f.sonames)), ", "))"
        else
            "—"
        end
        println("| `$(f.jll)` | $(VERDICT_LABEL[f.verdict]) | $(join(f.products, ", ")) | " *
                "$(round(f.kb / 1024, digits = 1)) MB | $missing |")
    end
end

println()
println("override              the system satisfies the JLL: an Overrides.toml line stops the download")
println("override-needs-alias  same, plus a name to create (a symlink answers it)")
println("needs-jll (absent lib)  a declared *library* is not in the system root: pkg install, or Yggdrasil")
println("needs-jll (absent exe)  the library is fine, but the JLL also declares a program/file the system lacks")
println("needs-jll (gap)       the system's build exports less API than the official one: Yggdrasil or a shim")
println("system-stub           stdlib stub: already resolves to the system, downloads nothing")
println("needs-alias           a stub whose soname nothing answers (a symlink fixes it)")

exit(any(f -> f.verdict === :error, findings) ? 1 : 0)
