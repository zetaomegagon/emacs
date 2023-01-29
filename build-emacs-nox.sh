#!/usr/bin/env bash

make distclean \
    && ./autogen.sh \
    && ./configure --without-all \
		   --without-x \
		   --with-mailutils \
		   --with-wide-int \
		   --with-modules \
		   --with-libsystemd \
		   --with-tree-sitter \
		   --enable-check-lisp-object-type \
		   --enable-acl \
		   --enable-year2038 \
		   --with-threads \
		   --with-json \
		   --with-zlib \
		   --with-selinux \
		   --with-gnutls \
		   --with-file-notification=yes \
		   --with-native-compilation=aot \
		   PKG_CONFIG_PATH=/usr/local/lib/pkgconfig

make
