package main

import (
	"fmt"

	"github.com/anonymouse64/golang_with_cmake_example/addition"
)

func main() {
	fmt.Println("This is an example program that uses an external library with cmake")
	fmt.Println("2 + 2 is %d", addition.Add2Num(2, 2))
}
