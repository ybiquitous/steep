require "test_helper"

class CodeWorkerTest < Minitest::Test
  include TestHelper
  include ShellHelper
  include LSPTestHelper

  include Steep

  LSP = LanguageServer::Protocol::Interface

  def dirs
    @dirs ||= []
  end

  def run_worker(worker)
    t = Thread.new do
      worker.run()
    end

    yield t

  ensure
    t.join

    reader_pipe[1].close
    writer_pipe[1].close
  end

  def shutdown!
    master_writer.write(
      id: -123,
      method: :shutdown,
      params: nil
    )

    master_reader do |response|
      break if response[:id] == -123
    end

    master_writer.write(
      method: :exit
    )
  end

  def test_worker_shutdown
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      run_worker(Server::CodeWorker.new(project: project, reader: worker_reader, writer: worker_writer)) do |worker|
        master_writer.write(
          id: 123,
          method: :shutdown,
          params: nil
        )

        master_reader.read do |response|
          break if response[:id] == 123
        end

        master_writer.write(
          method: :exit
        )
      end
    end
  end

  def test_target_files
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      worker = Server::CodeWorker.new(project: project, reader: worker_reader, writer: worker_writer)

      assert_empty worker.typecheck_paths

      worker.handle_request(
        {
          method: "workspace/executeCommand",
          params: LSP::ExecuteCommandParams.new(
            command: "steep/registerSourceToWorker",
            arguments: [
              "file://#{current_dir}/lib/hello.rb",
              "file://#{current_dir}/test/hello_test.rb"
            ]
          ).to_hash
        }
      )

      assert_operator worker.typecheck_paths, :member?, Pathname("lib/hello.rb")
      assert_operator worker.typecheck_paths, :member?, Pathname("test/hello_test.rb")
    end
  end

  def test_update_target_source
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      lib_target = project.targets[0]

      worker = Server::CodeWorker.new(project: project,
                                      reader: worker_reader,
                                      writer: worker_writer,
                                      queue: [])

      assert_empty worker.typecheck_paths

      worker.handle_request(
        {
          method: "workspace/executeCommand",
          params: LSP::ExecuteCommandParams.new(
            command: "steep/registerSourceToWorker",
            arguments: [
              "file://#{current_dir}/lib/hello.rb",
              "file://#{current_dir}/test/hello_test.rb"
            ]
          ).to_hash
        }
      )

      worker.handle_request(
        {
          method: "textDocument/didChange",
          params: LSP::DidChangeTextDocumentParams.new(
            text_document: LSP::VersionedTextDocumentIdentifier.new(
              version: 1,
              uri: "file://#{current_dir}/lib/hello.rb"
            ).to_hash,
            content_changes: [
              LSP::TextDocumentContentChangeEvent.new(
                text: <<-RUBY
class Foo
end
              RUBY
              ).to_hash
            ]
          ).to_hash
        }
      )

      assert_equal <<-RUBY, lib_target.source_files[Pathname("lib/hello.rb")].content
class Foo
end
      RUBY

      assert_equal [
                     Server::CodeWorker::TypeCheckJob.new(target: lib_target, path: Pathname("lib/hello.rb"))
                   ],
                   worker.queue
    end
  end

  def test_update_nontarget_source
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      lib_target = project.targets[0]

      worker = Server::CodeWorker.new(project: project,
                                      reader: worker_reader,
                                      writer: worker_writer,
                                      queue: [])

      assert_empty worker.typecheck_paths

      worker.handle_request(
        {
          method: "workspace/executeCommand",
          params: LSP::ExecuteCommandParams.new(
            command: "steep/registerSourceToWorker",
            arguments: [
              "file://#{current_dir}/lib/hello.rb",
              "file://#{current_dir}/test/hello_test.rb"
            ]
          ).to_hash
        }
      )

      worker.handle_request(
        {
          method: "textDocument/didChange",
          params: LSP::DidChangeTextDocumentParams.new(
            text_document: LSP::VersionedTextDocumentIdentifier.new(
              version: 1,
              uri: "file://#{current_dir}/lib/world.rb"
            ).to_hash,
            content_changes: [
              LSP::TextDocumentContentChangeEvent.new(
                text: <<-RUBY
class World
end
              RUBY
              ).to_hash
            ]
          ).to_hash
        }
      )

      assert_equal <<-RUBY, lib_target.source_files[Pathname("lib/world.rb")].content
