# Cabal System Library Directory Issue

Cabal configures the `pkg-config` program so that system library directories
are passed using `-L` command-line options.  When a dependency using a system
library directory (`/usr/lib`) is ordered before a dependency that requires a
different library directory, the wrong library may be linked.

## Issue Details

It is common to install multiple versions of development software in order to
test a range of versions.  Often, the most recent version is the system
default and one has to use configuration to build with an older version.

An example of such software is [LLVM/Clang][], which uses a program called
`llvm-config` to help with configuration of include directories, library
directories, C flags, etc.  One generally configures `PATH` so that the
desired version of the software is found, and `llvm-config` outputs the
appropriate settings for that version.

### System Environment

Currently, [Arch Linux][] provides the following versions, used in this demo:

* LLVM/Clang 22.1.5 is the system default, provided by the [`llvm`][] and
  [`clang`][] packages.
* LLVM/Clang 21.1.8 is also available, provided by the [`llvm21`][] and
  [`clang21`][] packages.

The `libclang` library provides a C API.  The ABI version is specified using
the major and minor version numbers, so the shared libraries are organized as
follows.

```
/usr/lib/
  libclang.so         ->  libclang.so.22.1
  libclang.so.21.1    ->  llvm21/lib/libclang.so.21.1
  libclang.so.22.1    ->  libclang.so.22.1.5
  libclang.so.22.1.5

/usr/lib/llvm21/lib/
  libclang.so         ->  libclang.so.21.1
  libclang.so.21.1    ->  libclang.so.21.1.8
  libclang.so.21.1.8
```

The `SONAME` for each shared library is as follows.

```
$ readelf -d /usr/lib/libclang.so.22.1.5 | grep SONAME
 0x000000000000000e (SONAME)             Library soname: [libclang.so.22.1]
$ readelf -d /usr/lib/llvm21/lib/libclang.so.21.1.8 | grep SONAME
 0x000000000000000e (SONAME)             Library soname: [libclang.so.21.1]
```

### Normal Behavior

To use LLVM/Clang 21.1, `PATH` is configured as follows.

```
$ export PATH="/usr/lib/llvm21/bin:${PATH}"
```

This results in the LLVM/Clang 21.1 version of `llvm-config` to be used.  It
specifies the library directory needed to link to that version.

```
$ which llvm-config
/usr/lib/llvm21/bin/llvm-config
$ llvm-config --libdir
/usr/lib/llvm21/lib
```

The linker is therefore passed `-lclang` and `-L/usr/lib/llvm21/lib` options.
The linker resolves `/usr/lib/llvm21/lib/libclang.so`, the `SONAME` for that
shared library is queried, and `libclang.so.21.1` is linked.

At runtime, `libclang.so.21.1` must be found by the dynamic linker.  This is
done by searching various paths as described in the [`ld.so(8)` manual][],
which does not include the build-time `/usr/lib/llvm21/lib` configuration.  In
this case, `libclang.so.21.1` is found in default path `/usr/lib`, and the
correct shared library is loaded.

When building a Haskell library/executable, shared libraries of all
dependencies are linked.  To make this work, linking options are stored in the
package database.

In this demo, library `dep-clang` depends on `libclang`.  With the above
configuration, it links to the correct shared library.

```
$ cabal build dep-clang
...
$ find dist-newstyle -type f -name 'libHSdep-clang-*.so' \
  | xargs ldd \
  | grep libclang
        libclang.so.21.1 => /usr/lib/llvm21/lib/libclang.so.21.1 (0x00007fdc52000000)
```

The package database for `dep-clang` specifies the `clang` library and the
`/usr/lib/llvm21/include` include directory.

```
$ ghc-pkg describe --package-db=dist-newstyle/packagedb/ghc-9.10.3 dep-clang
...
extra-libraries:      clang
...
include-dirs:
    /usr/lib/llvm21/include
    .../a-dep-clang/cbits
    .../dist-newstyle/build/x86_64-linux/ghc-9.10.3/dep-clang-0.0.0.0/build/cbits
...
```

Executable `demo` depends on library `dep-clang`, so it is also linked with
`-L/usr/lib/llvm21/include` and `-lclang` options.  If there are no issues
(described below) then it works fine: the executable is linked to
`libclang.so.21.1` just like the `dep-clang` library.

### The Issue

The issue is that configuration for other dependencies can cause the wrong
shared library to be linked.

Library `dep-z` depends on the [`zlib`][] package, which uses FFI by default,
linking to the `z` system library.  The `zlib` package uses `pkg-config` to
configure linking options.  Since the shared library is in the system default
library directory (`/usr/lib`), one generally does not specify a `-L` option.
A flag must be specified to force output of the system library directory.

