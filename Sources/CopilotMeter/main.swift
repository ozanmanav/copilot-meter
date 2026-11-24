import AppKit

if CommandLine.arguments.dropFirst() == ["--quota"] {
    do {
        print(try CopilotCLI().fetchQuota().title)
        exit(EXIT_SUCCESS)
    } catch {
        FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
        exit(EXIT_FAILURE)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
