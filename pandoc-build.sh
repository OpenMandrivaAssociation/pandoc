#!/bin/bash
# Build pandoc 3.11 with packaged ghc98 (GHC 9.8.4) and cabal-install 3.12.1.0.
# Sources and the Hackage cache are vendored. This script does not run
# cabal update and does not fetch. cabal 3.12 treats every RepoTarballPackage
# as a download when --offline is set, even if the tarball is already in the
# cache (Cabal-7125), so the build does not pass --offline. Proxies point at
# a closed local port so a fetch cannot reach Hackage. The http flag is off.
# Markdown to HTML does not fetch remote resources.
set -euo pipefail

ROOT=${1:?usage: pandoc-build.sh ROOT}
WORK=$ROOT/work
TREE=$WORK/src/pandoc-3.11
PREFIX=$ROOT/dest
SRC=$ROOT/incoming/pandoc-3.11.tar.gz
CLI_SRC=$ROOT/incoming/pandoc-cli-3.11.tar.gz
VENDOR_TAR=$ROOT/incoming/pandoc-3.11-hackage.tar.gz
VENDOR=$WORK/hackage
FREEZE_SRC=$ROOT/incoming/pandoc-3.11.cabal.project.freeze
EXPECT_SHA=50a04f7e8b244491546c45e81a6e7a0263d7e8c46a776b80738d51294a79f8a8
CLI_SHA=a9f3fc8c64962c8778b379cc2238c7c554541e1e94fd36a210c3f92e1729e929
VENDOR_SHA=7a7f88b76e908c61f6354353cf1f17ed331ba574cb7eac99261c003b6ba52423
unset CFLAGS CXXFLAGS LDFLAGS CPPFLAGS RPM_OPT_FLAGS RPM_LD_FLAGS || true
export CABAL_DIR=$ROOT/work/cabal-dir
export TMPDIR=$ROOT/work/tmp
export TEMP=$TMPDIR
export TMP=$TMPDIR
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
# Closed proxy. cabal's HTTP client honours these. Nothing is listening.
export http_proxy=http://127.0.0.1:9
export https_proxy=http://127.0.0.1:9
export HTTP_PROXY=http://127.0.0.1:9
export HTTPS_PROXY=http://127.0.0.1:9
export all_proxy=http://127.0.0.1:9
export ALL_PROXY=http://127.0.0.1:9
unset LD_LIBRARY_PATH || true
unset GHC_PACKAGE_PATH || true

mkdir -p "$TMPDIR" "$WORK/logs" "$WORK/src" "$WORK/proof" "$WORK/bin" "$PREFIX/bin" "$CABAL_DIR"
phase() { printf 'PANDOC311PKG_PHASE %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
failed=0
fail() { failed=1; printf 'PANDOC311PKG_FAILED: %s\n' "$*"; exit 1; }
trap 'rc=$?; if [ "$rc" -ne 0 ] && [ "$failed" != 1 ]; then printf "PANDOC311PKG_FAILED: exit %s\n" "$rc"; fi' EXIT

clean=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v -e '\.ghcup' -e '\.cabal' -e '/ghc66-work/' -e '/ghc610-work/' -e '/ghc612-work/' -e '/ghc74-work/' -e '/ghc78-work/' -e '/ghc80-work/' -e '/ghc84-work/' -e '/ghc88-work/' -e '/ghc90-work/' -e '/ghc94-work/' -e '/ghc98-work/' -e '/ghc98-prefix' -e '/ghc912-work/' -e '/ghc914-work/' -e '/pandoc311-work/' -e '/pkg-extract-' | paste -sd: -)
export PATH="$clean"
hash -r
CABAL=$(command -v cabal || true)
GHC=$(command -v ghc98 || true)
[ -n "$CABAL" ] && [ -x "$CABAL" ] || fail "cabal missing"
[ -n "$GHC" ] && [ -x "$GHC" ] || fail "ghc98 missing"
command -v g++ >/dev/null || fail "g++ missing"
command -v ld.lld >/dev/null || fail "ld.lld missing"
CABAL=$(readlink -f "$CABAL")
GHC=$(readlink -f "$GHC")
export PATH="$(dirname "$CABAL"):$(dirname "$GHC"):$PATH"
hash -r
got=$(sha256sum "$SRC" | awk '{print $1}')
[ "$got" = "$EXPECT_SHA" ] || fail "pandoc tarball sha $got"
cli_got=$(sha256sum "$CLI_SRC" | awk '{print $1}')
[ "$cli_got" = "$CLI_SHA" ] || fail "pandoc-cli tarball sha $cli_got"
vendor_got=$(sha256sum "$VENDOR_TAR" | awk '{print $1}')
[ "$vendor_got" = "$VENDOR_SHA" ] || fail "hackage cache sha $vendor_got"
ver=$("$GHC" --numeric-version | tr -d '[:space:]')
[ "$ver" = "9.8.4" ] || fail "ghc is $ver"
cver=$("$CABAL" --numeric-version | tr -d '[:space:]')
[ "$cver" = "3.12.1.0" ] || fail "cabal is $cver"
[ -f "$FREEZE_SRC" ] || fail "freeze file missing"
# ghc98 --print-libdir is .../lib/ghc-9.8.4/lib. hsc2hs is the sibling
# bin, and that program does not find its template on its own. Cabal
# looks up the hsc2hs program by name; the package does not put it on PATH.
libdir=$("$GHC" --print-libdir)
hsc2hs=$(dirname "$libdir")/bin/hsc2hs
[ -x "$hsc2hs" ] || fail "hsc2hs missing: $hsc2hs"
[ -f "$libdir/template-hsc.h" ] || fail "hsc2hs template missing: $libdir/template-hsc.h"
cat > "$WORK/bin/hsc2hs" << EOF
#!/bin/sh
exec $(printf '%q' "$hsc2hs") --template=$(printf '%q' "$libdir/template-hsc.h") --lflag=-fuse-ld=lld "\$@" -I$(printf '%q' "$libdir/include/")
EOF
chmod 755 "$WORK/bin/hsc2hs"
export PATH="$WORK/bin:$PATH"
hash -r
command -v hsc2hs | grep -F -q "$WORK/bin/hsc2hs" || fail "PATH hsc2hs is $(command -v hsc2hs)"
phase "tools ghc $ver cabal $cver"
printf '%s\n' "$$" > "$WORK/build.pid"

