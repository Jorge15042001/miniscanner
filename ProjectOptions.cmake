include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(miniscanner_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(miniscanner_setup_options)
  option(miniscanner_ENABLE_HARDENING "Enable hardening" ON)
  option(miniscanner_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    miniscanner_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    miniscanner_ENABLE_HARDENING
    OFF)

  miniscanner_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR miniscanner_PACKAGING_MAINTAINER_MODE)
    option(miniscanner_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(miniscanner_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(miniscanner_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(miniscanner_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(miniscanner_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(miniscanner_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(miniscanner_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(miniscanner_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(miniscanner_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(miniscanner_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(miniscanner_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(miniscanner_ENABLE_PCH "Enable precompiled headers" OFF)
    option(miniscanner_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(miniscanner_ENABLE_IPO "Enable IPO/LTO" ON)
    option(miniscanner_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(miniscanner_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(miniscanner_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(miniscanner_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(miniscanner_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(miniscanner_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(miniscanner_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(miniscanner_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(miniscanner_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(miniscanner_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(miniscanner_ENABLE_PCH "Enable precompiled headers" OFF)
    option(miniscanner_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      miniscanner_ENABLE_IPO
      miniscanner_WARNINGS_AS_ERRORS
      miniscanner_ENABLE_USER_LINKER
      miniscanner_ENABLE_SANITIZER_ADDRESS
      miniscanner_ENABLE_SANITIZER_LEAK
      miniscanner_ENABLE_SANITIZER_UNDEFINED
      miniscanner_ENABLE_SANITIZER_THREAD
      miniscanner_ENABLE_SANITIZER_MEMORY
      miniscanner_ENABLE_UNITY_BUILD
      miniscanner_ENABLE_CLANG_TIDY
      miniscanner_ENABLE_CPPCHECK
      miniscanner_ENABLE_COVERAGE
      miniscanner_ENABLE_PCH
      miniscanner_ENABLE_CACHE)
  endif()

  miniscanner_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (miniscanner_ENABLE_SANITIZER_ADDRESS OR miniscanner_ENABLE_SANITIZER_THREAD OR miniscanner_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(miniscanner_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(miniscanner_global_options)
  if(miniscanner_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    miniscanner_enable_ipo()
  endif()

  miniscanner_supports_sanitizers()

  if(miniscanner_ENABLE_HARDENING AND miniscanner_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR miniscanner_ENABLE_SANITIZER_UNDEFINED
       OR miniscanner_ENABLE_SANITIZER_ADDRESS
       OR miniscanner_ENABLE_SANITIZER_THREAD
       OR miniscanner_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${miniscanner_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${miniscanner_ENABLE_SANITIZER_UNDEFINED}")
    miniscanner_enable_hardening(miniscanner_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(miniscanner_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(miniscanner_warnings INTERFACE)
  add_library(miniscanner_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  miniscanner_set_project_warnings(
    miniscanner_warnings
    ${miniscanner_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(miniscanner_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    configure_linker(miniscanner_options)
  endif()

  include(cmake/Sanitizers.cmake)
  miniscanner_enable_sanitizers(
    miniscanner_options
    ${miniscanner_ENABLE_SANITIZER_ADDRESS}
    ${miniscanner_ENABLE_SANITIZER_LEAK}
    ${miniscanner_ENABLE_SANITIZER_UNDEFINED}
    ${miniscanner_ENABLE_SANITIZER_THREAD}
    ${miniscanner_ENABLE_SANITIZER_MEMORY})

  set_target_properties(miniscanner_options PROPERTIES UNITY_BUILD ${miniscanner_ENABLE_UNITY_BUILD})

  if(miniscanner_ENABLE_PCH)
    target_precompile_headers(
      miniscanner_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(miniscanner_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    miniscanner_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(miniscanner_ENABLE_CLANG_TIDY)
    miniscanner_enable_clang_tidy(miniscanner_options ${miniscanner_WARNINGS_AS_ERRORS})
  endif()

  if(miniscanner_ENABLE_CPPCHECK)
    miniscanner_enable_cppcheck(${miniscanner_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(miniscanner_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    miniscanner_enable_coverage(miniscanner_options)
  endif()

  if(miniscanner_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(miniscanner_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(miniscanner_ENABLE_HARDENING AND NOT miniscanner_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR miniscanner_ENABLE_SANITIZER_UNDEFINED
       OR miniscanner_ENABLE_SANITIZER_ADDRESS
       OR miniscanner_ENABLE_SANITIZER_THREAD
       OR miniscanner_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    miniscanner_enable_hardening(miniscanner_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
