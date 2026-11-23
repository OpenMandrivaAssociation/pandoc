%global debug_package %{nil}
Summary:	Pandoc 3.11 markup converter
Name:		pandoc
Version:	3.11
Release:	1
License:	GPL-2.0-or-later
Group:		Publishing
Url:		https://pandoc.org/
# Fills the empty distribution pandoc stub. This is the distro package,
# so no Epoch (and not Epoch 10).
# Built with packaged ghc98 and cabal-install. Hackage is vendored.
ExclusiveArch:	x86_64 znver1
Source0:	pandoc-3.11.tar.gz
Source1:	pandoc-cli-3.11.tar.gz
Source2:	pandoc-3.11-hackage.tar.gz
Source3:	pandoc-3.11.cabal.project.freeze
Source4:	pandoc-build.sh
Source5:	%{name}.rpmlintrc

BuildRequires:	ghc98
BuildRequires:	cabal-install
BuildRequires:	pkgconfig(zlib)
BuildRequires:	gcc
BuildRequires:	python
BuildRequires:	file
BuildRequires:	tar
BuildRequires:	gzip
BuildRequires:	findutils
BuildRequires:	coreutils
BuildRequires:	diffutils
BuildRequires:	sed
BuildRequires:	gawk
BuildRequires:	grep

%description
Pandoc 3.11 compiled by packaged ghc98 (GHC 9.8.4) and cabal-install
3.12.1.0. The library has no executable; the binary is pandoc-cli.
Dependencies are a vendored Hackage cache. The build does not use the
network: proxies point at a closed local port, and cabal is not passed
--offline because that flag rejects vendored tarballs (Cabal issue 7125).
The pandoc flags are -http and +embed_data_files, so the installed
program is a single binary.

%prep
	set -eu
	cd %{_builddir}
	rm -rf pandoc-root
	mkdir -p pandoc-root/incoming
	cp -a %{SOURCE0} pandoc-root/incoming/pandoc-3.11.tar.gz
	cp -a %{SOURCE1} pandoc-root/incoming/pandoc-cli-3.11.tar.gz
	cp -a %{SOURCE2} pandoc-root/incoming/pandoc-3.11-hackage.tar.gz
	cp -a %{SOURCE3} pandoc-root/incoming/pandoc-3.11.cabal.project.freeze
	cp -a %{SOURCE4} pandoc-root/incoming/pandoc-build.sh
	chmod 755 pandoc-root/incoming/pandoc-build.sh
	set +u

%build
	set -eu
	bash %{_builddir}/pandoc-root/incoming/pandoc-build.sh \
		"%{_builddir}/pandoc-root"
	set +u

%install
	set -eu
	mkdir -p %{buildroot}%{_bindir}
	install -m 755 %{_builddir}/pandoc-root/dest/bin/pandoc \
		%{buildroot}%{_bindir}/pandoc
	set +u

%files
%{_bindir}/pandoc

%check
	set -eu
	b=%{buildroot}%{_bindir}/pandoc
	export TMPDIR=%{_builddir}/pandoc-root/work/tmp
	export TEMP=$TMPDIR
	export TMP=$TMPDIR
	mkdir -p "$TMPDIR" check
	export http_proxy=http://127.0.0.1:9
	export https_proxy=http://127.0.0.1:9
	export HTTP_PROXY=http://127.0.0.1:9
	export HTTPS_PROXY=http://127.0.0.1:9
	export all_proxy=http://127.0.0.1:9
	export ALL_PROXY=http://127.0.0.1:9
	"$b" --version > version.out
	ver=$(awk 'NR==1{print; exit}' version.out)
	test "$ver" = "pandoc 3.11"
	cat > check/fixture.md <<-'EOF'
	# Bootstrap Heading

	A short paragraph.
	EOF
	"$b" -f markdown -t html check/fixture.md > check/pandoc-1.html
	"$b" -f markdown -t html check/fixture.md > check/pandoc-2.html
	cmp -s check/pandoc-1.html check/pandoc-2.html
	grep -q 'Bootstrap Heading' check/pandoc-1.html
	grep -q 'Bootstrap Heading' check/pandoc-2.html
	grep -q '<h1' check/pandoc-1.html
	grep -q '<h1' check/pandoc-2.html
	grep -q '<p>' check/pandoc-1.html
	grep -q '<p>' check/pandoc-2.html
	set +u