if [ ! -f "$VENDOR/Glob/0.10.2/Glob-0.10.2.tar.gz" ]; then
	phase "unpack hackage cache"
	rm -rf "$VENDOR"
	mkdir -p "$VENDOR"
	tar -C "$VENDOR" -xzf "$VENDOR_TAR"
fi
# The source archive ships 01-index.tar.gz only. cabal reads 01-index.tar.
if [ ! -f "$VENDOR/01-index.tar" ]; then
	[ -f "$VENDOR/01-index.tar.gz" ] || fail "01-index.tar.gz missing"
	gzip -dc "$VENDOR/01-index.tar.gz" > "$VENDOR/01-index.tar.partial"
	mv "$VENDOR/01-index.tar.partial" "$VENDOR/01-index.tar"
fi
[ -f "$VENDOR/01-index.tar" ] || fail "vendored hackage index missing"

if [ ! -f "$TREE/pandoc.cabal" ]; then
	phase "unpack library"
	tar -C "$WORK/src" -xzf "$SRC"
fi
if [ ! -f "$WORK/src/pandoc-cli-3.11/pandoc-cli.cabal" ]; then
	phase "unpack cli"
	tar -C "$WORK/src" -xzf "$CLI_SRC"
fi
[ -f "$TREE/pandoc.cabal" ] || fail "library unpack failed"
[ -f "$WORK/src/pandoc-cli-3.11/pandoc-cli.cabal" ] || fail "cli unpack failed"
# The 3.11 library package has no executable. The pandoc binary is pandoc-cli.
rm -f "$TREE/cabal.project" "$TREE/cabal.project.freeze"

cat > "$WORK/src/cabal.project" <<'EOF'
packages:
  pandoc-3.11
  pandoc-cli-3.11

tests: False
benchmarks: False
shared: False
executable-dynamic: False

package pandoc
  flags: -http +embed_data_files

package pandoc-cli
  flags: -lua -server -repl -nightly
EOF
/bin/cp -f "$FREEZE_SRC" "$WORK/src/cabal.project.freeze"
# The solved freeze leaves embed_data_files off (the Hackage default).
# cabal build then bakes an absolute data-dir under the cabal store, and
# the copied binary exits 97 looking for abbreviations. Embedding adds no
# Hackage packages: it only compiles Text.Pandoc.Data.BakedIn.
grep -q 'pandoc -embed_data_files -http' "$WORK/src/cabal.project.freeze" \
	|| fail "freeze has no embed_data_files constraint"
sed -i 's/pandoc -embed_data_files -http/pandoc +embed_data_files -http/' \
	"$WORK/src/cabal.project.freeze"

# Vendored index and tarballs. No cabal update. Skip the 1 GiB copy when
# this cache was already filled from the same vendor tree.
if [ ! -f "$CABAL_DIR/packages/hackage.haskell.org/01-index.tar" ] \
	|| [ ! -f "$CABAL_DIR/packages/hackage.haskell.org/Glob/0.10.2/Glob-0.10.2.tar.gz" ]
