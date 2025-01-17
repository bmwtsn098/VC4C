####
# Find either LLVM SPIR-V translator ...
####

if(NOT SPIRV_COMPILER_ROOT AND NOT SPIRV_TRANSLATOR_ROOT)
	# Try to detect the location of the SPIRV-LLVM-Translator binaries
	find_program(LLVM_SPIRV_FOUND NAMES llvm-spirv HINTS "/opt/SPIRV-LLVM-Translator/build/tools/llvm-spirv/")
	if(LLVM_SPIRV_FOUND)
		get_filename_component(SPIRV_TRANSLATOR_ROOT "${LLVM_SPIRV_FOUND}" DIRECTORY)
	endif()
endif()
if(SPIRV_TRANSLATOR_ROOT)
	message(STATUS "Khronos OpenCL toolkit: ${SPIRV_TRANSLATOR_ROOT}")
	# The translator uses the built-in clang
	find_program(SPIRV_CLANG_FOUND clang NAMES clang clang-3.9 clang-4.0 clang-5.0 clang-6.0 clang-7 clang-8 clang-9 clang-10 clang-11 clang-12 clang-13)
	find_program(LLVM_DIS_FOUND llvm-dis NAMES llvm-dis llvm-dis-3.9 llvm-dis-4.0 llvm-dis-5.0 llvm-dis-6.0 llvm-dis-7 llvm-dis-8 llvm-dis-9 llvm-dis-10 llvm-dis-11 llvm-dis-12 llvm-dis-13)
	find_program(LLVM_AS_FOUND llvm-as NAMES llvm-as llvm-as-3.9 llvm-as-4.0 llvm-as-5.0 llvm-as-6.0 llvm-as-7 llvm-as-8 llvm-as-9 llvm-as-10 llvm-as-11 llvm-as-12 llvm-as-13)
	find_program(LLVM_LINK_FOUND llvm-link NAMES llvm-link llvm-link-3.9 llvm-link-4.0 llvm-link-5.0 llvm-link-6.0 llvm-link-7 llvm-link-8 llvm-link-9 llvm-link-10 llvm-link-11 llvm-link-12 llvm-link-13)
	find_file(SPIRV_LLVM_SPIR_FOUND llvm-spirv PATHS ${SPIRV_TRANSLATOR_ROOT} NO_DEFAULT_PATH)
	if(SPIRV_CLANG_FOUND)
		message(STATUS "Khronos OpenCL compiler: ${SPIRV_CLANG_FOUND}")
	endif()
	if(LLVM_DIS_FOUND)
		# Since the LLVM SPIR-V translator is based on the default clang, we can also use the default LLVM disassembler.
		message(STATUS "LLVM-dis found: " ${LLVM_DIS_FOUND})
	endif()
	if(LLVM_AS_FOUND)
		# Since the LLVM SPIR-V translator is based on the default clang, we can also use the default LLVM assembler.
		message(STATUS "LLVM-as found: " ${LLVM_AS_FOUND})
	endif()
	if(LLVM_LINK_FOUND)
		# Using the LLVM linker allows us to compile without PCH, but link in standard-library module which is much faster.
		# Since the LLVM SPIR-V translator is based on the default clang, we can also use the default LLVM linker.
		message(STATUS "LLVM-link found: " ${LLVM_LINK_FOUND})
		set(SPIRV_LINK_MODULES ON)
	endif()
	if(NOT CLANG_VERSION_STRING)
		EXECUTE_PROCESS( COMMAND ${SPIRV_CLANG_FOUND} --version OUTPUT_VARIABLE clang_full_version_string )
		string (REGEX REPLACE ".*clang version ([0-9]+\\.[0-9]+).*" "\\1" CLANG_VERSION_STRING ${clang_full_version_string})
	endif()
endif()

####
# ... or find deprecated LLVM SPIR-V compiler
####
if(SPIRV_FRONTEND AND NOT SPIRV_TRANSLATOR_ROOT)
	if(NOT SPIRV_COMPILER_ROOT)
		# Try to detect the location of the SPIRV-LLVM binaries
		find_program(LLVM_SPIRV_FOUND NAMES llvm-spirv HINTS "/opt/SPIRV-LLVM/build/bin/")
		if(LLVM_SPIRV_FOUND)
			get_filename_component(SPIRV_COMPILER_ROOT "${LLVM_SPIRV_FOUND}" DIRECTORY)
		endif()
	endif()
	if(SPIRV_COMPILER_ROOT)
		message(STATUS "Khronos OpenCL toolkit: ${SPIRV_COMPILER_ROOT}")
		find_file(SPIRV_CLANG_FOUND clang PATHS ${SPIRV_COMPILER_ROOT} NO_DEFAULT_PATH)
		find_file(SPIRV_LLVM_SPIR_FOUND llvm-spirv PATHS ${SPIRV_COMPILER_ROOT} NO_DEFAULT_PATH)
		if(SPIRV_CLANG_FOUND)
			message(STATUS "Khronos OpenCL compiler: ${SPIRV_CLANG_FOUND}")
		endif()
		set(SPIRV_LINK_MODULES OFF)
	endif()
