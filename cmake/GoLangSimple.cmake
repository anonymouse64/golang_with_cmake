
# For automatic testing using go test
# Every target added will have a go test call added to it if there's a corresponding
# "file_test.go" alongside it
include(CTest)
enable_testing()

set(GOPATH "${CMAKE_CURRENT_BINARY_DIR}/go")
file(MAKE_DIRECTORY ${GOPATH})

set(GO_COVERAGE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/coverage")
file(MAKE_DIRECTORY ${GO_COVERAGE_DIRECTORY})

# Make sure to clean up the gopath and the go coverage directory
set_property(DIRECTORY APPEND PROPERTY ADDITIONAL_MAKE_CLEAN_FILES ${GOPATH} ${GO_COVERAGE_DIRECTORY})

# ADD_GO_INSTALLABLE_PROGRAM allows for adding a new go progam target
function(ADD_GO_INSTALLABLE_PROGRAM)
	# First parse the arguments
	set(oneValueArgs TARGET MAIN_SOURCE IMPORT_PATH)
	set(multiValueArgs SOURCE_DIRECTORIES)
	cmake_parse_arguments(GO_PROGRAM "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN} )

	# This variable tracks the copy of the main file inside the gopath
	set(GO_PROGRAM_GOPATH ${GOPATH}/src/${GO_PROGRAM_IMPORT_PATH})
	get_filename_component(GO_PROGRAM_GOPATH_MAIN_SOURCE_DIR ${GO_PROGRAM_GOPATH}/${GO_PROGRAM_MAIN_SOURCE} DIRECTORY)

	# This is for tracking changes to the original go file
	get_filename_component(MAIN_SRC_ABS ${GO_PROGRAM_MAIN_SOURCE} ABSOLUTE)
	get_filename_component(MAIN_SRC_ABS_DIR ${MAIN_SRC_ABS} DIRECTORY)
	get_filename_component(MAIN_SRC_DIR ${GO_PROGRAM_MAIN_SOURCE} DIRECTORY)

	# Add the target for copying the files over
	add_custom_target(${GO_PROGRAM_TARGET}_copy)

	# First copy over the individual source file for this executable
	add_custom_command(TARGET ${GO_PROGRAM_TARGET}_copy
		COMMAND ${CMAKE_COMMAND} -E
		copy ${MAIN_SRC_ABS} ${GO_PROGRAM_GOPATH}/${GO_PROGRAM_MAIN_SOURCE}
		# The copy command depends on the original source file
		DEPENDS ${MAIN_SRC_ABS})

	# Now copy the specified source directories over into the gopath
	foreach(SourceDir ${GO_PROGRAM_SOURCE_DIRECTORIES})
		add_custom_command(TARGET ${GO_PROGRAM_TARGET}_copy
			COMMAND ${CMAKE_COMMAND} -E
			copy_directory ${SourceDir} ${GO_PROGRAM_GOPATH}/${SourceDir}
			WORKING_DIRECTORY ${CMAKE_SOURCE_DIR})
	endforeach(SourceDir)

	# Add the actual build target
	add_custom_target(${GO_PROGRAM_TARGET} ALL)
	add_dependencies(${GO_PROGRAM_TARGET} ${GO_PROGRAM_TARGET}_copy) 

	# First before building the target, we automatically fetch all of the dependencies declared 
	# in the go file using go get
	add_custom_command(TARGET ${GO_PROGRAM_TARGET}
		COMMAND env GOPATH=${GOPATH} go get -d -t ./...
		WORKING_DIRECTORY ${GO_PROGRAM_GOPATH_MAIN_SOURCE_DIR}
		DEPENDS ${GO_PROGRAM_TARGET}_copy)

	# Now actually setup the build to go build the file inside of the gopath
	add_custom_command(TARGET ${GO_PROGRAM_TARGET}
		COMMAND env GOPATH=${GOPATH} go build 
		-o "${CMAKE_CURRENT_BINARY_DIR}/${GO_PROGRAM_TARGET}"
		${CMAKE_GO_FLAGS} ${GO_PROGRAM_GOPATH}/${GO_PROGRAM_MAIN_SOURCE}
		WORKING_DIRECTORY ${GO_PROGRAM_GOPATH}
		DEPENDS ${GO_PROGRAM_TARGET}_copy)

	# Install the executable
	install(PROGRAMS ${CMAKE_CURRENT_BINARY_DIR}/${GO_PROGRAM_TARGET} DESTINATION bin)

	# Now check if we should add tests for this executable
	string(REGEX REPLACE "\\.[^.]*$" "" GO_PROGRAM_MAIN_SOURCE_ROOT_FILE ${GO_PROGRAM_GOPATH}/${GO_PROGRAM_MAIN_SOURCE})
	set(GO_PROGRAM_MAIN_SOURCE_TEST_FILE ${GO_PROGRAM_MAIN_SOURCE_ROOT_FILE}_test.go)
	if(EXISTS ${GO_PROGRAM_MAIN_SOURCE_TEST_FILE})
		get_filename_component(GO_PROGRAM_TEST_FILE_NAME ${GO_PROGRAM_MAIN_SOURCE_TEST_FILE} NAME)
		message(STATUS "Found go test file : ${MAIN_SRC_DIR}/${GO_PROGRAM_TEST_FILE_NAME}")
		message(STATUS "Enabling testing for ${GO_PROGRAM_TARGET}")
		# Add a dummy test command to copy the test file over 
		add_test(NAME ${GO_PROGRAM_TARGET}Test_copy
			COMMAND "${CMAKE_COMMAND}" -E
			copy ${MAIN_SRC_ABS_DIR}/${GO_PROGRAM_TEST_FILE_NAME} ${GO_PROGRAM_GOPATH}/${MAIN_SRC_DIR}/${GO_PROGRAM_TEST_FILE_NAME})

		# Finally add the test
		add_test(NAME ${GO_PROGRAM_TARGET}Test
			COMMAND env GOPATH=${GOPATH} go test -cover
			WORKING_DIRECTORY ${GO_PROGRAM_GOPATH_MAIN_SOURCE_DIR})

		# Make the test target dependent on the copy target
		set_tests_properties(${GO_PROGRAM_TARGET}Test PROPERTIES 
			DEPENDS ${GO_PROGRAM_TARGET}Test_copy)
	endif()
endfunction(ADD_GO_INSTALLABLE_PROGRAM)
