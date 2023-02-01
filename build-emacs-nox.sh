#!/usr/bin/env bash

# upgrade dependencies
sudo dnf upgrade -y
# link treesitter libs
sudo ldconfig /usr/local/lib

# clean repo and configure
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

# begin build
make -j $(nproc)

# install emacs, enable and start emacs.service
# kickoff build of GUI emacs
version="$(./emacs --version | head -1 | cut -d' ' -f3)"
prefix=/usr/local
sudo make install \
    && sudo mv ${prefix}/bin/emacs-${version} ${prefix}/bin/emacs-${version}-nox \
    && systemctl --user enable --now emacs.service \
    && ./build-emacs.sh
