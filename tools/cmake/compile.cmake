
# Convert to cmake path(for Windows)
file(TO_CMAKE_PATH "${SDK_PATH}" SDK_PATH)

message(STATUS "SDK_PATH:${SDK_PATH}")

get_filename_component(parent_dir ${CMAKE_PARENT_LIST_FILE} DIRECTORY)
get_filename_component(current_dir ${CMAKE_CURRENT_LIST_FILE} DIRECTORY)
get_filename_component(parent_dir_name ${parent_dir} NAME)

function(register_component)
    get_filename_component(component_dir ${CMAKE_CURRENT_LIST_FILE} DIRECTORY)
    get_filename_component(component_name ${component_dir} NAME)
    message(STATUS "[register component: ${component_name} ], path:${component_dir}")

    # Add src to lib
    if(ADD_SRCS)
        add_library(${component_name} STATIC ${ADD_SRCS})
        set(include_type PUBLIC)
    else()
        add_library(${component_name} INTERFACE)
        set(include_type INTERFACE)
    endif()

    # Add include
    foreach(include_dir ${ADD_INCLUDE})
        get_filename_component(abs_dir ${include_dir} ABSOLUTE BASE_DIR ${component_dir})
        if(NOT IS_DIRECTORY ${abs_dir})
            message(FATAL_ERROR "${CMAKE_CURRENT_LIST_FILE}: ${include_dir} not found!")
        endif()
        target_include_directories(${component_name} ${include_type} ${abs_dir})
    endforeach()

    # Add private include
    foreach(include_dir ${ADD_PRIVATE_INCLUDE})
        if(${include_type} STREQUAL INTERFACE)
            message(FATAL_ERROR "${CMAKE_CURRENT_LIST_FILE}: ADD_PRIVATE_INCLUDE set but no source file！")
        endif()
        get_filename_component(abs_dir ${include_dir} ABSOLUTE BASE_DIR ${component_dir})
        if(NOT IS_DIRECTORY ${abs_dir})
            message(FATAL_ERROR "${CMAKE_CURRENT_LIST_FILE}: ${include_dir} not found!")
        endif()
        target_include_directories(${component_name} PRIVATE ${abs_dir})
    endforeach()

    # Add blobal config include
    target_include_directories(${component_name} PUBLIC ${global_config_dir})

    # Add requirements
    target_link_libraries(${component_name} ${ADD_REQUIREMENTS})

    # Add static lib
    if(ADD_STATIC_LIB)
        target_link_libraries(${component_name} "${component_dir}/${ADD_STATIC_LIB}")
    endif()
endfunction()

function(is_path_component ret param_path)
    set(res 1)
    get_filename_component(abs_dir ${param_path} ABSOLUTE)

    if(NOT IS_DIRECTORY "${abs_dir}")
        set(res 0)
    endif()

    get_filename_component(base_dir ${abs_dir} NAME)
    string(SUBSTRING "${base_dir}" 0 1 first_char)

    if(NOT first_char STREQUAL ".")
        if(NOT EXISTS "${abs_dir}/CMakeLists.txt")
            set(res 0)
        endif()
    else()
        set(res 0)
    endif()

    set(${ret} ${res} PARENT_SCOPE)
endfunction()

function(get_python python version info_str)
    set(res 1)
    execute_process(COMMAND python3 --version RESULT_VARIABLE cmd_res OUTPUT_VARIABLE cmd_out)
    if(${cmd_res} EQUAL 0)
        set(${python} python3 PARENT_SCOPE)
        set(${version} 3 PARENT_SCOPE)
        set(${info_str} ${cmd_out} PARENT_SCOPE)
    else()
        execute_process(COMMAND python --version RESULT_VARIABLE cmd_res OUTPUT_VARIABLE cmd_out)
        if(${cmd_res} EQUAL 0)
            set(${python} python PARENT_SCOPE)
            set(${version} 2 PARENT_SCOPE)
            set(${info_str} ${cmd_out} PARENT_SCOPE)
        endif()
    endif()
