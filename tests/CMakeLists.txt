cmake_minimum_required(VERSION 3.16)
project(AppManagerUiTests LANGUAGES CXX)

# The backend's logic (src/AppManager, AppSections) on the
# library, with fake package modules and a fake Basecamp: no SDK, no host.

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

set(BASECAMP_INSTALLER_COMMON_DIR "" CACHE PATH "basecamp-installer-common's source")
set(LOGOS_PACKAGE_INCLUDE_DIR "" CACHE PATH "logos-package's headers (<logos/semver.hpp>)")

find_package(Qt6 REQUIRED COMPONENTS Core Gui Network Test)

include(${BASECAMP_INSTALLER_COMMON_DIR}/cmake/BasecampInstallerCommon.cmake)

set(APP_SRC ${CMAKE_CURRENT_SOURCE_DIR}/../src)
add_library(app_manager_core STATIC
    ${BASECAMP_INSTALLER_COMMON_SOURCES}
    ${APP_SRC}/AppManager.h
    ${APP_SRC}/AppManager.cpp
    ${APP_SRC}/AppSections.h
    ${APP_SRC}/AppSections.cpp)
target_include_directories(app_manager_core
    PUBLIC ${APP_SRC} ${BASECAMP_INSTALLER_COMMON_INCLUDE_DIRS}
    PRIVATE ${LOGOS_PACKAGE_INCLUDE_DIR})
target_link_libraries(app_manager_core PUBLIC Qt6::Core Qt6::Network)
target_compile_options(app_manager_core PRIVATE -Wall -Wextra -Werror)

enable_testing()
foreach(t app_sections app_manager)
    add_executable(tst_${t} cpp/tst_${t}.cpp)
    # Gui: QStandardItemModel, for a source the sections test drives.
    target_link_libraries(tst_${t} PRIVATE app_manager_core Qt6::Gui Qt6::Test)
    target_compile_options(tst_${t} PRIVATE -Wall -Wextra -Werror)
    add_test(NAME ${t} COMMAND tst_${t})
endforeach()
