
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
	set(options CONFIGURE_FILE)
	set(oneValueArgs TARGET MAIN_SOURCE IMPORT_PATH)
	set(multiValueArgs SOURCE_DIRECTORIES TEST_PACKAGES GO_ENVIRONMENT GET_ENVIRONMENT)
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

	# First copy over the individual source file for this executable only if CONFIGURE_FILE isn't true
	# otherwise we configure the file and output it to the gopath
	if(${GO_PROGRAM_CONFIGURE_FILE})
		message(STATUS "Configuring file ${GO_PROGRAM_MAIN_SOURCE}")
		# Configure the file first
		configure_file(${GO_PROGRAM_MAIN_SOURCE} ${GO_PROGRAM_GOPATH}/${GO_PROGRAM_MAIN_SOURCE}.configured)
		# Now setup the generate call for handling generator expressions
		file(GENERATE
			OUTPUT ${GO_PROGRAM_MAIN_SOURCE}
			INPUT ${GO_PROGRAM_GOPATH}/${GO_PROGRAM_MAIN_SOURCE}.configured)
	else()
		add_custom_command(TARGET ${GO_PROGRAM_TARGET}_copy
			COMMAND ${CMAKE_COMMAND} -E
			copy ${MAIN_SRC_ABS} ${GO_PROGRAM_GOPATH}/${GO_PROGRAM_MAIN_SOURCE}
			# The copy command depends on the original source file
			DEPENDS ${MAIN_SRC_ABS})
	endif()

	# Now copy the specified source directories over into the gopath
	foreach(SourceDir ${GO_PROGRAM_SOURCE_DIRECTORIES})
		add_custom_command(TARGET ${GO_PROGRAM_TARGET}_copy
			COMMAND ${CMAKE_COMMAND} -E
			copy_directory ${SourceDir} ${GO_PROGRAM_GOPATH}/${SourceDir}
			WORKING_DIRECTORY ${CMAKE_SOURCE_DIR})
	endforeach(SourceDir)

	# We don't need to show the progress for copying files
	set_target_properties(${GO_PROGRAM_TARGET}_copy PROPERTIES RULE_MESSAGES OFF)

	# Add the actual build target which depends on the source directories being updated
	add_custom_target(${GO_PROGRAM_TARGET} ALL)
	add_dependencies(${GO_PROGRAM_TARGET} ${GO_PROGRAM_TARGET}_copy)

	# First before building the target, we automatically fetch all of the dependencies declared 
	# in the go file using go get
	add_custom_command(TARGET ${GO_PROGRAM_TARGET}
		COMMAND ${CMAKE_COMMAND} -E env ${GO_PROGRAM_GO_ENVIRONMENT} GOPATH=${GOPATH} go get -v -d -t ./...
		WORKING_DIRECTORY ${GO_PROGRAM_GOPATH_MAIN_SOURCE_DIR}
		DEPENDS ${GO_PROGRAM_TARGET}_copy)

	# Now actually setup the build to go build the file inside of the gopath
	add_custom_command(TARGET ${GO_PROGRAM_TARGET}
		COMMAND ${CMAKE_COMMAND} -E env ${GO_PROGRAM_GO_ENVIRONMENT} GOPATH=${GOPATH} go build -v 
		-o ${CMAKE_CURRENT_BINARY_DIR}/${GO_PROGRAM_TARGET}
		${CMAKE_GO_FLAGS} ${GO_PROGRAM_GOPATH}/${GO_PROGRAM_MAIN_SOURCE}
		WORKING_DIRECTORY ${GO_PROGRAM_GOPATH}
		DEPENDS ${GO_PROGRAM_TARGET}_copy)

	# Install the executable
	install(PROGRAMS ${CMAKE_CURRENT_BINARY_DIR}/${GO_PROGRAM_TARGET} DESTINATION bin)

	# Now check if we should add tests for this executable
	# This regex deletes the file extension so we can append _test.go to see if that test file exists
	string(REGEX REPLACE "\\.[^.]*$" "" GO_PROGRAM_MAIN_SOURCE_ROOT_FILE ${CMAKE_SOURCE_DIR}/${GO_PROGRAM_MAIN_SOURCE})
	set(GO_PROGRAM_MAIN_SOURCE_TEST_FILE ${GO_PROGRAM_MAIN_SOURCE_ROOT_FILE}_test.go)
	if(EXISTS ${GO_PROGRAM_MAIN_SOURCE_TEST_FILE})
		# This is to support multiple packages being specified for a single cover profile with go test
		# but requires golang 1.10, see https://github.com/golang/go/issues/6909
		# Then the call to go test can use the variable GO_PROGRAM_FULL_TEST_PACKAGES and get more accurate testing results
		set(GO_PROGRAM_FULL_TEST_PACKAGES "")
		foreach(test_pkg ${GO_PROGRAM_TEST_PACKAGES})
			list(APPEND GO_PROGRAM_FULL_TEST_PACKAGES ${GO_PROGRAM_IMPORT_PATH}/${test_pkg})
		endforeach(test_pkg)
		get_filename_component(GO_PROGRAM_TEST_FILE_NAME ${GO_PROGRAM_MAIN_SOURCE_TEST_FILE} NAME)
		message(STATUS "Found go test file : ${MAIN_SRC_DIR}/${GO_PROGRAM_TEST_FILE_NAME}")
		message(STATUS "Enabling testing for ${GO_PROGRAM_TARGET}")
		# Add a dummy test command to copy the test file over 
		add_test(NAME ${GO_PROGRAM_TARGET}Test_copy
			COMMAND ${CMAKE_COMMAND} -E
			copy ${MAIN_SRC_ABS_DIR}/${GO_PROGRAM_TEST_FILE_NAME} ${GO_PROGRAM_GOPATH}/${MAIN_SRC_DIR}/${GO_PROGRAM_TEST_FILE_NAME})

		# Add the go test command
		add_test(NAME ${GO_PROGRAM_TARGET}Test
			COMMAND ${CMAKE_COMMAND} -E env GOPATH=${GOPATH} go test ${GO_PROGRAM_FULL_TEST_PACKAGES} -coverprofile=${GO_COVERAGE_DIRECTORY}/${GO_PROGRAM_TARGET}coverage.out
			WORKING_DIRECTORY ${GO_PROGRAM_GOPATH_MAIN_SOURCE_DIR})

		# Also add a coverage html generation output - this will generate coverage statistics in a HTML viewer of the code
		add_test(NAME ${GO_PROGRAM_TARGET}coverage
			COMMAND ${CMAKE_COMMAND} -E env GOPATH=${GOPATH} go tool cover -o ${GO_COVERAGE_DIRECTORY}/${GO_PROGRAM_TARGET}.html -html=${GO_COVERAGE_DIRECTORY}/${GO_PROGRAM_TARGET}coverage.out
			WORKING_DIRECTORY ${GO_PROGRAM_GOPATH_MAIN_SOURCE_DIR})

		# Make the test target dependent on the copy target
		set_tests_properties(${GO_PROGRAM_TARGET}Test PROPERTIES 
			DEPENDS ${GO_PROGRAM_TARGET}Test_copy)
	endif()
