package main

import (
	"testing"

	"github.com/anonymouse64/golang_with_cmake_example/addition"
)

func TestAdd2Num(t *testing.T) {
	total := addition.Add2Num(5, 5)
	if total != 10 {
		t.Errorf("MyFunc was incorrect, got: %d, want: %d.", total, 10)
	}

}