class World
end
      RUBY

      refute_operator worker.typecheck_paths, :include?, Pathname("lib/world.rb")

      assert_empty worker.queue
    end
  end

  def test_update_signature
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      lib_target = project.targets[0]

      worker = Server::CodeWorker.new(project: project,
                                      reader: worker_reader,
                                      writer: worker_writer,
                                      queue: [])

      assert_empty worker.typecheck_paths

      worker.handle_request(
        {
          method: "workspace/executeCommand",
          params: LSP::ExecuteCommandParams.new(
            command: "steep/registerSourceToWorker",
            arguments: [
              "file://#{current_dir}/lib/hello.rb"
            ]
          ).to_hash
        }
      )

      worker.handle_request(
        {
          method: "textDocument/didChange",
          params: LSP::DidChangeTextDocumentParams.new(
            text_document: LSP::VersionedTextDocumentIdentifier.new(
              version: 1,
              uri: "file://#{current_dir}/lib/hello.rb"
            ).to_hash,
            content_changes: [
              LSP::TextDocumentContentChangeEvent.new(
                text: <<-RUBY
class Hello
end
              RUBY
              ).to_hash
            ]
          ).to_hash
        }
      )

      worker.queue.clear

      worker.handle_request(
        {
          method: "textDocument/didChange",
          params: LSP::DidChangeTextDocumentParams.new(
            text_document: LSP::VersionedTextDocumentIdentifier.new(
              version: 1,
              uri: "file://#{current_dir}/sig/hello.rbs"
            ).to_hash,
            content_changes: [
              LSP::TextDocumentContentChangeEvent.new(
                text: <<-RUBY
class Hello
end
              RUBY
              ).to_hash
            ]
          ).to_hash
        }
      )

      assert_equal [
                     Server::CodeWorker::TypeCheckJob.new(target: lib_target, path: Pathname("lib/hello.rb"))
                   ],
                   worker.queue
    end
  end

  def test_typecheck_success
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
  typing_options :lenient
end
EOF

      target = project.targets[0]
      target.add_source Pathname("lib/success.rb"), <<RUBY
class Hello
  1 + ""
  1.hello_world
end
RUBY

      worker = Server::CodeWorker.new(project: project, reader: worker_reader, writer: worker_writer)

      Thread.start do
        worker.typecheck_file Pathname("lib/success.rb"), project.targets[0]
      end

      master_reader.read do |response|
        uri = response[:params][:uri]
        diagnostics = response[:params][:diagnostics]

        assert_equal Pathname("lib/success.rb"), project.relative_path(Pathname(URI.parse(uri).path))

        assert_equal [
                       {
                         range: {
                           start: { line: 1, character: 2 },
                           end: { line: 1, character: 8 }
                         },
                         severity: 1,
                         code: "Ruby::UnresolvedOverloading",
                         message: <<~MESSAGE.chomp
                                  Cannot find compatible overloading of method `+` of type `::Integer`
                                  Method types:
                                    def +: (::Integer) -> ::Integer
                                         | (::Float) -> ::Float
                                         | (::Rational) -> ::Rational
                                         | (::Complex) -> ::Complex
                         MESSAGE
                       }
                     ],
                     diagnostics
        break
      end
    end
  end

  def test_typecheck_annotation_error
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      target = project.targets[0]
      target.add_source Pathname("lib/annotation_syntax_error.rb"), <<RUBY
# @type var foo: []]
foo = 30
RUBY
      target.add_source Pathname("lib/ruby_syntax_error.rb"), <<RUBY
class Hello
RUBY

      worker = Server::CodeWorker.new(project: project, reader: worker_reader, writer: worker_writer)

      Thread.start do
        worker.typecheck_file Pathname("lib/annotation_syntax_error.rb"), project.targets[0]
      end

      master_reader.read do |response|
        uri = response[:params][:uri]
        diagnostics = response[:params][:diagnostics]

        assert_equal Pathname("lib/annotation_syntax_error.rb"), project.relative_path(Pathname(URI.parse(uri).path))

        assert_equal({
                       start: { line: 0, character: 1 },
                       end: { line: 0, character: 20 }
                     },
                     diagnostics[0][:range])

        assert_match /Annotation syntax error: parse error on value/,
                     diagnostics[0][:message]
        break
      end
    end
  end

  def test_typecheck_ruby_syntax_error
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      target = project.targets[0]
      target.add_source Pathname("lib/ruby_syntax_error.rb"), <<RUBY
