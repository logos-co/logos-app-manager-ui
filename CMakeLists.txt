cmake_minimum_required(VERSION 3.14)
project(AppManagerUiPlugin LANGUAGES CXX)

if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found. Set LOGOS_MODULE_BUILDER_ROOT.")
endif()

# The name comes from metadata.json: the backend is built from it as the core
# module `app_manager_ui_backend`.
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/metadata.json" METADATA_JSON)
string(JSON MODULE_NAME GET ${METADATA_JSON} name)

# basecamp-installer-common, staged by the flake's preConfigure.
include(${CMAKE_CURRENT_SOURCE_DIR}/vendor/basecamp-installer-common/cmake/BasecampInstallerCommon.cmake)
# Who signed a package (its trust sources): ICU's lookalike checks.
find_package(ICU REQUIRED COMPONENTS uc i18n)

logos_module(
    NAME ${MODULE_NAME}
    REP_FILE src/app_manager_ui.rep
    SOURCES
        src/AppManagerBackend.h
        src/AppManagerBackend.cpp
        src/AppManager.h
        src/AppManager.cpp
        src/AppSections.h
        src/AppSections.cpp
        src/ModuleCalls.h
        src/ModuleCalls.cpp
        ${BASECAMP_INSTALLER_COMMON_SOURCES}
        ${BASECAMP_INSTALLER_COMMON_TRUST_SOURCES}
        ${BASECAMP_INSTALLER_COMMON_PACKAGE_TRUST_SOURCES}
    LINK_LIBRARIES
        ICU::i18n
        ICU::uc
    INCLUDE_DIRS
        ${CMAKE_CURRENT_SOURCE_DIR}/src
        # <logos/semver.hpp>, staged from logos-package; headers only.
        ${CMAKE_CURRENT_SOURCE_DIR}/vendor
        ${BASECAMP_INSTALLER_COMMON_INCLUDE_DIRS}
)
