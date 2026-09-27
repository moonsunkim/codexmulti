cask "codexmulti" do
  version "0.2.15"
  sha256 "bdd6902d689300a5f4a3ae8137a6a978cf2a2db3f001805a90d27b10cfa4072c"

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
