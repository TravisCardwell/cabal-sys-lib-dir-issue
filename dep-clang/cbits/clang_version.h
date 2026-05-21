#ifndef CLANG_VERSION_H
#define CLANG_VERSION_H

#include <clang-c/Index.h>
#include <string.h>

#define CLANG_VERSION_BUFFER_SIZE 256

static inline void clang_version_getClangVersionString(char *result) {
  CXString cxstring = clang_getClangVersion();
  strncpy(result, clang_getCString(cxstring), CLANG_VERSION_BUFFER_SIZE - 1);
  result[CLANG_VERSION_BUFFER_SIZE - 1] = '\0';
  clang_disposeString(cxstring);
}

#endif
