# Any copyright is dedicated to the Public Domain.
# http://creativecommons.org/publicdomain/zero/1.0/

ROOT_DIR=${CURDIR}
LLVM_SHA=c3039d4e5b58f86fcab717f8024329ef81b0ad39
CLANG_SHA=b362b05b29b0d5bf897d5f3e9d99eb60c0025d5d
LLD_SHA=5fb37bb34735f7006f2c22ff10e3e6081a9ce33a
COMPILER_RT_SHA=250580a9aee433b34c9e187a72b8dda9ac75c4ec
LIBCXX_SHA=02b189877a38a4fd583d3d4770afa29bd4f4dde1
LIBCXXABI_SHA=d66bcda1e1d200e707d33eb204d9f89eb0c3eb77
MUSL_SHA=d9e28df3d85c0bb3b53c8f2e5a16f69dc74162a3

default: build

clean:
	rm -rf build src dist sysroot wasmception-*-bin.tar.gz

src/llvm.CLONED:
	mkdir -p src/
	cd src/; git clone https://github.com/gwsystems/wasmception-llvm.git llvm
ifdef LLVM_SHA
	cd src/llvm; git checkout $(LLVM_SHA)
endif
	cd src/llvm/tools; git clone https://github.com/gwsystems/wasmception-clang.git clang
ifdef CLANG_SHA
	cd src/llvm/tools/clang; git checkout $(CLANG_SHA)
endif
	cd src/llvm/tools; git clone https://github.com/gwsystems/wasmception-lld.git
ifdef LLD_SHA
	cd src/llvm/tools/lld; git checkout $(LLD_SHA)
endif
	touch src/llvm.CLONED

src/musl.CLONED:
	mkdir -p src/
	cd src/; git clone https://github.com/gwsystems/wasmception-musl.git
ifdef MUSL_SHA
	cd src/musl; git checkout $(MUSL_SHA)
endif
	touch src/musl.CLONED

src/compiler-rt.CLONED:
	mkdir -p src/
	cd src/; git clone https://github.com/gwsystems/wasmception-compiler-rt.git compiler-rt
ifdef COMPILER_RT_SHA
	cd src/compiler-rt; git checkout $(COMPILER_RT_SHA)
endif
	touch src/compiler-rt.CLONED

src/libcxx.CLONED:
	mkdir -p src/
	cd src/; git clone https://github.com/gwsystems/wasmception-libcxx.git libcxx
ifdef LIBCXX_REV
	cd src/libcxx; git checkout $(LIBCXX_SHA)
endif
	cd src/libcxx; patch -p 1 < $(ROOT_DIR)/patches/libcxx.patch
	touch src/libcxx.CLONED

src/libcxxabi.CLONED:
	mkdir -p src/
	cd src/; git clone https://github.com/gwsystems/wasmception-libcxxabi.git libcxxabi
ifdef LIBCXXABI_REV
	cd src/libcxxabi; git checkout $(LIBCXXABI_SHA)
endif
	touch src/libcxxabi.CLONED

build/llvm.BUILT: src/llvm.CLONED
	mkdir -p build/llvm
	cd build/llvm; cmake -G "Unix Makefiles" \
		-DCMAKE_BUILD_TYPE=MinSizeRel \
		-DCMAKE_INSTALL_PREFIX=$(ROOT_DIR)/dist \
		-DLLVM_TARGETS_TO_BUILD= \
		-DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD=WebAssembly \
		$(ROOT_DIR)/src/llvm
	cd build/llvm; $(MAKE) -j 8 \
		install-clang \
		install-lld \
		install-llc \
		install-llvm-ar \
		install-llvm-ranlib \
		llvm-config
	touch build/llvm.BUILT

build/musl.BUILT: src/musl.CLONED build/llvm.BUILT
	mkdir -p build/musl
	make -C src/musl install prefix=$(ROOT_DIR)/sysroot CC="$(ROOT_DIR)/dist/bin/clang --target=wasm32-unknown-unknown-wasm" CROSS_COMPILE=$(ROOT_DIR)/dist/bin/llvm-
	touch build/musl.BUILT

build/compiler-rt.BUILT: src/compiler-rt.CLONED build/llvm.BUILT
	mkdir -p build/compiler-rt
	cd build/compiler-rt; cmake -G "Unix Makefiles" \
		-DCMAKE_BUILD_TYPE=RelWithDebInfo \
		-DCMAKE_TOOLCHAIN_FILE=$(ROOT_DIR)/wasm_standalone.cmake \
		-DCOMPILER_RT_BAREMETAL_BUILD=On \
		-DCOMPILER_RT_BUILD_XRAY=OFF \
		-DCOMPILER_RT_INCLUDE_TESTS=OFF \
		-DCOMPILER_RT_ENABLE_IOS=OFF \
		-DCOMPILER_RT_DEFAULT_TARGET_ONLY=On \
		-DCMAKE_C_FLAGS="--target=wasm32-unknown-unknown-wasm -O1" \
		-DLLVM_CONFIG_PATH=$(ROOT_DIR)/build/llvm/bin/llvm-config \
		-DCOMPILER_RT_OS_DIR=. \
		-DCMAKE_INSTALL_PREFIX=$(ROOT_DIR)/dist/lib/clang/7.0.0/ \
		-DCMAKE_VERBOSE_MAKEFILE:BOOL=ON \
		$(ROOT_DIR)/src/compiler-rt/lib/builtins
	cd build/compiler-rt; make -j 8 install
	cp -R $(ROOT_DIR)/build/llvm/lib/clang $(ROOT_DIR)/dist/lib/
	touch build/compiler-rt.BUILT

