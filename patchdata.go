package ultrawide

import "embed"

//go:embed patches/megaton-1.4.9-linux/manifest patches/megaton-1.4.9-linux/changes.tsv
//go:embed patches/megaton-1.4.9-windows/manifest patches/megaton-1.4.9-windows/changes.tsv
var Patches embed.FS

var PatchDirs = []string{"patches/megaton-1.4.9-linux", "patches/megaton-1.4.9-windows"}
