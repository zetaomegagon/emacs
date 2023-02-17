#!/usr/bin/env bash

if [[ $USER == root ]]; then
    # update the system
    dnf upgrade -y
    # install dependancies
    dnf install -y libwebp-devel liblcms2-devel
    dnf builddep -y emacs
    # link tree-sitter libs
    ldconfig /usr/local/lib

    # clean the repo and configure
    su ebeale -c make extraclean \
	&& su ebeale -c ./autogen.sh \
	&& su ebeale -c ./configure --enable-check-lisp-object-type \
	      --with-mailutils \
	      --with-pgtk \
	      --with-wide-int \
	      --with-tree-sitter \
	      --with-native-compilation=aot \
	      PKG_CONFIG_PATH='/usr/local/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig'

    # begin build
    su ebeale -c "make -j $(nproc)"

    # unistall existing emacs
    su ebeale -c 'systemctl --user disable --now emacs.service'
    make uninstall
    # install new emacs
    make install
    su ebeale -c 'systemctl --user enable --now emacs.service'
else
    echo "Run with sudo!"
fi
