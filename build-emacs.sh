#!/usr/bin/env bash

input="$1"
_usage() { echo "Usage: ./build-emacs.sh --x11|--nox|--pgtk"; }

case "$input" in
    --x11|--nox|--pgtk)
	# update the system and install dependancies
	sudo bash -c "dnf upgrade -y && dnf install -y libtool libwebp{,-devel} lcms2-devel gcc-c++ && dnf builddep -y emacs"

	# keep sudo timer refreshed
	while : ; do sudo -v; sleep 60; done &
	sudo_loop=$!

	# build and install latest sbcl
	(
	    cd ..

	    if [[ ! -d sbcl ]]; then
		git clone git://git.code.sf.net/p/sbcl/sbcl
	    fi

	    git pull --quiet

	    cd sbcl && ./clean.sh && ./make.sh

	    (
		cd ./doc/manual/
		sudo dnf install texinfo-tex -y
		make clean && make
		sudo dnf remove texinfo-tex -y
	    )

	    sudo ./install.sh

	) >/dev/null 2>&1 &

	sbcl_build_pid=$!

	# build and install latest mailutils
	(
	    cd ..

	    src="https://ftp.gnu.org/gnu/mailutils/mailutils-latest.tar.xz"
	    xz="${src##*/}"
	    dir="$(echo "$xz" | cut -d'-' -f1)"

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
	) >/dev/null 2>&1 &

	mailutils_build_pid=$!

	# build and install latest tree-sitter
	(
	    cd ..

	    if [[ ! -d tree-sitter ]]; then
		git clone https://github.com/tree-sitter/tree-sitter.git
		cd tree-sitter
		make -j "$(nproc)"
		sudo make install
	    else
		cd tree-sitter
		make clean
		git pull --quiet
		make -j "$(nproc)"
		sudo make install
	    fi
	) >/dev/null 2>&1 &

	tree_sitter_build_pid=$!

	# build and install tree-sitter-modules
	(
	    cd ..

	    if [[ ! -d tree-sitter-module ]]; then
		git clone https://github.com/casouri/tree-sitter-module
		cd tree-sitter-module
		./batch.sh
		chown -R root:root dist/*
		sudo mv ./dist/* /usr/local/lib/
	    else
		cd tree-sitter-module
		git pull --quiet
		./batch.sh
		chown -R root:root dist/*
		sudo mv ./dist/* /usr/local/lib/
	    fi

	    # link tree-sitter libs
	    sudo ldconfig /usr/local/lib

	) >/dev/null 2>&1 &

	tree_sitter_module_build_pid=$!


	wait $mailutils_build_pid
	wait $tree_sitter_build_pid
	wait $tree_sitter_module_build_pid

	# clean and update the repo
	make extraclean \
	    && git fetch upstream \
	    && git merge --no-edit upstream/master \
	    && git push -u origin master

	# generate configure script
	./autogen.sh

	# remove old native compiled files in
	# - ./native-lisp/...
	# - /usr/local/lib/...
	# - ~/.emacs.d/eln-cache/...
	# - ~/.emacs.d/straight/...
	version="$(command grep 'PACKAGE_VERSION=' ./configure | cut -d'=' -f2 | tr -d \')"

	if [[ -d ./native-lisp ]]; then
	    for dir in ./native-lisp/*; do
		rm -rf "$dir" || :
		sudo rm -rf "/usr/local/lib/emacs/${version}/native-lisp/${dir##*/}" || :
		rm -rf "$HOME/.emacs.d/eln-cache/${dir##*/}" || :
	    done
	fi

	if [[ -d $HOME/.emacs.d/straight ]]; then
	    rm -rf $HOME/.emacs.d/straight || :
	fi

	# configure the build
	case "$input" in
	    --nox)
		./configure \
		    --without-all \
		    --without-x \
		    --enable-check-lisp-object-type \
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
		    --with-native-compilation=aot \
		    PKG_CONFIG_PATH='/usr/local/lib/pkgconfig'
		;;
	    --x11)
		./configure \
		    --enable-check-lisp-object-type \
		    --with-x-toolkit=lucid \
		    --with-mailutils \
		    --with-wide-int \
		    --with-tree-sitter \
		    --with-native-compilation=aot \
		    PKG_CONFIG_PATH='/usr/local/lib/pkgconfig'
		;;
	    --pgtk)
		./configure \
		    --enable-check-lisp-object-type \
		    --with-pgtk \
		    --with-mailutils \
		    --with-wide-int \
		    --with-tree-sitter \
		    --with-native-compilation=aot \
		    PKG_CONFIG_PATH='/usr/local/lib/pkgconfig'
		;;
	    *)
		_usage
	esac

	# make the build
	make -j "$(nproc)"

	# disable and stop emacs daemon
	systemctl --user disable --now emacs.service

	# uninstall old emacs; install new emacs
	sudo bash -c 'make uninstall && make install'

	# pull and build straight packages
	/usr/local/bin/emacs --batch --load=$HOME/.emacs.d/early-init.el --load=$HOME/.emacs.d/init.el

	# native compile straight packages
	echo "Native compiling Straight packages"
	( /usr/local/bin/emacs --batch --load=$HOME/.emacs.d/early-init.el --load=$HOME/.emacs.d/init.el ) &
	native_comp_pid=$!
	wait "$native_comp_pid"
	echo "Finished native compilation"

	# reload changed unit files and start daemon
	systemctl --user daemon-reload
	systemctl --user enable --now  emacs.service

	# stop sudo timer refresh
	sudo kill -9 "$sudo_loop"
	;;
    *)
	_usage
esac
