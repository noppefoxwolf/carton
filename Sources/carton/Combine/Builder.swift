// Copyright 2020 Carton contributors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Dispatch
import Foundation
import OpenCombine
import TSCBasic

struct BuilderError: Error, CustomStringConvertible {
  let description: String
}

final class Builder {
  let publisher: AnyPublisher<String, Error>

  init(_ arguments: [String], _ terminal: TerminalController) {
    let subject = PassthroughSubject<String, Error>()
    publisher = subject
      .handleEvents(receiveOutput: {
        terminal.write($0)
      }, receiveCompletion: {
        switch $0 {
        case .finished:
          terminal.write("Build completed successfully\n\n", inColor: .green, bold: false)
        case let .failure(error):
          let errorString = String(describing: error)
          if errorString.isEmpty {
            terminal.write("Build failed, check the build process output above.\n", inColor: .red)
          } else {
            terminal.write("Build failed and produced following output: \n", inColor: .red)
            print(error)
          }
        }
      })
      .eraseToAnyPublisher()

    DispatchQueue.global().async {
      let stdout: TSCBasic.Process.OutputClosure = {
        guard let string = String(data: Data($0), encoding: .utf8) else { return }
        subject.send(string)
      }

      var stderrBuffer = [UInt8]()

      let stderr: TSCBasic.Process.OutputClosure = {
        stderrBuffer.append(contentsOf: $0)
      }

      let process = Process(
        arguments: arguments,
        outputRedirection: .stream(stdout: stdout, stderr: stderr),
        verbose: true,
        startNewProcessGroup: true
      )

      let result = Result<ProcessResult, Error> {
        try process.launch()
        return try process.waitUntilExit()
      }

      switch result.map(\.exitStatus) {
      case .success(.terminated(code: 0)):
        subject.send(completion: .finished)
      case let .failure(error):
        subject.send(completion: .failure(error))
      default:
        let errorDescription = String(data: Data(stderrBuffer), encoding: .utf8) ?? ""
        return subject.send(completion: .failure(BuilderError(description: errorDescription)))
      }
    }
  }
}