import Darwin
import Foundation
import PBMCore

let cli = PBMCLI()
let result = cli.run(arguments: Array(CommandLine.arguments.dropFirst()))
if let output = result.output {
    FileHandle.standardOutput.write(output)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

exit(result.exitCode)
