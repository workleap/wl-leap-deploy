if ($IsWindows) {
	wsl -- make $args
} else {
	make $args
}