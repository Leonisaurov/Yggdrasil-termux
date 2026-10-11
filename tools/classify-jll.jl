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
#   julia classify-jll.jl [--prefix DIR] [--show-symbols N] JLL [JLL ...]
#
# Verdicts:
#   override            every product exists, its SONAME resolves, no missing symbols
#   override-with-gaps  products exist but the official build exports symbols this build
#                       does not: the consumer may need them (this is FFTW)
#   needs-jll           a declared product is missing from the system root
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
    jlls = String[]
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--prefix" && i < length(args)
            prefix = args[i + 1]; i += 2
        elseif a == "--show-symbols" && i < length(args)
            show_symbols = parse(Int, args[i + 1]); i += 2
        else
            push!(jlls, a); i += 1
        end
    end
    return prefix, show_symbols, jlls
end

const PREFIX, SHOW, JLLS = parse_args(ARGS)

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
        # nm prints `symbol@@VERSION` (and `symbol@VERSION` for a single one): the version
        # tag is a property of the build, not a different symbol.  Without this, libpng
        # reported one "missing" symbol that was only `PNG16_0@@PNG16_0`.
        length(f) == 3 && push!(syms, replace(f[3], r"@.*$" => ""))
    end
    return syms
end

# Linker and C-runtime bookkeeping, not API: every build has its own set of these, and
# comparing them says nothing about whether a consumer would find what it asks for.  It
# was 5 of the 240 symbols FFTW's artifact showed as "missing" the first time this ran.
const ELF_BOOKKEEPING = Set(["__bss_start", "_edata", "_end", "_fini", "_init",
    "__gmon_start__", "_ITM_deregisterTMCloneTable", "_ITM_registerTMCloneTable",
    "__cxa_finalize", "__libc_csu_fini", "__libc_csu_init", "_dl_relocate_static_pie"])

# A version node (`PNG16_0`, `GLIBC_2.17`) is the name of a version script entry, not
# something a consumer can call: libpng's artifact exports one, and counting it made the
# verdict look like a missing API symbol when the build was fine.
const VERSION_NODE = r"^[A-Za-z_][A-Za-z0-9_]*_[0-9]+(\.[0-9]+)*$"

"The symbols a consumer could actually call: the artifact's, minus the bookkeeping."
api_symbols(syms) = Set{String}(s for s in syms if !(s in ELF_BOOKKEEPING) && !occursin(VERSION_NODE, s))

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

function classify(jll::String)
    println("\n=== $jll ===")
    env = mktempdir()
    Pkg.activate(env; io = devnull)
    try
        Pkg.add(jll; io = devnull)
    catch err
        println("  COULD NOT INSTALL: ", first(sprint(showerror, err), 200))
        return :error
    end
    pkgid = Base.identify_package(jll)
    # Not Pkg.dependencies()[pkgid]: that reflects a manifest snapshot this process may
    # have cached before the add.  find_package() reads the active environment's manifest
    # and hands back the entry file, so two dirnames give the package directory.
    entry = Base.find_package(jll)
    if entry === nothing
        println("  could not locate $jll on the load path")
        return :error
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
            return :error
        end
        verdict = :system_stub
        for name in sort(collect(keys(prods)))
            son = prods[name].soname
            found = findfirst(d -> ispath(joinpath(d, son)), SONAME_DIRS)
            if found === nothing
                println("  MISSING  $name wants $son, which nothing answers")
                verdict = :needs_alias
            else
                dir = SONAME_DIRS[found]
                note = dir == joinpath(PREFIX, "lib", "julia") ? "  <- created by the recipe's alias mechanism" : ""
                println("  $(rpad(name, 16)) $son  answered by $dir$note")
            end
        end
        println("  => verdict: ", verdict === :system_stub ? "system-stub" : "needs-alias")
        return verdict
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
        return :no_artifact
    end
    is_stdlib = basename(at) == "StdlibArtifacts.toml"
    is_stdlib && println("  stdlib JLL with artifact metadata (not a stub: it does use one)")

    host = HostPlatform()
    selected = Artifacts.select_downloadable_artifacts(at; platform = host, pkg_uuid = pkgid.uuid)
    if isempty(selected)
        println("  no artifact matches $host: the JLL cannot be used here at all")
        println("  => verdict: no-artifact (an override is not optional, it is the only way in)")
        return :no_artifact
    end

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
        println("  artifact '$name'  hash $(meta["git-tree-sha1"][1:12])…  $(dir_kb(dir)) kB")
        artifact_dir === nothing && (artifact_dir = dir)
    end
    artifact_dir === nothing && (println("  no artifact on disk"); return :error)

    wrapper, prods = declared_products(jll_dir, artifact_dir)
    if isempty(prods)
        println("  the JLL declares no product")
        return :no_products
    end
    println("  wrapper: $wrapper   products: $(join(sort(collect(keys(prods))), ", "))")

    verdict = :override
    for name in sort(collect(keys(prods)))
        p = prods[name]
        art = joinpath(artifact_dir, p.relpath)
        sys = joinpath(PREFIX, p.relpath)
        if !isfile(sys)
            println("  MISSING  $name ($(p.kind)): the system root has no $(p.relpath)")
            println("           (is the Termux package that provides it installed?)")
            verdict = :needs_jll
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
        if !isempty(gap)
            verdict == :override && (verdict = :needs_jll)
        elseif !soname_ok
            verdict in (:override, :needs_jll) && (verdict = :override_needs_alias)
        end
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
            end
        end
    end

    label = verdict === :override ? "override" :
            verdict === :override_needs_alias ? "override-needs-alias" :
            verdict === :override_gaps ? "override-with-gaps" : "needs-jll"
    println("  => verdict: $label")
    if verdict === :override
        for (_, meta) in selected
            println("     Overrides.toml: \"$(meta["git-tree-sha1"])\" = \"$PREFIX\"")
        end
    elseif verdict === :override_needs_alias
        println("     the system has the API; create the missing names (a symlink each) and then:")
        for (_, meta) in selected
            println("     Overrides.toml: \"$(meta["git-tree-sha1"])\" = \"$PREFIX\"")
        end
    end
    return verdict
end

println("classify-jll.jl — prefix $PREFIX")
println("host: $(HostPlatform())")
counts = Dict{Symbol,Int}()
for jll in JLLS
    v = classify(jll)
    counts[v] = get(counts, v, 0) + 1
end

println("\n=== summary ===")
for (v, n) in sort!(collect(counts); by = first)
    println("  $(rpad(String(v), 18)) $n")
end
println()
println("override            the system satisfies the JLL: an Overrides.toml line stops the download")
println("override-needs-alias  same, plus a name to create (a symlink answers it)")
println("needs-jll           the system's build exports less API than the official one: Yggdrasil or a shim")
println("system-stub         stdlib stub: already resolves to the system, downloads nothing")
println("needs-alias         a stub whose soname nothing answers (a symlink fixes it)")
