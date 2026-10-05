//
//  StandardOutput.swift
//  PopcornEPG
//
//  Copyright © 2026 Adam Young.
//

// Glibc's `stdout` is an unannotated global that Swift 6 rejects as not concurrency-safe. Importing Glibc
// `@preconcurrency` allows it, but not in a file that imports Foundation first, so this has its own file.
#if canImport(Glibc)
    @preconcurrency import Glibc
#else
    import Darwin
#endif

enum StandardOutput {

    /// Stdout is block-buffered when piped (as in CI), which holds every progress line until exit.
    static func useLineBuffering() {
        setvbuf(stdout, nil, _IOLBF, 0)
    }

}
