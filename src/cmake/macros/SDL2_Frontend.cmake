MACRO(CONFIGURE_SDL2_FRONTEND _NAME_TARGET)

    INCLUDE(FindPkgConfig)

    if(IOS)
        # Build static lib only
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
        if (NOT sdl2_POPULATED)
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
        if (NOT sdl2_ttf_POPULATED)
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
        if (NOT sdl2_image_POPULATED)
            FetchContent_Populate(sdl2_image)
        endif()
        add_subdirectory(${sdl2_image_SOURCE_DIR} ${sdl2_image_BINARY_DIR} EXCLUDE_FROM_ALL)
        set(SDL2_IMAGE_INCLUDE_DIRS ${sdl2_image_SOURCE_DIR} ${sdl2_image_BINARY_DIR})
        set(SDL2_IMAGE_LIBRARIES SDL2_image::SDL2_image-static)

        set(SDL2_FOUND True)
        set(SDL2_IMAGE_FOUND True)
        set(SDL2_TTF_FOUND True)

        TARGET_LINK_LIBRARIES(${_NAME_TARGET} PRIVATE ${SDL2_LIBRARIES} ${SDL2_TTF_LIBRARIES} ${SDL2_IMAGE_LIBRARIES})
        TARGET_INCLUDE_DIRECTORIES(${_NAME_TARGET} PRIVATE ${SDL2_INCLUDE_DIRS} ${SDL2_TTF_INCLUDE_DIRS} ${SDL2_IMAGE_INCLUDE_DIRS})
    else()

        PKG_SEARCH_MODULE(SDL2 sdl2)
        PKG_SEARCH_MODULE(SDL2_TTF SDL2_ttf>=2.0.0)
        PKG_SEARCH_MODULE(SDL2_IMAGE SDL2_image>=2.0.0)

        IF(SDL2_FOUND AND SDL2_IMAGE_FOUND AND SDL2_TTF_FOUND)

            TARGET_LINK_LIBRARIES(${_NAME_TARGET} PRIVATE ${SDL2_LIBRARIES} ${SDL2_TTF_LIBRARIES} ${SDL2_IMAGE_LIBRARIES})
            TARGET_INCLUDE_DIRECTORIES(${_NAME_TARGET} PRIVATE ${SDL2_INCLUDE_DIRS} ${SDL2_TTF_INCLUDE_DIRS} ${SDL2_IMAGE_INCLUDE_DIRS})
            TARGET_COMPILE_DEFINITIONS(${_NAME_TARGET} PRIVATE -D USE_SDL2)
            TARGET_COMPILE_OPTIONS(${_NAME_TARGET} PRIVATE ${SDL2_CFLAGS} ${SDL2_TTF_CFLAGS} ${SDL2_IMAGE_CFLAGS})
            TARGET_LINK_OPTIONS(${_NAME_TARGET} PRIVATE ${SDL2_LDFLAGS} ${SDL2_TTF_LDFLAGS} ${SDL2_IMAGE_LDFLAGS})
            MESSAGE(STATUS "Support for SDL2 front end - Ready")

        ELSE()

            MESSAGE(FATAL_ERROR "Support for SDL2 front end - Failed")

        ENDIF()
ENDIF()
ENDMACRO()
