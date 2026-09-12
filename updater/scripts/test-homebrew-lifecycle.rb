require "cask/cask_loader"
require "cask/artifact/uninstall"
require "tmpdir"

class FixtureBlocked < StandardError; end

class FixtureCommand < SystemCommand
  class << self
    attr_accessor :events, :blocked, :expected

    def run(executable, **options)
      raise "unexpected executable" unless executable.to_s == expected
      raise "helper failure may be ignored" unless options[:must_succeed]
      events << :prepare
      raise FixtureBlocked if blocked
    end
  end
end

root = Pathname.new(__dir__).parent.parent
Dir.mktmpdir("codexmulti-homebrew-lifecycle-") do |temporary|
  directory = Pathname.new(temporary)
  appdir = directory/"Applications"
  helper = appdir/"CodexMulti.app/Contents/Helpers/codexmulti-update-agent"
  helper.dirname.mkpath
  helper.write("fixture")
  cask = Cask::CaskLoader.load(root/"homebrew/Casks/codexmulti.rb",
                              config: Cask::Config.new(explicit: { appdir: appdir.to_s }))
  artifact = cask.artifacts.find { |entry| entry.is_a?(Cask::Artifact::Uninstall) }
  raise "missing uninstall guard" unless artifact
  artifact.define_singleton_method(:uninstall_quit) { |*_, **_| FixtureCommand.events << :quit }
  FixtureCommand.expected = helper.to_s
  [{}, { upgrade: true }, { reinstall: true }].each do |options|
    FixtureCommand.events = []
    FixtureCommand.blocked = true
    begin
      artifact.uninstall_phase(command: FixtureCommand, **options)
      raise "unprepared lifecycle unexpectedly succeeded"
    rescue FixtureBlocked
      raise "GUI quit before the guard: #{FixtureCommand.events}" unless FixtureCommand.events == [:prepare]
    end
    raise "blocked lifecycle removed app" unless helper.read == "fixture"
    FixtureCommand.events = []
    FixtureCommand.blocked = false
    artifact.uninstall_phase(command: FixtureCommand, **options)
    raise "invalid prepared order" unless FixtureCommand.events == [:prepare, :quit]
    puts "PASS Homebrew #{options.empty? ? 'uninstall' : options.keys.first}: preparation precedes quit; refusal preserves app"
  end
end
