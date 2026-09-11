macro(configure_sdl2_frontend _NAME_TARGET)

    if(IOS)

        # There are no system SDL2 packages to find on iOS, so build the
        # three libraries from source and link them statically into the app
        # bundle.
        set(BUILD_SHARED_LIBS OFF)
        set(SDL_SHARED OFF)
        set(SDL_STATIC ON)

        # Fixes _ftol2_sse already defined
        set(SDL_LIBC ON)

        include(FetchContent)

        FetchContent_Declare(sdl2
                GIT_REPOSITORY "https://github.com/libsdl-org/SDL"
                GIT_TAG "SDL2"
        )
        FetchContent_GetProperties(sdl2)
        if(NOT sdl2_POPULATED)
            FetchContent_Populate(sdl2)
        endif()
        add_subdirectory(${sdl2_SOURCE_DIR} ${sdl2_BINARY_DIR} EXCLUDE_FROM_ALL)
        set(SDL2_INCLUDE_DIRS ${sdl2_SOURCE_DIR} ${sdl2_BINARY_DIR})
        set(SDL2_LIBRARIES SDL2-static SDL2::SDL2main SDL2::SDL2)

        set(SDL2TTF_VENDORED 1)
        FetchContent_Declare(sdl2_ttf
                GIT_REPOSITORY "https://github.com/libsdl-org/SDL_ttf"
                GIT_TAG "SDL2"
        )
        FetchContent_GetProperties(sdl2_ttf)
        if(NOT sdl2_ttf_POPULATED)
            FetchContent_Populate(sdl2_ttf)
        endif()
        add_subdirectory(${sdl2_ttf_SOURCE_DIR} ${sdl2_ttf_BINARY_DIR} EXCLUDE_FROM_ALL)
        set(SDL2_TTF_INCLUDE_DIRS ${sdl2_ttf_SOURCE_DIR} ${sdl2_ttf_BINARY_DIR})
        set(SDL2_TTF_LIBRARIES SDL2_ttf::SDL2_ttf-static)

        set(SDL2IMAGE_VENDORED 1)
        set(SDL2IMAGE_BACKEND_IMAGEIO OFF)
        set(SDL2IMAGE_AVIF OFF)
        set(SDL2IMAGE_WEBP OFF)
        set(SDL2IMAGE_TIF OFF)
        FetchContent_Declare(sdl2_image
                GIT_REPOSITORY "https://github.com/libsdl-org/SDL_image"
                GIT_TAG "SDL2"
        )
        FetchContent_GetProperties(sdl2_image)
        if(NOT sdl2_image_POPULATED)
            FetchContent_Populate(sdl2_image)
        endif()
        add_subdirectory(${sdl2_image_SOURCE_DIR} ${sdl2_image_BINARY_DIR} EXCLUDE_FROM_ALL)
        set(SDL2_IMAGE_INCLUDE_DIRS ${sdl2_image_SOURCE_DIR} ${sdl2_image_BINARY_DIR})
        set(SDL2_IMAGE_LIBRARIES SDL2_image::SDL2_image-static)

        target_link_libraries(${_NAME_TARGET} PRIVATE
            ${SDL2_LIBRARIES}
            ${SDL2_TTF_LIBRARIES}
            ${SDL2_IMAGE_LIBRARIES}
        )
        target_include_directories(${_NAME_TARGET} PRIVATE
            ${SDL2_INCLUDE_DIRS}
            ${SDL2_TTF_INCLUDE_DIRS}
            ${SDL2_IMAGE_INCLUDE_DIRS}
        )
        target_compile_definitions(${_NAME_TARGET} PRIVATE USE_SDL2)

        message(STATUS "Support for SDL2 front end - Ready (vendored for iOS)")

    else()

        find_package(PkgConfig REQUIRED)

        pkg_check_modules(SDL2 QUIET IMPORTED_TARGET sdl2)
        pkg_check_modules(SDL2_TTF QUIET IMPORTED_TARGET SDL2_ttf>=2.0.0)
        pkg_check_modules(SDL2_IMAGE QUIET IMPORTED_TARGET SDL2_image>=2.0.0)

        if(SDL2_FOUND AND SDL2_IMAGE_FOUND AND SDL2_TTF_FOUND)

            include(PkgConfigHelpers)
            angband_pkgconfig_select_target(SDL2       SDL2_SELECTED)
            angband_pkgconfig_select_target(SDL2_TTF   SDL2_TTF_SELECTED)
            angband_pkgconfig_select_target(SDL2_IMAGE SDL2_IMAGE_SELECTED)

            target_link_libraries(${_NAME_TARGET} PRIVATE
                ${SDL2_SELECTED}
                ${SDL2_TTF_SELECTED}
                ${SDL2_IMAGE_SELECTED}
            )
            target_compile_definitions(${_NAME_TARGET} PRIVATE USE_SDL2)

            message(STATUS "Support for SDL2 front end - Ready")

        else()

            message(FATAL_ERROR "Support for SDL2 front end - Failed")

        endif()

    endif()

endmacro()