build/libcxx.BUILT: build/llvm.BUILT src/libcxx.CLONED build/compiler-rt.BUILT build/musl.BUILT
	mkdir -p build/libcxx
	cd build/libcxx; cmake -G "Unix Makefiles" \
		-DCMAKE_TOOLCHAIN_FILE=$(ROOT_DIR)/wasm_standalone.cmake \
		-DLLVM_CONFIG_PATH=$(ROOT_DIR)/build/llvm/bin/llvm-config \
		-DCMAKE_VERBOSE_MAKEFILE:BOOL=ON \
		-DLIBCXX_ENABLE_THREADS:BOOL=OFF \
		-DLIBCXX_ENABLE_STDIN:BOOL=OFF \
		-DLIBCXX_ENABLE_STDOUT:BOOL=OFF \
		-DCMAKE_BUILD_TYPE=RelWithDebugInfo \
		-DLIBCXX_ENABLE_SHARED:BOOL=OFF \
		-DLIBCXX_ENABLE_EXPERIMENTAL_LIBRARY:BOOL=OFF \
		-DLIBCXX_ENABLE_FILESYSTEM:BOOL=OFF \
		-DLIBCXX_ENABLE_EXCEPTIONS:BOOL=OFF \
		-DLIBCXX_ENABLE_RTTI:BOOL=OFF \
		-DCMAKE_C_FLAGS="--target=wasm32-unknown-unknown-wasm" \
		-DCMAKE_CXX_FLAGS="--target=wasm32-unknown-unknown-wasm -D_LIBCPP_HAS_MUSL_LIBC" \
		--debug-trycompile \
		$(ROOT_DIR)/src/libcxx
	cd build/libcxx; make -j 8 install
	touch build/libcxx.BUILT

build/libcxxabi.BUILT: src/libcxxabi.CLONED build/libcxx.BUILT build/llvm.BUILT
	mkdir -p build/libcxxabi
	cd build/libcxxabi; cmake -G "Unix Makefiles" \
		-DCMAKE_VERBOSE_MAKEFILE:BOOL=ON \
		-DCMAKE_CXX_COMPILER_WORKS=ON \
		-DCMAKE_C_COMPILER_WORKS=ON \
		-DLIBCXXABI_ENABLE_EXCEPTIONS:BOOL=OFF \
		-DLIBCXXABI_ENABLE_SHARED:BOOL=OFF \
		-DLIBCXXABI_ENABLE_THREADS:BOOL=OFF \
		-DCXX_SUPPORTS_CXX11=ON \
		-DLLVM_COMPILER_CHECKED=ON \
		-DCMAKE_BUILD_TYPE=RelWithDebugInfo \
		-DLIBCXXABI_LIBCXX_PATH=$(ROOT_DIR)/src/libcxx \
		-DLIBCXXABI_LIBCXX_INCLUDES=$(ROOT_DIR)/sysroot/include/c++/v1 \
		-DLLVM_CONFIG_PATH=$(ROOT_DIR)/build/llvm/bin/llvm-config \
		-DCMAKE_TOOLCHAIN_FILE=$(ROOT_DIR)/wasm_standalone.cmake \
		-DCMAKE_C_FLAGS="--target=wasm32-unknown-unknown-wasm" \
		-DCMAKE_CXX_FLAGS="--target=wasm32-unknown-unknown-wasm -D_LIBCPP_HAS_MUSL_LIBC" \
		-DUNIX:BOOL=ON \
		--debug-trycompile \
		$(ROOT_DIR)/src/libcxxabi
	cd build/libcxxabi; make -j 8 install
	touch build/libcxxabi.BUILT

BASICS=sysroot/include/wasmception.h sysroot/lib/wasmception.wasm

sysroot/include/wasmception.h: basics/wasmception.h
	cp basics/wasmception.h sysroot/include/

sysroot/lib/wasmception.wasm: build/llvm.BUILT basics/wasmception.c
	dist/bin/clang \
		--target=wasm32-unknown-unknown-wasm \
		--sysroot=./sysroot basics/wasmception.c \
		-c -O3 -g \
		-o sysroot/lib/wasmception.wasm

build: build/llvm.BUILT build/musl.BUILT build/compiler-rt.BUILT build/libcxxabi.BUILT build/libcxx.BUILT $(BASICS)
	cp -r $(ROOT_DIR)/dist/lib/clang/7.0.0/* $(ROOT_DIR)/dist/lib/clang/8.0.0/

strip: build/llvm.BUILT
	cd dist/bin; strip clang-7 llc lld llvm-ar

revisions:
	cd src/llvm; echo "LLVM_REV=`svn info --show-item revision`"
	cd src/llvm/tools/clang; echo "CLANG_REV=`svn info --show-item revision`"
	cd src/llvm/tools/lld; echo "LLD_REV=`svn info --show-item revision`"
	cd src/musl; echo "MUSL_SHA=`git log -1 --format="%H"`"
	cd src/compiler-rt; echo "COMPILER_RT_REV=`svn info --show-item revision`"
	cd src/libcxx; echo "LIBCXX_REV=`svn info --show-item revision`"
	cd src/libcxxabi; echo "LIBCXXABI_REV=`svn info --show-item revision`"

OS_NAME=$(shell uname -s | tr '[:upper:]' '[:lower:]')
pack:
	tar czf wasmception-${OS_NAME}-bin.tar.gz dist sysroot

.PHONY: default clean build strip revisions pack
