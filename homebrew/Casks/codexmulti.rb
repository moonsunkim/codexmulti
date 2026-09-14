cask "codexmulti" do
  version "0.2.10"
  sha256 "74321a39b4b0973a947fa5b2dd15e7b6aec1b712fb3c58259bd5f1fc6cecf5d1"

  url "https://github.com/moonsunkim/codexmulti/releases/download/v#{version}/CodexMulti-#{version}.zip"
  name "CodexMulti"
  desc "Menu-bar failover routing for multiple Codex accounts"
  homepage "https://github.com/moonsunkim/codexmulti"

  depends_on arch: :arm64
  depends_on macos: :tahoe

  auto_updates true

  app "CodexMulti.app"

  uninstall quit: "dev.codexmulti.app",
            on_upgrade: :quit,
            early_script: {
              executable: "#{appdir}/CodexMulti.app/Contents/Helpers/codexmulti-update-agent",
              args: ["homebrew-uninstall", "--app", "#{appdir}/CodexMulti.app"],
              sudo: false,
              must_succeed: true,
            }

  zap trash: [
    "~/.config/codexmulti",
    "~/Library/Application Support/CodexMulti",
    "~/Library/LaunchAgents/dev.codexmulti.app.proxy.plist",
    "~/Library/Logs/CodexMulti",
    "~/Library/Preferences/dev.codexmulti.app.plist",
  ]

end
