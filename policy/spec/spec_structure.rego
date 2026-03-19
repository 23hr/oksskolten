package main

import rego.v1

# Helper: extract text from heading node children
heading_text(h) := concat("", [c.value | some c in h.children; c.type == "text"])

# All headings in the document
headings := [h | some h in input.children; h.type == "heading"]

# Rule 1: H1 must match title pattern (EN or JA)
deny contains msg if {
	some h in headings
	h.depth == 1
	text := heading_text(h)
	not regex.match(`^Oksskolten Spec — .+$`, text)
	not regex.match(`^Oksskolten 実装仕様書 — .+$`, text)
	msg := sprintf("H1 must match 'Oksskolten Spec — {Feature}' or 'Oksskolten 実装仕様書 — {Feature}', got: '%s'", [text])
}

deny contains msg if {
	h1s := [h | some h in headings; h.depth == 1]
	count(h1s) != 1
	msg := sprintf("Spec must have exactly one H1, found %d", [count(h1s)])
}

# Rule 2: Feature specs (filename contains _feature_) must have exactly one H2
# This rule is enforced via --data flag passing metadata from the shell script.
# When input.metadata.is_feature is true, enforce single H2.
deny contains msg if {
	object.get(input, ["metadata", "is_feature"], false) == true
	h2s := [h | some h in headings; h.depth == 2]
	count(h2s) != 1
	msg := sprintf("Feature spec must have exactly one H2 (feature name), found %d", [count(h2s)])
}

# Rule 3: Forbidden section names
forbidden_prefixes := ["Current Status", "Implementation Checklist", "Discrepancies", "Updates", "Reference:"]

deny contains msg if {
	some h in headings
	text := heading_text(h)
	some prefix in forbidden_prefixes
	startswith(text, prefix)
	msg := sprintf("Forbidden section name: '%s'", [text])
}

# Rule 4: Key Files table must have 2 columns (File | Description)
deny contains msg if {
	some i, node in input.children
	node.type == "heading"
	node.depth == 3
	heading_text(node) == "Key Files"

	# Find the next table after this heading
	some j, tbl in input.children
	j > i
	tbl.type == "table"

	# Check column count via first row (header)
	header := tbl.children[0]
	col_count := count(header.children)
	col_count != 2
	msg := sprintf("Key Files table must have 2 columns (File | Description), found %d", [col_count])
}

# Rule 5: No heading deeper than H4
deny contains msg if {
	some h in headings
	h.depth > 4
	text := heading_text(h)
	msg := sprintf("Heading depth %d exceeds maximum (H4): '%s'", [h.depth, text])
}
