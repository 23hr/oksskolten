package main

import rego.v1

# ---------------------------------------------------------------------------
# Helpers to build minimal remark AST nodes
# ---------------------------------------------------------------------------

h(depth, text) := {"type": "heading", "depth": depth, "children": [{"type": "text", "value": text}]}

tbl(cols) := {"type": "table", "children": [{"type": "tableRow", "children": [{"type": "tableCell"} | some _ in numbers.range(1, cols)]}]}

doc(children) := {"type": "root", "children": children}

feature_doc(children) := {"type": "root", "children": children, "metadata": {"is_feature": true}}

# ---------------------------------------------------------------------------
# Rule 1: H1 title pattern
# ---------------------------------------------------------------------------

test_h1_valid_en if {
	count(deny) == 0 with input as doc([h(1, "Oksskolten Spec — Chat")])
}

test_h1_valid_ja if {
	count(deny) == 0 with input as doc([h(1, "Oksskolten 実装仕様書 — チャット")])
}

test_h1_invalid if {
	"H1 must match 'Oksskolten Spec — {Feature}' or 'Oksskolten 実装仕様書 — {Feature}', got: 'Bad Title'" in deny with input as doc([h(1, "Bad Title")])
}

test_h1_missing if {
	"Spec must have exactly one H1, found 0" in deny with input as doc([h(2, "Only H2")])
}

test_h1_multiple if {
	"Spec must have exactly one H1, found 2" in deny with input as doc([
		h(1, "Oksskolten Spec — A"),
		h(1, "Oksskolten Spec — B"),
	])
}

# ---------------------------------------------------------------------------
# Rule 2: Feature spec single H2
# ---------------------------------------------------------------------------

test_feature_single_h2_pass if {
	count(deny) == 0 with input as feature_doc([
		h(1, "Oksskolten Spec — Clip"),
		h(2, "Clip"),
	])
}

test_feature_multiple_h2_fail if {
	"Feature spec must have exactly one H2 (feature name), found 2" in deny with input as feature_doc([
		h(1, "Oksskolten Spec — Clip"),
		h(2, "Clip"),
		h(2, "Extra"),
	])
}

test_non_feature_multiple_h2_ok if {
	count(deny) == 0 with input as doc([
		h(1, "Oksskolten Spec — Overview"),
		h(2, "Stack"),
		h(2, "Deploy"),
	])
}

# ---------------------------------------------------------------------------
# Rule 3: Forbidden section names
# ---------------------------------------------------------------------------

test_forbidden_current_status if {
	"Forbidden section name: 'Current Status'" in deny with input as doc([
		h(1, "Oksskolten Spec — X"),
		h(3, "Current Status"),
	])
}

test_forbidden_implementation_checklist if {
	"Forbidden section name: 'Implementation Checklist'" in deny with input as doc([
		h(1, "Oksskolten Spec — X"),
		h(3, "Implementation Checklist"),
	])
}

test_forbidden_reference_prefix if {
	"Forbidden section name: 'Reference: Keyboard Shortcuts'" in deny with input as doc([
		h(1, "Oksskolten Spec — X"),
		h(3, "Reference: Keyboard Shortcuts"),
	])
}

test_allowed_section_name if {
	count(deny) == 0 with input as doc([
		h(1, "Oksskolten Spec — X"),
		h(3, "Key Files"),
	])
}

# ---------------------------------------------------------------------------
# Rule 4: Key Files table columns
# ---------------------------------------------------------------------------

test_key_files_2_columns_pass if {
	count(deny) == 0 with input as doc([
		h(1, "Oksskolten Spec — X"),
		h(3, "Key Files"),
		tbl(2),
	])
}

test_key_files_3_columns_fail if {
	"Key Files table must have 2 columns (File | Description), found 3" in deny with input as doc([
		h(1, "Oksskolten Spec — X"),
		h(3, "Key Files"),
		tbl(3),
	])
}

# ---------------------------------------------------------------------------
# Rule 5: Max heading depth
# ---------------------------------------------------------------------------

test_h4_allowed if {
	count(deny) == 0 with input as doc([
		h(1, "Oksskolten Spec — X"),
		h(4, "Subsection"),
	])
}

test_h5_denied if {
	"Heading depth 5 exceeds maximum (H4): 'Too Deep'" in deny with input as doc([
		h(1, "Oksskolten Spec — X"),
		h(5, "Too Deep"),
	])
}
