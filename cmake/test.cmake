enable_testing()

link_directories("${CMAKE_INSTALL_PREFIX}/lib")

# This is for tests that aren't run as part of `make test`. These are useful
# for manual or component tests that you don't want to necessarily run as
# part of the unit test suite.
function(add_standalone_gtest testName)
  set(options "")
  set(oneValueArgs "")
  set(multiValueArgs SRCS DEPS)
  cmake_parse_arguments(add_standalone_gtest
      "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  add_executable(${testName}
                 ${add_standalone_gtest_SRCS})
  target_link_libraries(${testName}
      gmock_main gtest gmock "-pthread"
      ${add_standalone_gtest_DEPS})
endfunction (add_standalone_gtest)

# This function is use for gtest/gmock-dependent libraries for use in other
# unit tests (i.e. does not link a `main` symbol).
function(add_gtest_lib testName)
  set(options "")
  set(oneValueArgs "")
  set(multiValueArgs SRCS DEPS)
  cmake_parse_arguments(add_gtest_lib
      "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  add_library(${testName}
              ${add_gtest_lib_SRCS})
  target_link_libraries(${testName}
      gtest gmock "-pthread" ${add_gtest_lib_DEPS})
endfunction (add_gtest_lib)

# Adds a unit test named `${NAME}_test`.
#
# The file `${NAME}_test.cc` is implicitly added as a source.
# Additional source files can be declared with the `SRCS` parameter.
#
# Test executable is implicitly linked with `gtest` and `gmock`.
# Additional libraries can be linked with the `LIBS` parameter.
#
# Additional dependencies can be declares with the `DEPS` parameter.
function(add_cpp_test NAME)
  set(TEST_NAME "${NAME}_test")
  cmake_parse_arguments(ARG "" "" "SRCS;LIBS;DEPS" ${ARGN})

  add_executable(
    ${TEST_NAME}
      "${TEST_NAME}.cc"
      ${ARG_SRCS}
  )
  add_test(${TEST_NAME} ${TEST_NAME})

  target_link_libraries(
    ${TEST_NAME}
      ${ARG_LIBS}
      gmock_main
      gtest
      gmock
      shared-executable
  )
endfunction(add_cpp_test)

# Adds a unit test named `${NAME}_test`, which is part of the `unit_tests` target.
#
# The file `${NAME}_test.cc` is implicitly added as a source.
# Additional source files can be declared with the `SRCS` parameter.
#
# Test executable is implicitly linked with `gtest` and `gmock`.
# Additional libraries can be linked with the `LIBS` parameter.
#
# Additional dependencies can be declares with the `DEPS` parameter.
add_custom_target(unit_tests)
function(add_unit_test NAME)
  cmake_parse_arguments(ARG "" "" "SRCS;LIBS;DEPS" ${ARGN})
  add_cpp_test(${NAME} SRCS ${ARG_SRCS} LIBS ${ARG_LIBS} DEPS ${ARG_DEPS})
  add_dependencies(unit_tests "${NAME}_test")
endfunction(add_unit_test)