then
	phase "fill package cache"
	rm -rf "$CABAL_DIR/packages"
	mkdir -p "$CABAL_DIR/packages/hackage.haskell.org"
	/bin/cp -a "$VENDOR/." "$CABAL_DIR/packages/hackage.haskell.org/"
fi
if [ ! -f "$CABAL_DIR/config" ]; then
	"$CABAL" user-config init --force
fi

phase "plan"
cd "$WORK/src"
if ! stdbuf -oL -eL "$CABAL" build --dry-run -j8 --with-compiler="$GHC" \
	--with-hsc2hs="$WORK/bin/hsc2hs" \
	--disable-tests --disable-benchmarks pandoc-cli:exe:pandoc \
	> "$WORK/logs/cabal-dry-run.log" 2>&1
then
	fail "cabal dry-run: $(tail -30 "$WORK/logs/cabal-dry-run.log" | tr '\n' ' ' | cut -c1-900)"
fi
if grep -q 'requires download' "$WORK/logs/cabal-dry-run.log"; then
	fail "plan still wants a download"
fi
if ! grep -q 'pandoc-cli-3.11 (exe:pandoc)' "$WORK/logs/cabal-dry-run.log"; then
	fail "plan missing pandoc-cli executable"
fi

phase "build"
if ! stdbuf -oL -eL "$CABAL" build -j8 --with-compiler="$GHC" \
	--with-hsc2hs="$WORK/bin/hsc2hs" \
	--disable-tests --disable-benchmarks pandoc-cli:exe:pandoc \
	> "$WORK/logs/cabal-build.log" 2>&1
then
	fail "cabal build: $(tail -c 1800 "$WORK/logs/cabal-build.log" | tr '\n' ' ')"
fi
bin=$("$CABAL" list-bin --with-compiler="$GHC" --with-hsc2hs="$WORK/bin/hsc2hs" pandoc-cli:exe:pandoc | tr -d '[:space:]')
[ -x "$bin" ] || fail "list-bin produced '$bin'"
/bin/cp -f "$bin" "$PREFIX/bin/pandoc"
chmod +x "$PREFIX/bin/pandoc"

pver=$("$PREFIX/bin/pandoc" --version | awk 'NR==1{print; exit}')
printf '%s\n' "$pver" | grep -qx 'pandoc 3.11' || fail "pandoc version line '$pver'"

cat > "$WORK/proof/fixture.md" <<'EOF'
# Bootstrap Heading

A short paragraph about the in-chain compiler.
EOF
"$PREFIX/bin/pandoc" -f markdown -t html "$WORK/proof/fixture.md" > "$WORK/proof/pandoc-1.html"
"$PREFIX/bin/pandoc" -f markdown -t html "$WORK/proof/fixture.md" > "$WORK/proof/pandoc-2.html"
for f in "$WORK/proof/pandoc-1.html" "$WORK/proof/pandoc-2.html"; do
	grep -q 'Bootstrap Heading' "$f" || fail "$f missing heading"
	grep -q 'A short paragraph about the in-chain compiler.' "$f" || fail "$f missing paragraph"
	grep -q '<h1' "$f" || fail "$f missing h1"
	grep -q '<p>' "$f" || fail "$f missing p"
done
cmp -s "$WORK/proof/pandoc-1.html" "$WORK/proof/pandoc-2.html" || fail "html outputs differ"

{
	printf 'pandoc_version=%s\n' "$pver"
	printf 'pandoc_bin=%s\n' "$PREFIX/bin/pandoc"
	printf 'ghc_numeric_version=%s\n' "$ver"
	printf 'ghc_bin=%s\n' "$GHC"
	printf 'ghc_libdir=%s\n' "$("$GHC" --print-libdir)"
	printf 'cabal_numeric_version=%s\n' "$cver"
	printf 'cabal_bin=%s\n' "$CABAL"
	printf 'built_from=%s\n' "$bin"
	printf 'flags=pandoc:-http +embed_data_files pandoc-cli:-lua -server -repl -nightly\n'
	printf 'offline=vendored-cache\n'
	printf 'cabal_offline_flag=no\n'
	printf 'network_policy=proxy-127.0.0.1:9\n'
	printf 'source_sha256=%s\n' "$EXPECT_SHA"
} > "$WORK/logs/pandoc-build.log"
phase "html ok"
printf 'PANDOC311PKG_DONE %s %s\n' "$PREFIX/bin/pandoc" "$pver"
