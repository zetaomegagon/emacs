#!/usr/bin/env bash

input="$1"
_usage() { echo "Usage: ./build-emacs.sh --x11|--nox|--pgtk"; }

case "$input" in
    --x11|--nox|--pgtk)
	# keep sudo timer refreshed
	sudo -v
	script_pid="$$"
	while pgrep bash | grep -q "$script_pid" ; do sudo -v; sleep 60; done &

	# update the system and install dependancies
	sudo dnf upgrade -y
	sudo dnf install -y libtool libwebp{,-devel} lcms2-devel gcc-c++
	sudo dnf builddep -y emacs

	# build and install latest sbcl
	(
	    cd ..

	    if ! hash sbcl; then
		sudo dnf install sbcl -y
	    fi

	    if [[ ! -d sbcl ]]; then
		git clone git://git.code.sf.net/p/sbcl/sbcl
	    fi

	    cd sbcl && git pull --quiet && ./clean.sh && ./make.sh

	    (
		cd ./doc/manual/
		sudo dnf install texinfo-tex -y
		make clean && make
		sudo dnf remove texinfo-tex -y
	    )

	    sudo ./install.sh
	    sudo dnf remove sbcl -y

	) >/dev/null 2>&1 &

	sbcl_build_pid=$!
	printf "%s\n" "Building Steel Bank Common Lisp"

	# build and install latest mailutils
	(
	    cd ..

	    src="https://ftp.gnu.org/gnu/mailutils/mailutils-latest.tar.xz"
	    xz="${src##*/}"
	    dir="${xz%-*}"

	    if [[ -d "$dir" ]]; then
		sudo rm -rf "$dir"
	    fi

	    wget -q "$src"
	    tmp="$(tar -tJf "$xz" | head -1 | tr -d '/')"
	    tar -xJf "$xz"
	    mv "$tmp" "$dir"
	    cd "$dir"

	    ./configure
	    make -j "$(nproc)"
	    sudo make install
	    rm ../"$xz"

	) >/dev/null 2>&1 &

	mailutils_build_pid=$!
	printf "%s\n" "Building GNU Mailutils"

	# build and install latest tree-sitter
	(
	    cd ..

	    if [[ ! -d tree-sitter ]]; then
		git clone https://github.com/tree-sitter/tree-sitter.git
		cd tree-sitter
	    else
		cd tree-sitter
		make clean
		git pull --quiet
	    fi

	    make -j "$(nproc)"
	    sudo make install

	) >/dev/null 2>&1 &

	tree_sitter_build_pid=$!
	printf "%s\n" "Building Tree-Sitter AST Parser"

	# build and install tree-sitter-modules
	(
	    cd ..

	    if [[ ! -d tree-sitter-module ]]; then
		git clone https://github.com/casouri/tree-sitter-module
		cd tree-sitter-module
	    else
		cd tree-sitter-module
		[[ -d ./dist ]] && sudo rm -rf ./dist
		git stash
		git pull --quiet
		git stash apply
		git stash drop
	    fi

	    ./batch.sh
	    sudo chown -R root:root dist/
	    sudo cp ./dist/* /usr/local/lib/

	    # link tree-sitter libs
	    sudo ldconfig /usr/local/lib

	) >/dev/null 2>&1 &

	tree_sitter_module_build_pid=$!
	printf "%s\n" "Building Tree-Sitter AST Parser language modules"

	# wait for background builds to finish
	wait "$mailutils_build_pid" \
	     "$tree_sitter_build_pid" \
	     "$tree_sitter_module_build_pid"

	# clean and update the repo
	make extraclean
	git fetch upstream
	git merge --no-edit upstream/master
	git push -u origin master

	# generate configure script
	./autogen.sh

	# remove old native compiled files in
	# - ./native-lisp/...
	# - /usr/local/lib/...
	# - ~/.emacs.d/eln-cache/...
	# - ~/.emacs.d/straight/...
	version="$(command grep 'PACKAGE_VERSION=' ./configure | cut -d'=' -f2 | tr -d \')"

	rm -rf ./native-lisp/{,.}* || :
	sudo rm -rf /usr/local/lib/emacs/${version}/native-lisp/{,.}* || :
	rm -rf $HOME/.emacs.d/eln-cache/{,.}* || :
	rm -rf $HOME/.emacs.d/straight/{,.}* || :

	# configure the build
	case "$input" in
	    --nox)
		./configure \
		    --without-all \
		    --without-x \
		    --enable-acl \
		    --enable-year2038 \
		    --with-sqlite3 \
		    --with-mailutils \
		    --with-wide-int \
		    --with-modules \
		    --with-libsystemd \
		    --with-tree-sitter \
		    --with-threads \
		    --with-json \
		    --with-zlib \
		    --with-selinux \
		    --with-gnutls \
		    --with-file-notification=yes \
		    --with-gameuser=:games \
		    --enable-check-lisp-object-type \
		    --with-native-compilation=aot \
		    PKG_CONFIG_PATH='/usr/local/lib/pkgconfig'
		;;
	    --x11)
		./configure \
		    --with-x-toolkit=no \
		    --with-mailutils \
		    --with-wide-int \
		    --with-tree-sitter \
		    --with-cairo \
		    --without-gconf \
		    --without-gsettings \
		    --with-gameuser=:games \
		    --enable-check-lisp-object-type \
		    --with-native-compilation=aot \
		    PKG_CONFIG_PATH='/usr/local/lib/pkgconfig'
		;;
	    --pgtk)
		./configure \
		    --with-pgtk \
		    --with-mailutils \
		    --with-wide-int \
		    --with-tree-sitter \
		    --with-gameuser=:games \
		    --enable-check-lisp-object-type \
		    --with-native-compilation=aot \
		    PKG_CONFIG_PATH='/usr/local/lib/pkgconfig'
		;;
	    *)
		_usage
	esac

	# make the build
	make -j $(( $(nproc) / 2 ))

	# disable and stop emacs daemon
	[[ ! -f $HOME/.bin/emacs ]] && systemctl --user disable --now emacs.service

	# uninstall old emacs; install new emacs
	sudo bash -c 'make uninstall && make install'

	# pull and build straight packages
	/usr/local/bin/emacs -Q --batch --load=$HOME/.emacs.d/early-init.el --load=$HOME/.emacs.d/init.el

	# native compile straight packages
	echo "Native compiling Straight packages"
	/usr/local/bin/emacs -Q --batch --load=$HOME/.emacs.d/early-init.el --load=$HOME/.emacs.d/init.el
	echo "Finished native compilation"

	# reload changed unit files and start daemon
	if [[ ! -f $HOME/.bin/emacs ]]; then
	    systemctl --user daemon-reload
	    systemctl --user enable --now  emacs.service
	fi
	;;
    *)
	_usage
esac
