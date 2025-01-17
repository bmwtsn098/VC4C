####
# Find Clang compiler and tools to use
####
if(LLVMLIB_FRONTEND AND NOT CROSS_COMPILE AND NOT SPIRV_CLANG_FOUND)
	if(NOT CLANG_FOUND)
		find_program(CLANG_FOUND clang NAMES clang clang-3.9 clang-4.0 clang-5.0 clang-6.0 clang-7 clang-8 clang-9 clang-10 clang-11 clang-12 clang-13)
	endif()
	if (NOT LLVM_DIS_FOUND)
		find_program(LLVM_DIS_FOUND llvm-dis NAMES llvm-dis llvm-dis-3.9 llvm-dis-4.0 llvm-dis-5.0 llvm-dis-6.0 llvm-dis-7 llvm-dis-8 llvm-dis-9 llvm-dis-10 llvm-dis-11 llvm-dis-12 llvm-dis-13)
	endif()
	if (NOT LLVM_AS_FOUND)
		find_program(LLVM_AS_FOUND llvm-as NAMES llvm-as llvm-as-3.9 llvm-as-4.0 llvm-as-5.0 llvm-as-6.0 llvm-as-7 llvm-as-8 llvm-as-9 llvm-as-10 llvm-as-11 llvm-as-12 llvm-as-13)
	endif()
	if(NOT LLVM_LINK_FOUND)
		find_program(LLVM_LINK_FOUND llvm-link NAMES llvm-link llvm-link-3.9 llvm-link-4.0 llvm-link-5.0 llvm-link-6.0 llvm-link-7 llvm-link-8 llvm-link-9 llvm-link-10 llvm-link-11 llvm-link-12 llvm-link-12)
	endif()
	if(CLANG_FOUND)
		message(STATUS "CLang compiler found: " ${CLANG_FOUND})
		EXECUTE_PROCESS( COMMAND ${CLANG_FOUND} --version OUTPUT_VARIABLE clang_full_version_string )
		string (REGEX REPLACE ".*clang version ([0-9]+\\.[0-9]+).*" "\\1" CLANG_VERSION_STRING ${clang_full_version_string})
	else()
		message(WARNING "No CLang compiler found!")
	endif()
	if(LLVM_DIS_FOUND)
		message(STATUS "LLVM-dis found: " ${LLVM_DIS_FOUND})
	endif()
	if(LLVM_AS_FOUND)
		message(STATUS "LLVM-as found: " ${LLVM_AS_FOUND})
	endif()
	if(LLVM_LINK_FOUND)
		message(STATUS "LLVM-link found: " ${LLVM_LINK_FOUND})
	endif()
endif()
