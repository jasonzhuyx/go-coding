package utils

import (
	"regexp"
	"unicode"
)

func GetGraphemeCount(str string) int {
	regex := regexp.MustCompile("\\PM\\pM*|.")
	return len(regex.FindAllString(str, -1))
}

func GetGraphemeCountInString(str string) int {

	checked := false
	count := 0

	for _, ch := range str {
		if !unicode.Is(unicode.M, ch) {
			count++

			if checked == false {
				checked = true
			}

		} else if checked == false {
			count++
		}
	}

	return count
}
