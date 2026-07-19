cmake_minimum_required(VERSION 3.10)
set(PROJECT_NAME "multi_window_manager")
project(${PROJECT_NAME} LANGUAGES CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "multi_window_manager_plugin")

add_library(${PLUGIN_NAME} SHARED
  "multi_window_manager.cc"
  "multi_window_manager_plugin.cc"
  "mwm_linux_classic_gl_survivor.cc"
)
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
# Set MWM_LOG_ENABLED=ON to enable diagnostic logging (off by default).
option(MWM_LOG_ENABLED "Enable MWM diagnostic logging" OFF)
if(MWM_LOG_ENABLED)
  target_compile_definitions(${PLUGIN_NAME} PRIVATE MWM_LOG_ENABLED)
endif()

target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
  "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)

# List of absolute paths to libraries that should be bundled with the plugin
set(multi_window_manager_bundled_libraries
  ""
  PARENT_SCOPE
)
