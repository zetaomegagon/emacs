#!/usr/bin/env bash

input="$1"
_usage() { echo "Usage: ./build-emacs.sh --x11|--nox|--pgtk"; }

case "$input" in
    --x11|--nox|--pgtk)
	# update the system and install dependancies
	sudo bash -c "dnf upgrade -y && dnf install -y libwebp{,-devel} lcms2-devel gcc-c++ && dnf builddep -y emacs"

	# build and install current tree-sitter
	(
	    cd ..

	    if [[ ! -d tree-sitter ]]; then
		git clone https://github.com/tree-sitter/tree-sitter.git
		cd tree-sitter
		make
		sudo make install
	    else
		cd tree-sitter
		make clean
		git pull --quiet
		make
		sudo make install
	    fi
	)

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
	)

	# link tree-sitter libs
	sudo ldconfig /usr/local/lib

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
	version="$(command grep 'PACKAGE_VERSION=' ./configure | cut -d'=' -f2 | tr -d \')"

	if [[ -e ./native-lisp ]]; then
	    for dir in ./native-lisp/*; do
		rm -r "$dir" || :
		sudo rm -r "/usr/local/lib/emacs/${version}/native-lisp/${dir##*/}" || :
		rm -r "$HOME/.emacs.d/eln-cache/${dir##*/}" || :
	    done
	fi

	# keep sudo timer refreshed
	while : ; do
	    sudo -v
	    sleep 60
	done &

	sudo_loop=$!

	configure the build
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

	# reload changed unit files and start daemon
	systemctl --user daemon-reload
	systemctl --user enable --now  emacs.service

	# stop sudo timer refresh
	sudo kill -9 "$sudo_loop"
	;;
    *)
	_usage
esac
