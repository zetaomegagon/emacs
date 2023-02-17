#!/usr/bin/env bash

declare user; user=$USER

if [[ $USER == root ]]; then
    # update the system
    dnf upgrade -y

    # install dependancies
    dnf install -y libwebp-devel lcms2-devel gcc-c++
    dnf builddep -y emacs

    # build and install current tree-sitter
    (
	cd ../tree-sitter/
	make clean
	git pull
	su "$user" -c make
	make install
    )

    # build and install tree-sitter-modules
    (
	cd ../tree-sitter-module/
	rm -r dist/*
	git pull
	su "$user" -c ./batch.sh
	chown -R root:root dist/*
	mv dist/* /usr/local/lib/
    )

    # link tree-sitter libs
    ldconfig /usr/local/lib

    # clean the repo and configure
    for dir in native-lisp/*; do
	rm -r "$dir"
	rm -r "/usr/local/lib/emacs/30.0.50/native-lisp/$dir"
	rm -r "$HOME/.emacs.d/eln-cache/$dir"
    done

    make extraclean \
	&& su "$user" 'git fetch upstream' \
	&& su "$user" 'git merge --no-edit upstream/master' \
	&& su "$user" 'git push -u origin master' \
	&& su "$user" -c ./autogen.sh \
	&& su "$user" -c "./configure --enable-check-lisp-object-type \
	      --with-mailutils \
	      --with-pgtk \
	      --with-wide-int \
	      --with-tree-sitter \
	      --with-native-compilation=aot \
	      PKG_CONFIG_PATH='/usr/local/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig'"

    # begin build
    su "$user" -c "make -j $(nproc)"

    # unistall existing emacs
    make uninstall

    # install new emacs
    make install
else
    echo "Run with sudo!"
fi
