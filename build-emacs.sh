#!/usr/bin/env bash

make distclean \
     && ./autogen.sh \
     && ./configure --with-mailutils \
		    --with-pgtk \
		    --with-wide-int \
		    --with-tree-sitter \
		    --with-native-compilation=aot \
		    PKG_CONFIG_PATH=/usr/local/lib/pkgconfig/

make -j8 all
