# `PKG_CONFIG_ALLOW_SYSTEM_LIBS` may cause wrong library to be linked

**Describe the bug**

Cabal configures the `pkg-config` program using
[`PKG_CONFIG_ALLOW_SYSTEM_LIBS`][] (in [`pkgConfigProgram`][]), which results
in `-L/usr/lib` linker options to be used for some packages.  Other software
may configure a library directory to load a specific version.  When a Haskell
library/executable has (transitive) dependencies of both types, which library
is linked depends on the order of linker options, which users have no control
over and even varies with different Cabal usage.  The Haskell library is
statically linked, so this can even result in the library/executable being
linked to two different versions of the same system dependency.

```
$ ldd hs-bindgen-cli | grep libclang
        libclang.so.21.1 => /usr/lib/libclang.so.21.1 (0x00007f2ef7e00000)
        libclang.so.22.1 => /usr/lib/libclang.so.22.1 (0x00007ff723c00000
```

[`PKG_CONFIG_ALLOW_SYSTEM_LIBS`]: https://linux.die.net/man/1/pkg-config
[`pkgConfigProgram`]: https://github.com/haskell/cabal/blob/cabal-install-v3.16.1.0/Cabal/src/Distribution/Simple/Program/Builtin.hs#L375-L386

**To Reproduce**

Reproduction requires multiple versions of the same software, where the
library for the default is stored in `/usr/lib`.  I have tested on
[Arch Linux][] using LLVM/Clang 22.1 ([`llvm`][] and [`clang`][] packages)
and LLVM/Clang 21.1 ([`llvm21`][] and [`clang21`][] packages).

A [minimal demo][] (with a [README][] that contains more detail) has the
following components:

* Library `dep-clang` links to `libclang`.
* Library `dep-z` depends on the [`zlib`][] package, which uses FFI by
  default, linking to the `z` system library.  The `zlib` package uses
  `pkg-config` to configure linking options, and the shared library is in the
  system default library directory (`/usr/lib`).
* Executable `demo` depends on both of those.

To use LLVM/Clang 21.1, `PATH` is configured:

```
$ export PATH="/usr/lib/llvm21/bin:${PATH}"
```

When building `dep-clang` separately, `-L/usr/lib/llvm21/lib` is first and the
correct library is linked.

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

[Arch Linux]: https://archlinux.org/
[`clang`]: https://archlinux.org/packages/extra/x86_64/clang/
[`clang21`]: https://archlinux.org/packages/extra/x86_64/clang21/
[`llvm`]: https://archlinux.org/packages/extra/x86_64/llvm/
[`llvm21`]: https://archlinux.org/packages/extra/x86_64/llvm21/
[minimal demo]: https://github.com/TravisCardwell/cabal-sys-lib-dir-issue
[README]: https://github.com/TravisCardwell/cabal-sys-lib-dir-issue/blob/main/README.md
[`zlib`]: https://hackage.haskell.org/package/zlib

**Expected behavior**

When linking to the system dependency of a (transitive) Haskell dependency,
the same library should be linked.  For example, if the LLVM/Clang bindings
library is linked to `libclang.so.21.1`, then reverse-dependencies should be
linked to the same shared library.  Not doing so results in conflicting
versions.

**System information**

```
$ grep ^NAME /etc/os-release
NAME="Arch Linux"
$ uname -srm
Linux 7.0.7-arch1-1 x86_64
$ cabal --version
cabal-install version 3.16.1.0
compiled using version 3.16.1.0 of the Cabal library (in-tree)
$ ghc --version
The Glorious Glasgow Haskell Compilation System, version 9.10.3
```

**Additional context**

We ran into this issue during development of [`hs-bindgen`][], which uses
the [`libclang-bindings`][] package to interface with LLVM/Clang.  We
implemented a [workaround][] that is *not* user-friendly but at least enables
users to work around the issue.

[`hs-bindgen`]: https://github.com/well-typed/hs-bindgen
[`libclang-bindings`]: https://github.com/well-typed/libclang-bindings
[workaround]: https://github.com/well-typed/libclang-bindings/blob/1098461095df9875a12ec40b4df3f628d138016c/manual/README.md#workaround-linux
