{-# LANGUAGE CApiFFI #-}

module DepClang (hello) where

import qualified Foreign
import qualified Foreign.C

#include <clang_version.h>

foreign import capi unsafe "clang_version.h clang_version_getClangVersionString"
  getClangVersionString :: Foreign.C.CString -> IO ()

getClangVersion :: IO String
getClangVersion = Foreign.allocaBytes bufferSize $ \buffer -> do
    getClangVersionString buffer
    Foreign.C.peekCString buffer
  where
    bufferSize :: Int
    bufferSize = #const CLANG_VERSION_BUFFER_SIZE

hello :: IO ()
hello = do
    clangVersion <- getClangVersion
    putStrLn $ "Hello from dep-clang (" ++ clangVersion ++ ")!"
