AC_PREREQ([2.71])
AC_INIT([dep-clang],[0.0.0.0])

AC_ARG_WITH([compiler],[AS_HELP_STRING([--with-compiler], [Haskell compiler])])

AC_PATH_PROG([LLVM_CONFIG],[llvm-config],[])
AS_IF([test -z "$LLVM_CONFIG"], [AC_MSG_ERROR([llvm-config not found])])

wt_clang_lib='clang'
AC_SUBST([CLANG_LIB], ["$wt_clang_lib"])
LIBS="${LIBS} -l${wt_clang_lib}"

wt_clang_lib_dir="$("$LLVM_CONFIG" --libdir)"
AC_SUBST([CLANG_LIB_DIR], ["$wt_clang_lib_dir"])
LDFLAGS="${LDFLAGS} -L${wt_clang_lib_dir}"

wt_clang_inc_dir="$("$LLVM_CONFIG" --includedir)"
AC_SUBST([CLANG_INC_DIR], ["$wt_clang_inc_dir"])
CPPFLAGS="${CPPFLAGS} -I${wt_clang_inc_dir}"

AC_CHECK_HEADER(
  [clang-c/Index.h],
  [],
  [AC_MSG_ERROR([Cannot find libclang headers])]
)

AC_CHECK_LIB(
  [$wt_clang_lib],
  [clang_createIndex],
  [],
  [AC_MSG_ERROR([Cannot link against libclang])]
)

AC_CONFIG_FILES([dep-clang.buildinfo])
AC_OUTPUT
