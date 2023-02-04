#!/usr/bin/env bash

# update dependancies
sudo dnf upgrade -y

# clean the repo and configure
make extraclean \
    && ./autogen.sh \
    && ./configure --enable-check-lisp-object-type \
		   --with-mailutils \
		   --with-pgtk \
		   --with-wide-int \
		   --with-tree-sitter \
		   --with-native-compilation=aot \
		   PKG_CONFIG_PATH=/usr/local/lib/pkgconfig/
# begin build
make -j $(nproc)

# install
make install
