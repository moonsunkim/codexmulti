cask "codexmulti" do
  version "0.2.4"
  sha256 "ef16d5604da0ceb3c557780a162a31c9174362fe997513c6b56d709b50ea7615"

  url "https://github.com/moonsunkim/codexmulti/releases/download/v#{version}/CodexMulti-#{version}.zip"
  name "CodexMulti"
  desc "Menu-bar failover routing for multiple Codex accounts"
  homepage "https://github.com/moonsunkim/codexmulti"

  depends_on arch: :arm64
  depends_on macos: ">= :tahoe"

  app "CodexMulti.app"

  uninstall quit: "dev.codexmulti.app",
            on_upgrade: :quit,
            script: {
              executable: "#{appdir}/CodexMulti.app/Contents/Helpers/codexmulti-maintenance",
              args: ["prepare-uninstall"],
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
