#!/usr/bin/env bash

sudo dnf upgrade -y

make extraclean \
     && ./autogen.sh \
     && ./configure --enable-check-lisp-object-type \
		    --with-mailutils \
		    --with-pgtk \
		    --with-wide-int \
		    --with-tree-sitter \
		    --with-native-compilation=aot \
		    PKG_CONFIG_PATH=/usr/local/lib/pkgconfig/

make -j $(nproc)
