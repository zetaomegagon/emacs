#!/usr/bin/env bash

# update the system
sudo dnf upgrade -y
# install dependancies
sudo dnf install -y libwebp-devel liblcms2-devel
sudo dnf builddep -y emacs
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
systemctl --user disable --now emacs.service
sudo make uninstall
# install new emacs
sudo make install
systemctl --user enable --now emacs.service
