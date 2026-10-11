#!/data/data/com.termux/files/usr/bin/bash
# Names the system does not ship, which a JLL's declared SONAME asks for.
#
# Same shape as julia-termux's packages/julia/needed-library-aliases.sh: the consumer asks the
# loader for the SONAME, not for the path, so a symlink next to the library answers it.  Each
# one is here because classify-jll.jl reported `override-needs-alias` and named it, and the
# override in termux-overrides.toml is what then uses it.
#
# Idempotent: safe to re-run.
set -eu

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"

link() {
	local name="$1" target="$2"
	if [ -e "$PREFIX/lib/$name" ]; then
		echo "  ok    $name already exists"
	else
		ln -sfn "$target" "$PREFIX/lib/$name"
		echo "  made  $PREFIX/lib/$name -> $target"
	fi
}

# libpng_jll declares libpng16.so.16; Termux ships libpng16.so (measured: 240/240 symbols match).
link libpng16.so.16 libpng16.so

# FriBidi_jll declares libfribidi.so.0; Termux ships libfribidi.so.  Revealed by Cairo.jl,
# whose closure reaches Pango_jll -> FriBidi_jll.
link libfribidi.so.0 libfribidi.so

echo "done"
