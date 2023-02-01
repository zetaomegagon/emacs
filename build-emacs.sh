#!/usr/bin/env bash

if $(emacs-nox --batch --eval "()"); then

    # update dependancies
    sudo dnf upgrade -y
    # linke treesitter libs
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
		       PKG_CONFIG_PATH=/usr/local/lib/pkgconfig/
    # begin build
    make -j $(nproc)

    # install as to not clobber emacs-nox installation
    # - install emacs binary
    prefix=/usr/local
    version="$(./src/emacs --version | head -1 | cut -d' ' -f3)"
    sudo cp ./src/emacs ${prefix}/bin/emacs-${version}

    # - install native compiled lisp files
    native_dir="$(basename "$(echo ./native-lisp/*)")"
    lisp_dir="${prefix}/lib/emacs/${version}/native-lisp"
    sudo cp -r ./native-lisp/* ${lisp_dir}/
    sudo chmod -R 644 ${lisp_dir}/
    sudo chmod -R 644 ${lisp_dir}/${native_dir}/preloaded/
    sudo chmod 755 ${lisp_dir}/${native_dir}/preloaded/

    # - install emacs.pdmp
    arch=x86_64-pc-linux-gnu
    fingerprint="$(./src/emacs --fingerprint)"
    sudo cp ./src/emacs.pdmp ${prefix}/libexec/emacs/${version}/${arch}/emacs-${fingerprint}.pdmp

    # - install launcher icons
    sudo cp ./etc/*.desktop ${prefix}/share/applications/

else
    ./build-emacs-nox.sh
    ./build-emacs.sh
fi
