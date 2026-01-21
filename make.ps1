if ($IsWindows) {
	wsl -- make "$@"
} else {
	make "$@"
}