cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

# Link libnotify for desktop notifications
pkg_check_modules(LIBNOTIFY libnotify)
if (LIBNOTIFY_FOUND)
  target_include_directories(${BINARY_NAME} PRIVATE ${LIBNOTIFY_INCLUDE_DIRS})
  target_link_libraries(${BINARY_NAME} PRIVATE ${LIBNOTIFY_LIBRARIES})
  target_compile_options(${BINARY_NAME} PRIVATE ${LIBNOTIFY_CFLAGS_OTHER})
endif()

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# If building on X11, link against X11 to resolve Xlib symbols used for WM_CLASS.
find_package(X11)
if (X11_FOUND)
  target_include_directories(${BINARY_NAME} PRIVATE ${X11_INCLUDE_DIR})
  target_link_libraries(${BINARY_NAME} PRIVATE ${X11_LIBRARIES})
endif()