endfunction(ADD_GO_INSTALLABLE_PROGRAM)


# ADD_GO_PACKAGE_FOLDER allows for adding a new go progam target
function(ADD_GO_PACKAGE_FOLDER)
	# First parse the arguments
	set(oneValueArgs TARGET MAIN_FOLDER IMPORT_PATH)
	set(multiValueArgs TEST_PACKAGES CONFIGURE_FILES GO_ENVIRONMENT GET_ENVIRONMENT)
	cmake_parse_arguments(GO_PACKAGE "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN} )

	# This variable tracks the copy of the main file inside the gopath
	set(GO_PACKAGE_GOPATH ${GOPATH}/src/${GO_PACKAGE_IMPORT_PATH})
	set(GO_PACKAGE_GOPATH_MAIN_FOLDER ${GO_PACKAGE_GOPATH}/${GO_PACKAGE_MAIN_FOLDER})

	# Add the target for copying the files over
	add_custom_target(${GO_PACKAGE_TARGET}_copy)

	# First we need to build up the list of files to configure and files to copy over
	# We can get the files to copy over by globbing the package directory, then iterating over
	# that list and only adding those files that don't appear inside CONFIGURE_FILES
	# Also note that this includes all files - not just go files in case there is test data, etc. in the folders
	# we want to copy that over too
	file(GLOB_RECURSE GO_PACKAGE_ALL_ITEMS 
		RELATIVE ${CMAKE_CURRENT_LIST_DIR}
		${CMAKE_CURRENT_LIST_DIR}/${GO_PACKAGE_MAIN_FOLDER}/* )
	set(GO_PACKAGE_COPY_FILES "")
	set(GO_PACKAGE_ABSOLUTE_COPY_FILES "")
	foreach(PackageItem ${GO_PACKAGE_ALL_ITEMS})
		# Check this file/directory against all of the specified files that need to be configured
		set(FILE_FOUND FALSE)
		foreach(ConfigureFile ${GO_PACKAGE_CONFIGURE_FILES})
			if(${ConfigureFile} STREQUAL ${PackageItem})
				# This item should be configured, not copied
				set(FILE_FOUND TRUE)
				break()
			endif()
		endforeach()
		if(NOT ${FILE_FOUND})
			# This package item wasn't in the list of files to be configured, so if it's not a directory we should add it to the list of things to copy
			# If it's a directory we don't want to copy it, as copying in a directory may inadvertantly copy in any configure files
			if(NOT IS_DIRECTORY  ${PackageItem})
				# We use the relative paths for creating the destination directories
				list(APPEND GO_PACKAGE_COPY_FILES ${PackageItem})
				# The absolute versions are for copying all of the files in one command
				get_filename_component(ABSOLUTE_PACKAGE_FILE ${PackageItem} ABSOLUTE)
				list(APPEND GO_PACKAGE_ABSOLUTE_COPY_FILES ${ABSOLUTE_PACKAGE_FILE})
			endif()
		endif()
	endforeach(PackageItem)


	# Before we can copy all of the files over, we have to make sure that all of the output directories exist
	set(GO_PACKAGE_CONFIGURE_DIRS "")
	foreach(CopyFile ${GO_PACKAGE_COPY_FILES})
		get_filename_component(CopyFileDirectory ${CopyFile} DIRECTORY)
		# Create this directory in case it doesn't exist
		# Need to iterate over the list of directories we have previously found that need to be created
		set(DIR_FOUND FALSE)
		foreach(DirItem ${GO_PACKAGE_CONFIGURE_DIRS})
			if(${CopyFileDirectory} STREQUAL ${DirItem})
				# This item should be configured, not copied
				set(DIR_FOUND TRUE)
				break()
			endif()
		endforeach()
		if(NOT ${DIR_FOUND})
			list(APPEND GO_PACKAGE_CONFIGURE_DIRS ${CopyFileDirectory})
			add_custom_command(TARGET ${GO_PACKAGE_TARGET}_copy
				COMMAND ${CMAKE_COMMAND} -E
				make_directory ${GO_PACKAGE_GOPATH}/${CopyFileDirectory})
		endif()
		# Copy this file over as well
		add_custom_command(TARGET ${GO_PACKAGE_TARGET}_copy
				COMMAND ${CMAKE_COMMAND} -E
				copy ${CMAKE_CURRENT_LIST_DIR}/${CopyFile} ${GO_PACKAGE_GOPATH}/${CopyFileDirectory})
	endforeach(CopyFile)

	# We don't need to show the progress for copying files
	set_target_properties(${GO_PACKAGE_TARGET}_copy PROPERTIES RULE_MESSAGES OFF)

	# Configure the files requested to be configured - also call file(GENERATE...) on them, so that we can support
	# both standard $VAR and @VAR@ as well as generator expressions like $<...>
	foreach(ConfigureFile ${GO_PACKAGE_CONFIGURE_FILES})
		message(STATUS "Configuring file ${ConfigureFile}")
		# Configure the file first
		configure_file(${ConfigureFile} ${GO_PACKAGE_GOPATH}/${ConfigureFile}.configured)
		# Now setup the generate call
		file(GENERATE
			OUTPUT ${GO_PACKAGE_GOPATH}/${ConfigureFile}
			INPUT ${GO_PACKAGE_GOPATH}/${ConfigureFile}.configured)
	endforeach(ConfigureFile)

	# Add the actual build target which depends on the files being updated
	add_custom_target(${GO_PACKAGE_TARGET} ALL)
	add_dependencies(${GO_PACKAGE_TARGET} ${GO_PACKAGE_TARGET}_copy)

	# First before building the target, we automatically fetch all of the dependencies declared 
	# in the go file using go get
	add_custom_command(TARGET ${GO_PACKAGE_TARGET}
		COMMAND ${CMAKE_COMMAND} -E env ${GO_PACKAGE_GO_ENVIRONMENT} GOPATH=${GOPATH} go get -v ${CMAKE_GO_FLAGS} -d -t ./...
		WORKING_DIRECTORY ${GO_PACKAGE_GOPATH_MAIN_FOLDER}
		DEPENDS ${GO_PACKAGE_TARGET}_copy)

	# Now actually setup the build to go build all of the packages inside of the package folder
	add_custom_command(TARGET ${GO_PACKAGE_TARGET}
		COMMAND ${CMAKE_COMMAND} -E env ${GO_PACKAGE_GO_ENVIRONMENT} GOPATH=${GOPATH} go build -v ${CMAKE_GO_FLAGS}  ./...
		WORKING_DIRECTORY ${GO_PACKAGE_GOPATH_MAIN_FOLDER}
		DEPENDS ${GO_PACKAGE_TARGET}_copy)

	# TODO: see if there's anything we should do about installing this package folder

	# TODO: finish implementing automatic tests for packages
	# Now check if we should add tests for this package
	# file(GLOB GO_PACKAGE_TEST_FILES *_test.go)
	# if(${GO_PACKAGE_TEST_FILES})
	# 	# This is to support multiple packages being specified for a single cover profile with go test
	# 	# but requires golang 1.10, see https://github.com/golang/go/issues/6909
	# 	# Then the call to go test can use the variable GO_PACKAGE_FULL_TEST_PACKAGES and get more accurate testing results
	# 	set(GO_PACKAGE_FULL_TEST_PACKAGES "")
	# 	foreach(test_pkg ${GO_PACKAGE_TEST_PACKAGES})
	# 		list(APPEND GO_PACKAGE_FULL_TEST_PACKAGES ${GO_PACKAGE_IMPORT_PATH}/${test_pkg})
	# 	endforeach(test_pkg)
	# 	get_filename_component(GO_PROGRAM_TEST_FILE_NAME ${GO_PROGRAM_MAIN_SOURCE_TEST_FILE} NAME)
	# 	message(STATUS "Found go test file : ${MAIN_SRC_DIR}/${GO_PROGRAM_TEST_FILE_NAME}")
	# 	message(STATUS "Enabling testing for ${GO_PACKAGE_TARGET}")
	# 	# Add a dummy test command to copy the test file over 
	# 	add_test(NAME ${GO_PACKAGE_TARGET}Test_copy
	# 		COMMAND "${CMAKE_COMMAND}" -E
	# 		copy ${MAIN_SRC_ABS_DIR}/${GO_PROGRAM_TEST_FILE_NAME} ${GO_PACKAGE_GOPATH}/${MAIN_SRC_DIR}/${GO_PROGRAM_TEST_FILE_NAME})

	# 	# Add the go test command
	# 	add_test(NAME ${GO_PACKAGE_TARGET}Test
	# 		COMMAND ${CMAKE_COMMAND} -E env GOPATH=${GOPATH} go test ${GO_PACKAGE_FULL_TEST_PACKAGES} -coverprofile=${GO_COVERAGE_DIRECTORY}/${GO_PACKAGE_TARGET}coverage.out
	# 		WORKING_DIRECTORY ${GO_PROGRAM_GOPATH_MAIN_SOURCE_DIR})

	# 	# Also add a coverage html generation output - this will generate coverage statistics in a HTML viewer of the code
	# 	add_test(NAME ${GO_PACKAGE_TARGET}coverage
	# 		COMMAND ${CMAKE_COMMAND} -E env GOPATH=${GOPATH} go tool cover -o ${GO_COVERAGE_DIRECTORY}/${GO_PACKAGE_TARGET}.html -html=${GO_COVERAGE_DIRECTORY}/${GO_PACKAGE_TARGET}coverage.out
	# 		WORKING_DIRECTORY ${GO_PROGRAM_GOPATH_MAIN_SOURCE_DIR})

	# 	# Make the test target dependent on the copy target
	# 	set_tests_properties(${GO_PACKAGE_TARGET}Test PROPERTIES 
	# 		DEPENDS ${GO_PACKAGE_TARGET}Test_copy)
	# endif()
endfunction(ADD_GO_PACKAGE_FOLDER)
