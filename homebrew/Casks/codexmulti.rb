cask "codexmulti" do
  version "0.2.0"
  sha256 "4c34783c72ac828b10225d6f84d56a433cb4f2d03df2a26426c7598e18d30334"

  url "https://github.com/moonsunkim/codexmulti/releases/download/v#{version}/CodexMulti-#{version}.zip"
  name "CodexMulti"
  desc "Menu-bar failover routing for multiple Codex accounts"
  homepage "https://github.com/moonsunkim/codexmulti"

  depends_on arch: :arm64
  depends_on macos: ">= :tahoe"

  app "CodexMulti.app"

  zap trash: [
    "~/.config/codexmulti",
    "~/Library/Application Support/CodexMulti",
    "~/Library/LaunchAgents/dev.codexmulti.app.proxy.plist",
    "~/Library/Logs/CodexMulti",
    "~/Library/Preferences/dev.codexmulti.app.plist",
  ]

  caveats <<~EOS
    This release is not notarized. macOS blocks the first launch: open CodexMulti once,
    dismiss the dialog, then in System Settings > Privacy & Security press "Open Anyway"
    next to CodexMulti and confirm. Notarized releases will open directly.
  EOS
end
