project(golang-with-cmake-example)
cmake_minimum_required(VERSION 3.2 FATAL_ERROR)

include("cmake/Golang.cmake")

# Add the main target executable
ADD_GO_INSTALLABLE_PROGRAM(TARGET example-executable
							MAIN_SOURCE cmd/example-executable/main.go
							IMPORT_PATH github.com/anonymouse64/golang_with_cmake_example
							SOURCE_DIRECTORIES cmd addition
	)

