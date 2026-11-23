package ultrawide

import _ "embed"

//go:embed patches/megaton-1.4.9-linux/manifest
var Manifest string

//go:embed patches/megaton-1.4.9-linux/changes.tsv
var Changes string
