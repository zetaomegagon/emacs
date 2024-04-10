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
	packages=(
	    libtool
	    libwebp
	    libwebp-devel
	    lcms2-devel
	    gcc
	    gcc-c++
	    cmake
	    automake
	    libpng-devel
	    make
	    poppler-devel
	    poppler-glib-devel
	    zlib-devel pkgconf
	    texinfo-tex
	    surfraw
	    dtach
	)

	sudo dnf clean all
	sudo dnf upgrade -y
	sudo dnf builddep -y emacs
	sudo dnf install -y "${packages[@]}"

	# build and install latest sbcl
	(
	    get-current-version() {
		git -c 'versionsort.suffix=' \
		    ls-remote --tags --sort='v:refname' \
		    "git://git.code.sf.net/p/sbcl/sbcl" \
		    | command grep -E 'sbcl-[0-9]+[^\^\{\}]*$' \
		    | sed -E 's,(^.*-)(.*),\2,g'
	    }

	    sbcl_git_version="$(get-current-version)"
	    sbcl_installed_version="$(sbcl --version | cut -d' ' -f2 | sed -E 's,(^.*)(\..*$),\1,g')"

	    if [[ "$sbcl_git_version" != "$sbcl_installed_version" ]]; then
		cd ..

		if ! hash sbcl; then
		    sudo dnf install sbcl -y
		fi

		if [[ ! -d sbcl ]]; then
		    git clone git://git.code.sf.net/p/sbcl/sbcl
		fi

		cd sbcl && git pull --quiet && ./clean.sh && ./make.sh "$(which sbcl) --no-userinit --no-sysinit"

		(
		    cd ./doc/manual/
		    make clean && make
		    sudo dnf remove texinfo-tex -y
		)

		sudo ./install.sh
		sudo dnf remove sbcl -y
	    fi

	) >/dev/null 2>&1 &

	sbcl_build_pid=$!
	printf "%s\n" "Building Steel Bank Common Lisp"

	# build and install latest mailutils
	(
	    get-current-version() {
		git -c 'versionsort.suffix=' \
		    ls-remote --tags --sort='v:refname' \
		    "https://git.savannah.gnu.org/git/mailutils.git" \
		    | command grep -E '/release-[0-9]+[^\^\{\}]*$' \
		    | tail -1 \
		    | sed -E 's,(.*-)(.*)$,\2,g'
	    }

	    mailutils_git_version="$(get-current-version)"
	    mailutils_installed_version="$(command mailutils --version | head -1 | cut -d ')' -f2)"

	    if [[ "$mailutils_installed_version" != "$mailutils_git_version" ]]; then
		cd ..
		src="https://ftp.gnu.org/gnu/mailutils/mailutils-latest.tar.xz"
		archive="${src##*/}"
		dir_name="${archive%-*}"

		if [[ -d "$dir" ]]; then
		    sudo rm -rf "$dir"
		fi

		wget -q "$src"
		tmp_name="$(tar -tJf "$archive" | head -1 | tr -d '/')"
		tar -xJf "$archive"
		mv "$tmp_name" "$dir_name"

		(
		    cd "$dir"
		    ./configure
		    make -j "$(nproc)"
		    sudo make uninstall
		    sudo make install
		)

		rm "$archive"
	    fi

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

	) >/dev/null 2>&1 &


	# link tree-sitter libs
	#
	# fix this so that we are putting tree-sitter stuff
	# in it's own directory and linking to it there
	sudo bash -c 'printf "%s" "/usr/local/lib" > /etc/ld.so.conf.d/tree-sitter.conf'

	tree_sitter_module_build_pid=$!
	printf "%s\n" "Building Tree-Sitter AST Parser language modules"

	# wait for background builds to finish
	wait "$mailutils_build_pid" \
	     "$tree_sitter_build_pid" \
	     "$tree_sitter_module_build_pid"

	# clean and update the repo
	sudo make extraclean
	git fetch upstream
	git merge --no-edit upstream/master
	git push -u origin master

	# generate configure script
	sudo ./autogen.sh

	# remove old native compiled files
	version="$(command grep 'PACKAGE_VERSION=' ./configure | cut -d'=' -f2 | tr -d \')"
	paths=(
	    "./native-lisp"
	    "/usr/local/lib/emacs/${version}/native-lisp"
	    "$HOME/.emacs.d/eln-cache"
	    "$HOME/.emacs.d/straight"
	    "$HOME/.emacs.d/elpaca"
	)

	for path in "${paths[@]}"; do
	    { sudo rm -rf ${path}/{,.}* || : ; } &
	done

	# configure the build
	flags_common=(
	    --without-xim
	    --without-gconf
	    --without-gsettings
	    --enable-acl
	    --enable-year2038
	    --with-sqlite3
	    --with-mailutils
	    --with-wide-int
	    --with-modules
	    --with-libsystemd
	    --with-tree-sitter
	    --with-threads
	    --with-json
	    --with-zlib
	    --with-selinux
	    --with-gnutls
	    --with-file-notification=yes
	    --with-gameuser=:games
	    --with-threads
	    --disable-build-details
	    --disable-silent-rules
	    --enable-check-lisp-object-type
	    --enable-gcc-warnings=warn-only
	    --with-native-compilation=aot
	)

	flags_nox=(
	    --without-all
	    --without-x
	)

	flags_x11=(
	    --with-x-toolkit=no
	    --with-cairo
	    --with-xwidgets
	)

	flags_pgtk=(
	    --with-pgtk
	)

	case "$input" in
	    --nox)
		./configure "${flags_common[@]}" "${flags_nox[@]}" PKG_CONFIG_PATH='/usr/local/lib/pkgconfig'
		;;
	    --x11)
		./configure "${flags_common[@]}" "${flags_x11[@]}" PKG_CONFIG_PATH='/usr/local/lib/pkgconfig'
		;;
	    --pgtk)
		./configure "${flags_common[@]}" "${flags_pgtk[@]}" PKG_CONFIG_PATH='/usr/local/lib/pkgconfig'
		;;
	    *)
		_usage
	esac

	# make the build
	sudo ldconfig /usr/local/lib
	make -j $(( $(nproc) / 2 ))

	# source some helper functions
	source $HOME/.bashrc.d/12-emacs.rc

	# if emacs is running gracefully shut it down
	emacs-running-p && emacsclient -e "(save-buffers-kill-emacs)"

	# disable and stop emacs daemon
	emacsctl disable || :

	# uninstall old emacs; install new emacs
	if [[ -e /usr/local/bin/emacs ]]; then
	    sudo bash -c '{ make uninstall && make install; } || exit'
	else
	    sudo make install || exit
	fi

	# pull and build straight packages
	for i in 0 1; do
	    # two iterations to download; then compile packages...
	    # ...I think...
	    /usr/local/bin/emacs \
		--quick \
		--batch \
		--load=$HOME/.emacs.d/early-init.el \
		--load=$HOME/.emacs.d/init.el
	done &

	build_packages_pid=$!
	printf "%s\n" "Building and compiling packages"

	# reload changed unit files
	wait "$build_packages_pid"
	emacsctl daemon-reload
	emacsctl start
	;;
    *)
	_usage
esac
