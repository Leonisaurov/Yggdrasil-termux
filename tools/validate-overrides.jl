#!/data/data/com.termux/files/usr/bin/julia
#
# validate-overrides.jl — does `using Foo_jll` actually resolve into $PREFIX?
#
# classify-jll.jl answers whether an override *should* work by comparing symbol surfaces.
# This answers whether it *does*: it loads the JLL (which runs JLLWrappers' generated
# __init__, the code that dlopens every library product and checks every executable) and
# asserts that each `<product>_path` binding points into $PREFIX.  A verdict is not a
# result until a real run says so - libpng's override was validated this way before the
# table in docs/14 was written, and every row of the sweep's "free win" list goes through
# here before docs/15 claims it.
#
# It also counts the artifact directories in the depot before and after: a JLL whose
# override is missing or wrong downloads its glibc artifact, which is the duplication the
# override exists to avoid, and that shows up here as a new directory.
#
# Usage:
#   julia validate-overrides.jl [--prefix DIR] JLL [JLL ...]
#   julia validate-overrides.jl --list tools/jlls-overrides.txt
#
# Run it against the *real* depot (the one holding ~/.julia/artifacts/Overrides.toml): the
# point is to test the overrides as installed.  Exit status is 0 only if every JLL loaded
# and every product resolved into the prefix.

using Pkg

function parse_args(args)
    prefix = get(ENV, "PREFIX", "/data/data/com.termux/files/usr")
    jlls = String[]
    list = nothing
    # A local JLLWrappers to develop into the temp environment before adding the JLLs.  Used to
    # test patches/JLLWrappers-bionic-fallback.patch on the device: with it, a bionic host with no
    # bionic wrapper falls back to the -gnu one instead of leaving every product undefined.
    jllwrappers = nothing
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--prefix" && i < length(args)
            prefix = args[i + 1]; i += 2
        elseif a == "--list" && i < length(args)
            list = args[i + 1]; i += 2
        elseif a == "--jllwrappers" && i < length(args)
            jllwrappers = args[i + 1]; i += 2
        else
            push!(jlls, a); i += 1
        end
    end
    if list !== nothing
        for line in eachline(list)
            s = strip(line)
            (isempty(s) || startswith(s, "#")) && continue
            push!(jlls, split(s)[1])
        end
    end
    return prefix, jllwrappers, jlls
end

const PREFIX, JLLWRAPPERS, JLLS = parse_args(ARGS)

# The artifact directories of the first depot in the path - where Overrides.toml lives and
# where a download would land.
const ARTIFACTS = joinpath(first(DEPOT_PATH), "artifacts")
artifact_dirs() = isdir(ARTIFACTS) ? Set(readdir(ARTIFACTS)) : Set{String}()

# PASS means "this product did not come from a downloaded artifact", not "it is under
# $PREFIX": FFTW's override points at ~/.local/opt/fftw-bionic, a bionic artifact built for
# this port because the system's fftw cannot satisfy the JLL (docs/14 14.1).  What the
# override exists to prevent is the glibc artifact in the depot, so that is the criterion.
is_artifact_path(p) = startswith(p, ARTIFACTS * "/")

"""
The `<product>_path` bindings of a loaded JLL module: what JLLWrappers' __init__ computed.
Executables and files have them too, so a missing program shows up here as well.

Everything runs inside `invokelatest`: the `using` above creates the binding in a newer
world age than this script's, and reading it directly fails with "The binding may be too
new: running in world age N, while current world is N+5" (measured, first run).
"""
function product_paths(modname::Symbol)
    return Base.invokelatest() do
        mod = getfield(Main, modname)
        out = Pair{String,String}[]
        for n in names(mod; all = true)
            s = String(n)
            endswith(s, "_path") || continue
            v = try
                getfield(mod, n)
            catch
                continue
            end
            v isa AbstractString && push!(out, s => v)
        end
        return sort(out; by = first)
    end
end

println("validate-overrides.jl — prefix $PREFIX")
println("depot: $(first(DEPOT_PATH))")
before = artifact_dirs()
println("artifact directories before: $(length(before))")

env = mktempdir()
Pkg.activate(env; io = devnull)
if JLLWRAPPERS !== nothing
    println("developing a local JLLWrappers: ", JLLWRAPPERS)
    Pkg.develop(path = JLLWRAPPERS; io = devnull)
end
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

failures = String[]
for jll in JLLS
    println("\n=== $jll ===")
    if Base.find_package(jll) === nothing
        println("  not installed: cannot validate")
        push!(failures, "$jll: not installed")
        continue
    end
    # `using` runs the generated __init__: a wrong override (or a missing program) throws
    # an InitError here, which is exactly the failure this is meant to catch.
    try
        Base.eval(Main, Meta.parse("using $jll"))
    catch err
        println("  LOAD FAILED: ", first(sprint(showerror, err), 300))
        push!(failures, "$jll: load failed")
        continue
    end
    paths = product_paths(Symbol(jll))
    if isempty(paths)
        println("  the module exposes no *_path binding")
        push!(failures, "$jll: no product paths")
        continue
    end
    from_artifact = filter(p -> is_artifact_path(last(p)), paths)
    for (n, p) in paths
        mark = is_artifact_path(p) ? "!!" : "  "
        println("  $mark $(rpad(n, 24)) $p")
    end
    if isempty(from_artifact)
        println("  PASS  every product resolves outside the depot's artifacts (nothing downloaded)")
    else
        println("  FAIL  $(length(from_artifact)) product(s) came from a downloaded artifact: ",
                join(first.(from_artifact), ", "))
        push!(failures, "$jll: $(length(from_artifact)) product(s) from an artifact")
    end
end

after = artifact_dirs()
new_dirs = setdiff(after, before)
println("\n=== summary ===")
println("  validated: $(length(JLLS) - length(failures)) / $(length(JLLS))")
println("  artifact directories after: $(length(after)) ($(length(new_dirs)) new)")
if !isempty(new_dirs)
    # Not automatically a failure - a JLL outside the override table legitimately downloads -
    # but for the JLLs being validated it is the duplication this port exists to remove.
    println("  downloaded during validation (the override did not take):")
    for d in sort(collect(new_dirs))
        println("    ", d)
    end
end
if !isempty(failures)
    println("\n  failures:")
    for f in failures
        println("    ", f)
    end
end

exit(isempty(failures) ? 0 : 1)
