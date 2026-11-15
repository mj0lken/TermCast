import Foundation

enum TerminalShellConfig {
    static let relativePath = ".config/termcast/init.zsh"

    static func configURL(homeDirectory: String) -> URL {
        URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent(relativePath)
    }

    static func exists(homeDirectory: String, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: configURL(homeDirectory: homeDirectory).path)
    }

    @discardableResult
    static func ensureRecommendedConfig(
        homeDirectory: String,
        overwrite: Bool = false,
        fileManager: FileManager = .default
    ) throws -> URL {
        let url = configURL(homeDirectory: homeDirectory)
        if !overwrite, fileManager.fileExists(atPath: url.path) {
            return url
        }
        let parent = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        try recommendedContents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static let recommendedContents = """
        # Termcast Terminal configuration (~/.config/termcast/init.zsh)
        # Sourced automatically by Termcast before running commands.
        # Keep this file lightweight for instant command startup.

        export CLICOLOR=1
        export LSCOLORS="${LSCOLORS:-GxFxCxDxBxegedabagaced}"

        # Readable directory listings (uses eza automatically when installed)
        if (( $+commands[eza] )); then
          alias ls='eza --group-directories-first --color=auto'
          alias ll='eza -lh --git --group-directories-first --color=auto'
          alias la='eza -lah --git --group-directories-first --color=auto'
          alias lt='eza --tree --level=2 --color=auto'
        else
          alias ls='ls -GF'
          alias ll='ls -lhGF'
          alias la='ls -lahGF'
        fi

        # Colorized search and diffs
        alias grep='grep --color=auto'
        alias diff='diff --color=auto'

        # Concise Git helpers
        alias gs='git status -sb'
        alias gl='git log --oneline --graph --decorate -20'
        alias gd='git diff'
        alias gds='git diff --staged'

        # Quick parent navigation
        alias ..='cd ..'
        alias ...='cd ../..'
        """ + "\n"
}