class Hello
RUBY

      worker = Server::CodeWorker.new(project: project, reader: worker_reader, writer: worker_writer)

      worker.typecheck_file Pathname("lib/ruby_syntax_error.rb"), project.targets[0]
      master_reader.read do |response|
        uri = response[:params][:uri]
        diagnostics = response[:params][:diagnostics]

        assert_equal Pathname("lib/ruby_syntax_error.rb"), project.relative_path(Pathname(URI.parse(uri).path))

        assert_equal [],
                     diagnostics
        break
      end
    end
  end

  def test_run
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      requests = []
      Thread.new do
        master_reader.read do |request|
          requests << request
        end
      end

      run_worker(Server::CodeWorker.new(project: project, reader: worker_reader, writer: worker_writer)) do |worker|
        master_writer.write(
          {
            method: "workspace/executeCommand",
            params: LSP::ExecuteCommandParams.new(
              command: "steep/registerSourceToWorker",
              arguments: [
                "file://#{current_dir}/lib/hello.rb",
                "file://#{current_dir}/test/hello_test.rb"
              ]
            )
          }
        )

        master_writer.write(
          {
            method: "textDocument/didChange",
            params: LSP::DidChangeTextDocumentParams.new(
              text_document: LSP::VersionedTextDocumentIdentifier.new(
                version: 1,
                uri: "file://#{current_dir}/lib/hello.rb"
              ),
              content_changes: [
                LSP::TextDocumentContentChangeEvent.new(
                  text: <<-RUBY
class Foo
end
                RUBY
                )
              ]
            )
          }
        )

        master_writer.write(
          {
            method: "textDocument/didChange",
            params: LSP::DidChangeTextDocumentParams.new(
              text_document: LSP::VersionedTextDocumentIdentifier.new(
                version: 1,
                uri: "file://#{current_dir}/lib/world.rb"
              ),
              content_changes: [
                LSP::TextDocumentContentChangeEvent.new(
                  text: <<-RUBY
class World
end
                RUBY
                )
              ]
            )
          }
        )

        master_writer.write(
          {
            method: "textDocument/didChange",
            params: LSP::DidChangeTextDocumentParams.new(
              text_document: LSP::VersionedTextDocumentIdentifier.new(
                version: 1,
                uri: "file://#{current_dir}/sig/lib.rbs"
              ),
              content_changes: [
                LSP::TextDocumentContentChangeEvent.new(
                  text: <<-RUBY
class Hello
end
                RUBY
                )
              ]
            )
          }
        )

        assert requests.all? {|req|
          req[:method] == "textDocument/publishDiagnostics" &&
            req[:params][:uri].end_with?("lib/hello.rb") &&
            req[:params][:diagnostics] == []
        }

        shutdown!
      end
    end
  end

  def test_calculate_stats
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      (current_dir + "lib").mkdir
      (current_dir + "lib/hello.rb").write(<<RUBY)
1+2
RUBY
      (current_dir + "lib/world.rb").write(<<RUBY)
1+""
RUBY


      loader = Project::FileLoader.new(project: project)
      loader.load_sources([])
      loader.load_signatures()

      worker = Server::CodeWorker.new(project: project, reader: worker_reader, writer: worker_writer)

      thread = Thread.new do
        worker.run
      end

      worker.handle_request(
        {
          id: 100,
          method: "workspace/executeCommand",
          params: LSP::ExecuteCommandParams.new(
            command: "steep/registerSourceToWorker",
            arguments: [
              "file://#{current_dir}/lib/hello.rb"
            ]
          ).to_hash
        }
      )

      worker.handle_request(
        {
          id: 1,
          method: "initialize",
          params: {}
        }
      )

      worker.handle_request(
        {
          id: 101,
          method: "workspace/executeCommand",
          params: LSP::ExecuteCommandParams.new(
            command: "steep/stats",
            arguments: [
              "file://#{current_dir}/lib/hello.rb",
              "file://#{current_dir}/lib/world.rb"
            ]
          ).to_hash
        }
      )

      response = master_reader.read do |response|
        break response if response[:id] == 101
      end


      assert_equal [
                     {
                       type: "success",
                       target: "lib",
                       path: "lib/hello.rb",
                       typed_calls: 1,
                       untyped_calls: 0,
                       error_calls: 0,
                       total_calls: 1
                     }
                   ], response[:result]

      shutdown!

      thread.join
    end
  end
end
