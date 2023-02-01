#!/usr/bin/env bash

sudo dnf upgrade -y
sudo ldconfig /usr/local/lib

make extraclean \
    && ./autogen.sh \
    && ./configure --without-all \
		   --without-x \
		   --enable-check-lisp-object-type \
		   --enable-acl \
		   --enable-year2038 \
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
		   PKG_CONFIG_PATH=/usr/local/lib/pkgconfig

make -j $(nproc)