endif()

if(SPIRV_FRONTEND AND NOT SPIRV_COMPILER_ROOT AND NOT SPIRV_TRANSLATOR_ROOT)
	message(WARNING "SPIR-V frontend configured, but no SPIR-V compiler found!")
endif()

####
# Enable SPIR-V Tools front-end
####

# If the complete tool collection is provided, compile the SPIR-V front-end
if(SPIRV_LLVM_SPIR_FOUND AND SPIRV_FRONTEND)
	message(STATUS "Compiling SPIR-V front-end...")
	# Try to find precompiled SPIR-V Tools, e.g. as provided by spirv-tools debian package
	include(FindPkgConfig)
	pkg_check_modules(SPIRV_TOOLS SPIRV-Tools)
	if(SPIRV_TOOLS_FOUND)
		set(SPIRV_Tools_HEADERS ${SPIRV_TOOLS_INCLUDEDIR})
		set(SPIRV_Tools_LIBS ${SPIRV_TOOLS_LINK_LIBRARIES})
	elseif(DEPENDENCIES_USE_FETCH_CONTENT)
		# CMake 3.14 introduces https://cmake.org/cmake/help/latest/module/FetchContent.html which allows us to run the configuration step
		# of the downloaded dependencies at CMake configuration step and therefore, we have the proper targets available.
		include(FetchContent)
		FetchContent_Declare(spirv-tools-project GIT_REPOSITORY https://github.com/KhronosGroup/SPIRV-Tools.git)
		# CMake configuration flags for SPIRV-Tools project
		set(SPIRV_SKIP_EXECUTABLES OFF)
		set(SPIRV_SKIP_TESTS ON)
		set(SPIRV-Headers_SOURCE_DIR ${SPIRV_HEADERS_SOURCE_DIR})
		FetchContent_MakeAvailable(spirv-tools-project)
		# Set variables expected by the VC4CC library to the SPIRV-Tools libraries.
		set(SPIRV_Tools_LIBS SPIRV-Tools SPIRV-Tools-opt SPIRV-Tools-link)
		# the headers are already included by linking the targets
		set(SPIRV_Tools_HEADERS "")
		# we need to export these targets, since they are required by VC4CC which we export
		# export(TARGETS SPIRV-Headers SPIRV-Tools SPIRV-Tools-opt SPIRV-Tools-link FILE spirv-exports.cmake)
	else()
		ExternalProject_Add(spirv-tools-project
			DEPENDS 			SPIRV-Headers-project-build
			PREFIX 				${CMAKE_BINARY_DIR}/spirv-tools
			GIT_REPOSITORY 		https://github.com/KhronosGroup/SPIRV-Tools.git
			UPDATE_COMMAND 		git pull -f https://github.com/KhronosGroup/SPIRV-Tools.git
			CMAKE_ARGS 			-DSPIRV_SKIP_EXECUTABLES:BOOL=ON -DSPIRV_SKIP_TESTS:BOOL=ON -DSPIRV-Headers_SOURCE_DIR:STRING=${SOURCE_DIR}
			STEP_TARGETS 		build
			EXCLUDE_FROM_ALL	TRUE
			TIMEOUT 			30		#Timeout for downloads, in seconds
			CMAKE_ARGS
			  -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
			  -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
			  -DCMAKE_FIND_ROOT_PATH=${CMAKE_FIND_ROOT_PATH}
		)
		ExternalProject_Get_Property(spirv-tools-project BINARY_DIR)
		ExternalProject_Get_Property(spirv-tools-project SOURCE_DIR)
		set(SPIRV_Tools_LIBS "-Wl,--whole-archive ${BINARY_DIR}/source/libSPIRV-Tools.a ${BINARY_DIR}/source/opt/libSPIRV-Tools-opt.a ${BINARY_DIR}/source/link/libSPIRV-Tools-link.a -Wl,--no-whole-archive")
		set(SPIRV_Tools_HEADERS ${SOURCE_DIR}/include)
		add_dependencies(SPIRV-Dependencies spirv-tools-project-build)
	endif()
	set(VC4C_ENABLE_SPIRV_TOOLS_FRONTEND ON)
endif()

####
# Find additional SPIR-V tools
####
find_program(SPIRV_LINK_FOUND spirv-link)
# XXX We could also look for spirv-as and spirv-dis here, but the SPIR-V text format they support is not compatible with llvm-spirv textual format.
# Unless we decide to completely switch to this format, we don't have any use for these tools.
if(SPIRV_LINK_FOUND)
	message(STATUS "SPIRV-link found: ${SPIRV_LINK_FOUND}")
endif()
