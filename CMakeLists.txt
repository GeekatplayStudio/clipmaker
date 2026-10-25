cmake_minimum_required(VERSION 3.20)
# Pick the newest SDK whose stubs this machine's linker can read (older CLT ld
# cannot parse the MacOSX27 .tbd files).
if(NOT CMAKE_OSX_SYSROOT)
  foreach(_sdk MacOSX26.5.sdk MacOSX26.sdk MacOSX15.4.sdk MacOSX15.sdk)
    if(EXISTS "/Library/Developer/CommandLineTools/SDKs/${_sdk}")
      set(CMAKE_OSX_SYSROOT "/Library/Developer/CommandLineTools/SDKs/${_sdk}" CACHE PATH "" FORCE)
      break()
    endif()
  endforeach()
endif()

project(ClipMaker LANGUAGES C CXX OBJC OBJCXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OBJCXX_STANDARD 20)
set(CMAKE_OSX_DEPLOYMENT_TARGET "13.0" CACHE STRING "" FORCE)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

file(GLOB CORE_SRC src/core/*.cpp)
file(GLOB PLATFORM_SRC src/platform/*.mm)
file(GLOB APP_SRC src/app/*.mm)

add_executable(ClipMaker MACOSX_BUNDLE ${CORE_SRC} ${PLATFORM_SRC} ${APP_SRC})
target_include_directories(ClipMaker PRIVATE src)
target_compile_options(ClipMaker PRIVATE -O2 -Wall -Wno-unused-function)
set_source_files_properties(${PLATFORM_SRC} ${APP_SRC} PROPERTIES COMPILE_FLAGS "-fobjc-arc")

set_target_properties(ClipMaker PROPERTIES
  MACOSX_BUNDLE_INFO_PLIST ${CMAKE_SOURCE_DIR}/Info.plist
  OUTPUT_NAME "ClipMaker")

target_link_libraries(ClipMaker PRIVATE
  "-framework Cocoa" "-framework AVFoundation" "-framework AVKit"
  "-framework CoreMedia" "-framework CoreVideo" "-framework CoreText"
  "-framework Speech" "-framework Vision" "-framework Accelerate"
  "-framework QuartzCore" "-framework UniformTypeIdentifiers")

# Ad-hoc sign so TCC (speech permission) and sandbox-free frameworks behave.
add_custom_command(TARGET ClipMaker POST_BUILD
  COMMAND codesign --force --deep --sign - "$<TARGET_BUNDLE_DIR:ClipMaker>" || true
  COMMENT "Ad-hoc code signing")