```
$ pkg-config --libs zlib
-lz
$ pkg-config --libs --keep-system-libs zlib
-L/usr/lib -lz
```

Cabal configures the `pkg-config` program to always set the
`PKG_CONFIG_ALLOW_SYSTEM_LIBS` environment variable (in
[`pkgConfigProgram`][]), which does the same thing.  The
[`pkg-config` manual][] specifies the following.

> `PKG_CONFIG_ALLOW_SYSTEM_LIBS`
>
> Don't strip `-L/usr/lib` out of libs

Executable `demo` also depends on library `dep-z`, so it is passed
`-L/usr/lib` in addition to `-L/usr/lib/llvm21/include`.  Which version of the
`clang` shared library that is linked depends on the ordering of these
options, which users have no control over.

* When `-L/usr/lib/llvm21/lib` is first, the linker resolves
  `/usr/lib/llvm21/lib/libclang.so`, the `SONAME` for that shared library is
  queried, and `libclang.so.21.1` is linked.  This is the correct library.
* When `-L/usr/lib` is first, the linker resolves `/usr/lib/libclang.so`, the
  `SONAME` for that shared library is queried, and `libclang.so.22.1` is
  linked.  This is *not* the correct library.

This minimal demo demonstrates *both* of these cases.  When building
`dep-clang` separately, `-L/usr/lib/llvm21/lib` is first and the correct
library is linked.

```
$ cabal clean
$ cabal build dep-clang
$ cabal build -v3 --ghc-options=-v demo 2>&1 | tee build.log
...
$ grep ^gcc build.log | tail -n 1 | tr ' ' '\n' | grep '^-L/usr'
-L/usr/lib/llvm21/lib
-L/usr/lib
$ find dist-newstyle -type f -name demo | xargs ldd | grep libclang
        libclang.so.21.1 => /usr/lib/libclang.so.21.1 (0x00007f3b8a800000)
$ cabal run demo
Hello from dep-clang (clang version 21.1.8)!
Hello from dep-z!
```

When building `all`, `-L/usr/lib` is first and the incorrect library is
linked.

```
$ cabal clean
$ cabal build -v3 --ghc-options=-v all 2>&1 | tee build.log
...
$ grep ^gcc build.log | tail -n 1 | tr ' ' '\n' | grep '^-L/usr'
-L/usr/lib
-L/usr/lib/llvm21/lib
$ find dist-newstyle -type f -name demo | xargs ldd | grep libclang
        libclang.so.22.1 => /usr/lib/libclang.so.22.1 (0x00007f2bf6800000)
$ cabal run demo
Hello from dep-clang (clang version 22.1.5)!
Hello from dep-z!
```

### Multiple Versions

We ran into this issue during development of [`hs-bindgen`][], which uses
the [`libclang-bindings`][] package to interface with LLVM/Clang.  In that
case, when `libclang-bindings` is linked to `libclang.so.21.1`, the
`hs-bindgen:internal` library is linked to `libclang.so.22.1` as well as the
`libclang-bindings` library.  With that transitive dependency, the
`hs-bindgen` libraries and executables end up being linked to *two* versions
of `libclang`.

```
$ find dist-newstyle -type f -name hs-bindgen-cli | xargs ldd | grep libclang
        libclang.so.21.1 => /usr/lib/libclang.so.21.1 (0x00007f2ef7e00000)
        libclang.so.22.1 => /usr/lib/libclang.so.22.1 (0x00007ff723c00000
```

This behavior is not reproduced in this demo.

[`clang`]: https://archlinux.org/packages/extra/x86_64/clang/
[`clang21`]: https://archlinux.org/packages/extra/x86_64/clang21/
[`hs-bindgen`]: https://github.com/well-typed/hs-bindgen
[`ld.so(8)` manual]: https://man7.org/linux/man-pages/man8/ld.so.8.html
[`libclang-bindings`]: https://github.com/well-typed/libclang-bindings
[`llvm`]: https://archlinux.org/packages/extra/x86_64/llvm/
[`llvm21`]: https://archlinux.org/packages/extra/x86_64/llvm21/
[`pkg-config` manual]: https://linux.die.net/man/1/pkg-config
[`pkgConfigProgram`]: https://github.com/haskell/cabal/blob/f444d1b9334a09a33b4c340aebfced4f31631aba/Cabal/src/Distribution/Simple/Program/Builtin.hs#L363-L374
[`zlib`]: https://hackage.haskell.org/package/zlib
[Arch Linux]: https://archlinux.org/
[LLVM/Clang]: https://github.com/llvm/llvm-project
