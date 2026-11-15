package updater

import (
	"slices"
	"strings"
)

const (
	// maxLCSCells bounds the work of the line diff; larger inputs fall back to
	// reporting the whole differing middle part as removed and added.
	maxLCSCells = 4_000_000

	// prefixRemoved marks a line that only exists in the baseline plan.
	prefixRemoved = "-"
	// prefixAdded marks a line that only exists in the current plan.
	prefixAdded = "+"
)

// diffLines returns the lines that differ between a and b, prefixed with "-"
// (only in a) or "+" (only in b). Common leading and trailing lines are skipped.
func diffLines(a, b string) []string {
	as, bs := strings.Split(a, "\n"), strings.Split(b, "\n")
	// Plans of one project are almost identical, so trimming the common head
	// and tail keeps the quadratic LCS table small.
	start := 0
	for start < len(as) && start < len(bs) && as[start] == bs[start] {
		start++
	}
	endA, endB := len(as), len(bs)
	for endA > start && endB > start && as[endA-1] == bs[endB-1] {
		endA--
		endB--
	}
	midA, midB := as[start:endA], bs[start:endB]
	if len(midA)*len(midB) > maxLCSCells {
		return replaceAll(midA, midB)
	}
	return lcsDiff(midA, midB)
}

// replaceAll reports every line of a as removed and every line of b as added.
// It is the fallback for inputs too large for the LCS table.
func replaceAll(a, b []string) []string {
	out := make([]string, 0, len(a)+len(b))
	for _, line := range a {
		out = append(out, prefixRemoved+line)
	}
	for _, line := range b {
		out = append(out, prefixAdded+line)
	}
	return out
}

// lcsDiff diffs a and b with a longest-common-subsequence table.
func lcsDiff(a, b []string) []string {
	// table[i][j] is the LCS length of a[i:] and b[j:].
	table := make([][]int, len(a)+1)
	for i := range table {
		table[i] = make([]int, len(b)+1)
	}
	for i, v := range slices.Backward(a) {
		for j := len(b) - 1; j >= 0; j-- {
			if v == b[j] {
				table[i][j] = table[i+1][j+1] + 1
			} else {
				table[i][j] = max(table[i+1][j], table[i][j+1])
			}
		}
	}
	// Walk the table from the start, emitting what each step drops or adds.
	var out []string
	i, j := 0, 0
	for i < len(a) && j < len(b) {
		switch {
		case a[i] == b[j]:
			i++
			j++
		case table[i+1][j] >= table[i][j+1]:
			out = append(out, prefixRemoved+a[i])
			i++
		default:
			out = append(out, prefixAdded+b[j])
			j++
		}
	}
	// One side is exhausted; the rest of the other side is all removed or added.
	for ; i < len(a); i++ {
		out = append(out, prefixRemoved+a[i])
	}
	for ; j < len(b); j++ {
		out = append(out, prefixAdded+b[j])
	}
	return out
}

// countChanges summarises a diff the way the former shell script did: lines
// mentioning resources or data sources count as added/removed resources, lines
// with plan markers as modified ones.
func countChanges(lines []string) (added, removed, modified int) {
	for _, line := range lines {
		mentionsResource := strings.Contains(line, "resource") || strings.Contains(line, "data.")
		switch {
		case mentionsResource && strings.HasPrefix(line, prefixAdded):
			added++
		case mentionsResource && strings.HasPrefix(line, prefixRemoved):
			removed++
		default:
			// Lines that do not mention a resource only count as modifications below.
		}
		// "~" is an in-place change, "-/+" a replacement.
		if strings.Contains(line, "~") || strings.Contains(line, "-/+") || strings.Contains(line, "force replacement") {
			modified++
		}
	}
	return added, removed, modified
}
