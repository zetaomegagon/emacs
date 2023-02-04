#!/usr/bin/env bash

# update dependancies
sudo dnf upgrade -y
# link tree-sitter libs
sudo ldconfig /usr/local/lib

# clean the repo and configure
make extraclean \
    && ./autogen.sh \
    && ./configure --enable-check-lisp-object-type \
		   --with-mailutils \
		   --with-pgtk \
		   --with-wide-int \
		   --with-tree-sitter \
		   --with-native-compilation=aot \
		   PKG_CONFIG_PATH='/usr/local/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig'
# begin build
make -j $(nproc)

# unistall existing emacs
sudo make uninstall
# install new emacs
sudo make install