endfunction(get_python python)


macro(project name)
    
    get_filename_component(current_dir ${CMAKE_CURRENT_LIST_FILE} DIRECTORY)
    set(PROJECT_SOURCE_DIR ${current_dir})
    set(PROJECT_BINARY_DIR "${current_dir}/build")

    # Find components in SDK's components folder, register components
    file(GLOB component_dirs ${SDK_PATH}/components/*)
    foreach(component_dir ${component_dirs})
        is_path_component(is_component ${component_dir})
        if(is_component)
            message(STATUS "Find component: ${component_dir}")
            get_filename_component(base_dir ${component_dir} NAME)
            list(APPEND components_dirs ${component_dir})
            if(EXISTS ${component_dir}/Kconfig)
                message(STATUS "Find component Kconfig of ${base_dir}")
                list(APPEND components_kconfig_files ${component_dir}/Kconfig)
            endif()
            if(EXISTS ${component_dir}/config_defaults.mk)
                message(STATUS "Find component defaults config of ${base_dir}")
                list(APPEND kconfig_defaults_files ${component_dir}/config_defaults.mk)
            endif()
        endif()
    endforeach()

    # Find components in project folder
    file(GLOB project_component_dirs ${PROJECT_SOURCE_DIR}/*)
    foreach(component_dir ${project_component_dirs})
        is_path_component(is_component ${component_dir})
        if(is_component)
            message(STATUS "find component: ${component_dir}")
            get_filename_component(base_dir ${component_dir} NAME)
            list(APPEND components_dirs ${component_dir})
            if(${base_dir} STREQUAL "main")
                set(main_component 1)
            endif()
            if(EXISTS ${component_dir}/Kconfig)
                message(STATUS "Find component Kconfig of ${base_dir}")
                list(APPEND components_kconfig_files ${component_dir}/Kconfig)
            endif()
            if(EXISTS ${component_dir}/config_defaults.mk)
                message(STATUS "Find component defaults config of ${base_dir}")
                list(APPEND kconfig_defaults_files ${component_dir}/config_defaults.mk)
            endif()
        endif()
    endforeach()
    if(NOT main_component)
        message(FATAL_ERROR "=================\nCan not find main component(folder) in project folder!!\n=================")
    endif()
    if(EXISTS ${PROJECT_SOURCE_DIR}/config_defaults.mk)
        message(STATUS "Find project defaults config")
        list(APPEND kconfig_defaults_files ${PROJECT_SOURCE_DIR}/config_defaults.mk)
    endif()

    # Generate config file from Kconfig
    get_python(python python_version python_info_str)
    if(NOT python)
        message(FATAL_ERROR "python not found, please install python firstly(python3 recommend)!")
    endif()
    message(STATUS "python command: ${python}, version: ${python_info_str}")
    string(REPLACE ";" " " components_kconfig_files "${components_kconfig_files}")
    set(generate_config_cmd ${python}  ${SDK_PATH}/tools/kconfig/genconfig.py
                            --kconfig ${SDK_PATH}/Kconfig
                            --defaults ${kconfig_defaults_files}
                            --menuconfig False
                            --env "SDK_PATH=${SDK_PATH}"
                            --env "PROJECT_PATH=${PROJECT_SOURCE_DIR}"
                            --output makefile ${PROJECT_BINARY_DIR}/config/global_config.mk
                            --output cmake  ${PROJECT_BINARY_DIR}/config/global_config.cmake
                            --output header ${PROJECT_BINARY_DIR}/config/global_config.h
                            )
    set(generate_config_cmd2 ${python}  ${SDK_PATH}/tools/kconfig/genconfig.py
                            --kconfig ${SDK_PATH}/Kconfig
                            --defaults ${kconfig_defaults_files}
                            --menuconfig True
                            --env "SDK_PATH=${SDK_PATH}"
                            --env "PROJECT_PATH=${PROJECT_SOURCE_DIR}"
                            --output makefile ${PROJECT_BINARY_DIR}/config/global_config.mk
                            --output cmake  ${PROJECT_BINARY_DIR}/config/global_config.cmake
                            --output header ${PROJECT_BINARY_DIR}/config/global_config.h
                            )
    execute_process(COMMAND ${generate_config_cmd} RESULT_VARIABLE cmd_res)
    if(NOT cmd_res EQUAL 0)
        message(FATAL_ERROR "Check Kconfig content")
    endif()

    # Include confiurations
    set(global_config_dir "${PROJECT_BINARY_DIR}/config")
    include(${global_config_dir}/global_config.cmake)

    # Config toolchain
    if(CONFIG_TOOLCHAIN_PATH)
        if(NOT IS_DIRECTORY ${CONFIG_TOOLCHAIN_PATH})
            message(FATAL_ERROR "TOOLCHAIN_PATH set error:${CONFIG_TOOLCHAIN_PATH}")
        endif()
        if(WIN32)
            file(TO_CMAKE_PATH ${CONFIG_TOOLCHAIN_PATH} TOOLCHAIN_PATH)
            set(CMAKE_C_COMPILER ${CONFIG_TOOLCHAIN_PATH}/${CONFIG_TOOLCHAIN_PREFIX}gcc.exe)
            set(CMAKE_CXX_COMPILER ${CONFIG_TOOLCHAIN_PATH}/${CONFIG_TOOLCHAIN_PREFIX}g++.exe)
            set(CMAKE_ASM_COMPILER ${CONFIG_TOOLCHAIN_PATH}/${CONFIG_TOOLCHAIN_PREFIX}gcc.exe)
        else()
            set(CMAKE_C_COMPILER ${CONFIG_TOOLCHAIN_PATH}/${CONFIG_TOOLCHAIN_PREFIX}gcc)
            set(CMAKE_CXX_COMPILER ${CONFIG_TOOLCHAIN_PATH}/${CONFIG_TOOLCHAIN_PREFIX}g++)
            set(CMAKE_ASM_COMPILER ${CONFIG_TOOLCHAIN_PATH}/${CONFIG_TOOLCHAIN_PREFIX}gcc)
        endif()
    endif()

    # Declare project
    _project(${name} ASM C CXX)


    # Add dependence: update configfile, append time and git info for global config header file
    # we didn't generate build info for cmake and makefile for if we do, it will always rebuild cmake
    # everytime we execute make
    set(gen_build_info_config_cmd ${python}  ${SDK_PATH}/tools/kconfig/update_build_info.py
                                  --configfile header ${PROJECT_BINARY_DIR}/config/global_config.h
                                  )
    add_custom_target(update_build_info COMMAND ${gen_build_info_config_cmd})

    # Create exe_src.c to satisfy cmake's `add_executable` interface!
    set(exe_src ${CMAKE_BINARY_DIR}/exe_src.c)
    add_executable(${name} "${exe_src}")
    add_custom_command(OUTPUT ${exe_src} COMMAND ${CMAKE_COMMAND} -E touch ${exe_src} VERBATIM)
    add_custom_target(gen_exe_src DEPENDS "${exe_src}")
    add_dependencies(${name} gen_exe_src)
    

    # Call CMakeLists.txt
    foreach(component_dir ${components_dirs})
        get_filename_component(base_dir ${component_dir} NAME)
        add_subdirectory(${component_dir} ${base_dir})
        add_dependencies(${base_dir} update_build_info) # add build info dependence
    endforeach()
    

    # Add menuconfig target for makefile
    add_custom_target(menuconfig COMMAND ${generate_config_cmd2})

    # Add main component(lib)
    target_link_libraries(${name} main)
endmacro()

