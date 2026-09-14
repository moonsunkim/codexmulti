# CodexMulti

[English](README.md) · **한국어** · [日本語](README.ja.md) · [简体中文](README.zh-CN.md) · [Español](README.es.md)

<p align="center">
  <img src="assets/hero.png" width="100%" alt="CodexMulti — 한 대의 Mac에서 여러 Codex 계정을 자동으로 전환">
</p>

**한 계정의 사용 한도에 도달해도, 다음 계정으로 작업을 이어가세요.**

CodexMulti는 여러 Codex 계정을 한곳에서 관리하는 macOS 메뉴 막대 앱입니다.
계정별 사용량과 재설정 시간을 확인하고 전환 순서를 정해 두면, 사용 한도 오류가 발생했을 때 다음 계정으로 자동 전환합니다.

[다운로드](https://github.com/moonsunkim/codexmulti/releases/latest) · [변경 내역](CHANGELOG.md) · [보안](SECURITY.md) · [기여 안내](CONTRIBUTING.md)

[![Latest release](https://img.shields.io/github/v/release/moonsunkim/codexmulti)](https://github.com/moonsunkim/codexmulti/releases/latest)
[![CI](https://github.com/moonsunkim/codexmulti/actions/workflows/ci.yml/badge.svg)](https://github.com/moonsunkim/codexmulti/actions/workflows/ci.yml)

- **모든 계정을 한눈에.** 계정별 사용량, 한도 재설정 시각, 자동 전환 상태를 한 화면에서 확인합니다. 메뉴 막대에서 평균 잔여율을 보고, **계정…**을 눌러 목록을 바로 열 수 있습니다.
- **순서는 한 번만 설정.** 계정을 드래그해 원하는 순서로 정렬하세요. 사용 한도 오류가 확인되면 다음 사용 가능한 계정으로 요청을 재시도합니다.
- **스위치 하나로 시작.** 필요한 로컬 프록시와 Node 런타임이 앱에 포함되어 있습니다. 앱이 열려 있으면 계정 추가와 재연결도 자동으로 반영됩니다.
- **인증 정보는 내 Mac에.** 계정마다 별도의 Codex 디렉터리와 키체인 백업을 사용합니다. CodexMulti 회원가입이나 별도 서버 연결은 필요하지 않습니다.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/screenshots/menu-bar-dark.png">
    <source media="(prefers-color-scheme: light)" srcset="assets/screenshots/menu-bar-light.png">
    <img src="assets/screenshots/menu-bar-light.png" width="440" alt="예시용 계정으로 표시한 CodexMulti 메뉴: 평균 잔여율, 계정별 사용량과 재설정 시간, 활성 계정">
  </picture>
</p>
<p align="center"><sub><a href="assets/screenshots/menu-bar-light.png">라이트</a> · <a href="assets/screenshots/menu-bar-dark.png">다크</a></sub></p>
<p align="center"><sub>메뉴 막대에서 풀의 평균 잔여율과 계정별 사용량·재설정 시간을 바로 확인합니다. 예시용 계정입니다.</sub></p>

## Failover는 어떤 문제를 해결하나요?

코딩 작업 중 한 계정의 사용 한도에 도달하면, 다른 계정에 사용량이 남아 있어도 작업이 멈출 수 있습니다.
자동 전환이 없다면 직접 다른 계정을 선택하고 요청을 다시 보내야 합니다.

**Failover는 사용 한도 오류가 확인되었을 때 다음 사용 가능한 계정으로 요청을 자동 재시도하는 기능입니다.**
이 앱의 한국어 화면에서는 **자동 계정 전환**이라고 부릅니다. 계정을 추가하고 순서를 정한 뒤
**자동 계정 전환 사용**을 켜면, 지원되는 Codex 요청이 Mac 안에서 실행되는 로컬 프록시를 거칩니다.

예를 들어 A 계정이 응답을 시작하기 전에 사용 한도 오류를 반환하면 같은 요청을 B 계정으로 재시도합니다.
B도 한도에 도달했다면 다음 사용 가능한 계정을 시도합니다. 한도 오류가 날 때마다 계정을 직접 바꿀 필요가 줄어듭니다.

각 계정의 구독과 사용 한도는 그대로입니다. 이미 시작한 응답을 다른 계정에서 다시 실행하거나 모든 오류를 재시도하지는 않습니다.
정확한 조건은 [계정이 전환되는 시점](#계정은-언제-전환되나요)을 참고하세요.

## 설치

**macOS 26 이상을 실행하는 Apple Silicon Mac**과 ChatGPT 로그인을 사용하는 **Codex CLI 0.146.0 이상**이 필요합니다.
자동 계정 전환을 활용하려면 계정이 두 개 이상 있어야 합니다.

```sh
brew install --cask moonsunkim/tap/codexmulti
```

또는 [최신 릴리스](https://github.com/moonsunkim/codexmulti/releases/latest)를 다운로드하세요.
0.2.1부터는 Developer ID 서명과 Apple 공증을 완료한 앱을 배포합니다.

<details>
<summary>설치 스크립트 또는 수동 설치</summary>

```sh
curl -fsSL https://raw.githubusercontent.com/moonsunkim/codexmulti/main/install.sh | bash
```

설치 스크립트는 공개된 SHA-256 체크섬을 확인하고, 기존 앱을 `CodexMulti.app.previous`로 보존합니다.
새 앱을 `/Applications`에 설치한 뒤 백그라운드에서 엽니다. Gatekeeper 격리 속성은 유지합니다.

수동으로 설치하려면 `CodexMulti-<version>.zip`과 해당 `.sha256` 파일을 같은 디렉터리에 내려받고,
압축을 풀기 전에 다음 명령으로 확인하세요.

```sh
shasum -a 256 -c CodexMulti-<version>.zip.sha256
```

확인한 `CodexMulti.app`을 `/Applications`로 옮겨 실행하세요.

</details>

이미 설치했다면 **설정 → 소프트웨어 업데이트 → 업데이트 확인**을 사용하세요. **안전한 업데이트 설정**이 표시되면 Codex 클라이언트를 종료하고 처음 한 번 설정을 마쳐야 합니다. 업데이트 확인과 설치는 사용자가 시작합니다. 자세한 내용은 [앱 내 업데이트](#앱-내-업데이트)를 참고하세요.

## 두 단계로 시작하기

1. **계정 추가.** **+**를 누르고 계정 이름을 입력한 뒤 공식 브라우저 로그인 절차를 완료하세요. 사용할 계정마다 반복합니다.
2. **자동 계정 전환 사용 켜기.** **설정**에서 켜면 앱이 내장 프록시를 준비하고 정상 동작을 확인한 뒤 Codex를 연결합니다.

이후에는 평소처럼 Codex를 사용하면 됩니다. 응답이 시작되기 전에 사용 한도 오류가 확인되면 같은 요청을 다음 계정으로 시도합니다.
전환 대상에서 제외한 계정, 인증에 문제가 있는 계정, 한도 재설정을 기다리는 계정은 건너뜁니다.

앱이 열려 있으면 계정 추가, 재연결, 순서 변경을 자동으로 반영합니다. 프록시를 다시 불러와야 하는 변경은
진행 중인 요청이 끝난 뒤 적용합니다. 메뉴 막대 앱을 종료해도 정상 작동 중인 프록시는 계속 실행됩니다.
자동 계정 전환을 끄면 진행 중인 요청이 끝난 뒤 Codex가 직접 연결하도록 복원합니다.

메뉴 막대의 **계정…**을 눌러 전체 목록을 여세요. 계정의 **…** 메뉴에서 **이 계정으로 전환…**을 선택하면
새 요청에 사용할 계정을 직접 바꿀 수 있습니다. **자동 전환 대상에서 제외**는 그 계정에 새 요청을 보내지 않게 하며,
**자동 전환 대상에 포함**으로 다시 사용할 수 있습니다. 이미 처리 중인 요청은 계속 진행됩니다.

계정 행의 비율은 표시된 기간에 **사용한 양**입니다. **100%는 해당 한도를 모두 사용했다는 뜻**입니다. **풀**은 주간 사용량이 보고된 포함 계정들의 평균 잔여율입니다. 제외되거나 인증이 무효인 계정은 빼지만, 한도 재설정을 기다리는 계정은 포함합니다. 토큰 총합이나 지금 바로 요청을 받을 수 있는 계정 수를 뜻하지 않습니다.

사용량은 마지막 조회 결과입니다. 계정의 **…** 메뉴에서 개별 갱신하거나 **모든 계정 새로 고침**을 사용하세요. 자동 갱신은 기본적으로 **꺼짐**이며, 설정에서 **15분·30분·1시간** 간격을 선택할 수 있습니다. 새로 고침은 로컬 프록시 상태도 갱신합니다. **이름 변경…**은 CodexMulti의 표시 이름을 바꾸며 OpenAI 계정 이메일은 바꾸지 않습니다.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/screenshots/accounts-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="assets/screenshots/accounts-light.png">
  <img alt="계정별 사용한 비율, 재설정 시각과 자동 전환 상태를 보여 주는 CodexMulti 계정 목록" src="assets/screenshots/accounts-light.png">
</picture>
<p align="center"><sub><a href="assets/screenshots/accounts-light.png">라이트</a> · <a href="assets/screenshots/accounts-dark.png">다크</a></sub></p>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/screenshots/settings-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="assets/screenshots/settings-light.png">
  <img alt="자동 계정 전환 스위치와 언어 선택 메뉴가 있는 설정 화면" src="assets/screenshots/settings-light.png">
</picture>
<p align="center"><sub><a href="assets/screenshots/settings-light.png">라이트</a> · <a href="assets/screenshots/settings-dark.png">다크</a></sub></p>

사용량 갱신 간격, 표시할 사용량 기간, 테마를 선택할 수 있습니다.
언어는 **시스템, English, 한국어, 日本語, 简体中文, Español**를 지원합니다. 중국어는 간체(`zh-Hans`), 스페인어는 공통 번역(`es`)을 사용합니다. 번체는 아직 지원하지 않습니다. 위 스크린샷은 영어 화면입니다. 번역 추가·수정 방법은 [i18n 안내](docs/i18n.md)를 참고하세요.

<details>
<summary>계정 상세 보기</summary>

계정을 펼치면 사용량 기간별 정보, 인증 및 자동 전환 상태, 마지막 갱신 시각과 보고된 리셋 크레딧을 확인할 수 있습니다.

제공자가 사용 가능한 크레딧을 보고하면 계정 메뉴에서 **리셋 1개 사용…**을 선택할 수 있습니다. 최신 상태를 확인하고 두 단계의 확인을 거친 뒤 기존 크레딧 1개를 사용합니다. **대기 해제…**는 외부에서 이미 한도를 초기화한 계정의 대기만 해제하는 별도 동작이며, 크레딧을 사용하지 않습니다.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/screenshots/accounts-expanded-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="assets/screenshots/accounts-expanded-light.png">
  <img alt="사용량 기간, 토큰 상태, 갱신 시각과 리셋 크레딧을 보여 주는 계정 상세 화면" src="assets/screenshots/accounts-expanded-light.png">
</picture>
<p align="center"><sub><a href="assets/screenshots/accounts-expanded-light.png">라이트</a> · <a href="assets/screenshots/accounts-expanded-dark.png">다크</a></sub></p>

모든 스크린샷은 예시용 계정을 사용합니다.

</details>

## 계정은 언제 전환되나요?

응답 스트림 시작 전 HTTP `429`의 오류 유형이 `usage_limit_reached`인 경우, WebSocket 연결 협상 중 같은 응답을 받은 경우, 또는 이미 연결된 Responses WebSocket에서 응답 이벤트가 전달되기 전에 `usage_limit_reached`가 발생한 경우에 전환합니다. 한 요청에서 각 후보 계정은 최대 한 번씩 시도합니다.

수동 전환은 기존 WebSocket을 재사용하더라도 다음 요청부터 적용됩니다. 시작된 응답은 원래 계정에서 마치고, 계정이 바뀐 후 이어지는 요청에는 대화 문맥을 전달합니다. 독립된 대화 스트림은 각각 계속 처리할 수 있습니다. 완전한 이력이 캐시에 남아 있지 않으면 클라이언트가 전체 문맥을 다시 보내야 하며, 프록시는 대화 내용을 임의로 생략하지 않습니다.

네트워크 오류, `5xx`, 중단된 스트림, 구독 불일치, `usage_not_included`, 인식하지 못하는 `429` 응답은 요청을 중단합니다.
이미 시작한 응답은 다른 계정에서 재실행하지 않습니다. 사용할 수 있는 계정이 더 없으면 무한 재시도하지 않고 오류를 반환합니다.

앱은 계정의 한도를 늘리거나 구독을 변경하지 않습니다. 프록시 호환성은 Codex CLI에 맞춰 관리하므로,
업데이트 전에 [릴리스 노트](https://github.com/moonsunkim/codexmulti/releases/latest)를 확인하세요.

## 계정 정보는 내 Mac에 보관됩니다

원격 측정, 분석 수집, CodexMulti가 운영하는 제어 서버는 없습니다. 인증, 사용량 조회, 추론 요청은 제공자 서비스에 직접 연결합니다.
프록시는 루프백 주소에서만 수신하며, 제어 API는 사용자별 비공개 인증 토큰을 사용합니다.

계정마다 격리된 Codex 홈을 사용합니다. 인증 정보는 로컬에 보관하고 키체인에 백업하며,
개인 `~/.codex/auth.json`은 덮어쓰지 않습니다. 자동 계정 전환을 켜면 `~/.codex/config.toml`에서
앱이 관리하는 base-URL 항목 두 개만 수정하고, 시각이 기록된 백업을 남깁니다. 끄면 직접 연결로 복원합니다.

보안 경계와 로그 처리 방식은 [보안 안내](SECURITY.md)와 [프록시 보안](proxy/README.md#state-logs-and-security)을 참고하세요.

## 소스에서 빌드하기

`PATH`에 Zig 0.16.0이 있어야 합니다. Swift 6과 macOS 26 SDK를 포함한 Xcode 또는 Command Line Tools,
그리고 macOS 26을 실행하는 Apple Silicon Mac이 필요합니다.

```sh
./app/scripts/fetch-node.sh
./app/scripts/build-app.sh
./app/scripts/screenshots.sh
./app/scripts/verify-provenance.sh app/dist/staging/CodexMulti.app
./app/scripts/verify-bundled-proxy.sh app/dist/staging/CodexMulti.app
```

고정 버전 Node의 SHA-256을 확인한 뒤, 코어를 `aarch64-macos` 오브젝트로 컴파일해 Swift 실행 파일에 연결합니다.
빌드 결과는 `app/dist/staging/CodexMulti.app`에 생성되며, Node 실행 파일과 프록시 소스가 함께 포함됩니다.
코어 소스 해시, 브리지 스키마, 프록시 커밋과 파일 트리 해시, Node 해시를 기록하고
`verify-provenance.sh`에서 실제 파일을 기준으로 다시 계산해 확인합니다.

테스트:

```sh
(cd core && zig build test && zig build test-bridge)
(cd app && CODEXMULTI_TEST_HEADLESS=1 swift test)
(cd proxy && npm test)
(cd updater && CODEXMULTI_TEST_HEADLESS=1 swift test)
```

Swift 테스트는 반드시 `CODEXMULTI_TEST_HEADLESS=1`을 지정하세요. 일반 `swift test`는 창을 엽니다.
CI는 macOS에서 Zig 코어, Node 프록시, SwiftUI 셸과 배포 스크립트를 검사합니다. SwiftUI 검사는 macOS 26 SDK를 사용합니다.

서명과 릴리스 패키징은 일반 빌드와 별도입니다. `app/scripts/package-signed-macos.sh`는 로컬 서명 정보를 확인하고
내장 Node부터 앱까지 순서대로 서명합니다. 출처 정보나 지정 요구 사항이 맞지 않는 번들은 거부합니다.

## 구성

| 구성 요소 | 역할 |
| --- | --- |
| [SwiftUI 앱](app/) | 창, 메뉴, 접근성, macOS 연동 |
| [Zig 코어](core/) | 계정, 백그라운드 작업, 안전한 연결 설정 변경, 모든 UI 문구 |
| [Node 프록시](proxy/) | 로컬 요청 전달과 사용 가능한 계정 간 자동 전환 |
| [네이티브 업데이터](updater/) | 서명된 실행 환경 준비, 새 요청 유입 제어, 장애 복구 |

앱은 타입이 지정된 동작 요청을 코어에 전달하고, 코어가 반환한 상태를 표시합니다.
프록시는 사용자별 LaunchAgent로 독립 실행되므로 메뉴 막대 앱을 종료해도 요청 처리를 계속할 수 있습니다.
프록시와 고정 버전 Node 런타임은 모두 앱에 포함되어 있습니다.
안전한 업데이트 설정 이후에는 `~/Library/Application Support/CodexMulti/runtimes/`에 검증된 별도 실행 환경을 두고 프록시를 실행합니다.

### 앱 내 업데이트

**설정 → 소프트웨어 업데이트 → 업데이트 확인**에서 새 버전을 확인하고 설치합니다. 처음 한 번은 Codex 클라이언트를 종료한 뒤 **안전한 업데이트 설정**을 완료해야 합니다. 이후에는 앱을 교체하는 동안 기존 프록시를 유지합니다. 프록시 실행 파일이 바뀌면 HTTP 요청, WebSocket 연결, 인증 갱신이 끝날 때까지 기다립니다. UI만 바뀐 업데이트는 기존 프록시 프로세스를 유지합니다. 실행 환경을 전환하는 짧은 동안 새 연결이 실패할 수 있지만, 진행 중인 요청을 강제로 끊거나 다시 보내지는 않습니다.

업데이트 중에는 계정 변경을 잠시 막습니다. 설정에서 진행 상태를 확인하고, 중지 확정 전 취소하거나 요청이 끝난 뒤 자동 전환을 끄도록 예약할 수 있습니다. 메뉴 막대 앱을 닫아도 업데이트 에이전트는 계속 동작합니다. 새 실행 환경이 시작하지 못하면 이전의 호환되는 환경으로 복구합니다. 살아 있지만 연결할 수 없는 프로세스는 강제로 종료하지 않고 복구가 필요한 상태로 표시합니다. 앱 설치 복구가 필요하면 **이전 앱 보기**로 보존된 서명 앱을 열 수 있습니다.

업데이트는 HTTPS 피드와 고정된 Sparkle 공개 키가 설정된 배포 빌드에서 사용할 수 있습니다. 업데이트 피드가 없는 로컬 빌드에서는 사용할 수 없습니다. [업데이트 설계](docs/update-design.md)와 [배포 설정](docs/updater-release.md)을 참고하세요.

<details>
<summary>복구, 제거, 연결 설정 수동 복원</summary>

자동 계정 전환이 켜져 있으면 앱이 복구를 자동 재시도합니다. 진행 중인 요청 때문에 변경을 미뤄야 하면 상태에 이유가 표시됩니다.
자동 계정 전환을 끄면 해당 요청이 끝난 뒤 Codex 직접 연결로 복원합니다.

안전한 업데이트를 설정한 설치에서는 Codex 클라이언트와 CodexMulti 메뉴 막대 앱을 종료한 뒤 다음을 실행하세요.

```sh
"/Applications/CodexMulti.app/Contents/Helpers/codexmulti-update-agent" prepare-removal \
  --app "/Applications/CodexMulti.app" \
  --config "$HOME/.config/codexmulti/proxy.json"
brew uninstall --cask codexmulti
```

프록시 설정 경로를 바꿨다면 실제 경로를 지정하세요. 준비 과정은 요청이 끝나기를 기다리고, CodexMulti가 관리하는 연결 설정만 복원한 뒤 자동 시작 등록을 제거합니다. `proxy_busy`가 나오면 에이전트가 계속 기다리므로 클라이언트가 종료된 뒤 준비 명령을 다시 실행하세요. 계정 인증 정보, 사용량 이력, 리셋 기록은 재설치를 위해 보존합니다.

Homebrew cask는 앱을 삭제하기 전에 명시적인 제거 준비가 완료됐는지 확인합니다. `auto_updates`로 등록되어 있으므로 일반 업데이트는 앱 내 업데이트를 사용하세요. Homebrew는 제거 스크립트에 업데이트와 삭제를 확실히 구분해 전달하지 않으므로, 준비되지 않은 `--greedy` 업데이트나 재설치는 앱 교체 전에 중단됩니다. 자동 계정 전환을 몰래 끄지 않습니다. `--zap`은 저장된 계정 데이터도 삭제합니다. 네이티브 업데이트 도구가 없는 구버전은 제거 전에 기존의 `codexmulti-maintenance prepare-uninstall` 절차를 사용하세요.

앱이나 내장 도구가 실행되지 않으면 `~/.codex/config.toml`을 텍스트 편집기로 여세요.
최상위에 다음 항목이 있는 경우에만 정확히 해당 두 항목을 제거하고 나머지 설정은 보존하세요.

```toml
chatgpt_base_url = "http://127.0.0.1:8787/backend-api/"
openai_base_url = "http://127.0.0.1:8787/backend-api/codex"
```

다음 서비스 제거 확인은 Node를 직접 실행하는 구버전 LaunchAgent에만 해당합니다. 별도 실행 환경을 사용하는 설치는 `codexmulti-runtime-launcher`로 시작하므로 앞에서 설명한 네이티브 도구와 복구 기능을 사용하세요. 요청을 처리 중인 실행 환경을 강제로 종료하지 마세요.

이후 `launchctl print "gui/$(id -u)/dev.codexmulti.app.proxy"`로 실행 인자를 확인하세요.
CodexMulti 앱의 `Contents/Helpers/node`, `Contents/Resources/proxy/src/server.mjs`, `--config`와
본인의 프록시 설정을 가리키는 경우에만 `launchctl bootout "gui/$(id -u)/dev.codexmulti.app.proxy"`로 중지하고
`~/Library/LaunchAgents/dev.codexmulti.app.proxy.plist`를 제거하세요.
Codex 클라이언트를 다시 시작해 직접 연결 설정을 읽게 하세요. 공유 설정 파일 전체를 오래된 백업으로 덮어쓰지 마세요.

프록시 제어에는 사용자별 비공개 인증 토큰이 필요합니다. 일반 Codex 프록시 요청은 로컬 Mac의 사용자와 프로세스를 신뢰하는 구조이므로,
신뢰할 수 있는 환경에서 사용하세요. 자세한 내용은 [프록시 보안](proxy/README.md#state-logs-and-security)을 참고하세요.

</details>

## 라이선스

MIT — [LICENSE](LICENSE)를 참고하세요. 내장 Node.js 관련 고지는 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)에 있습니다.

CodexMulti는 독립적인 오픈 소스 프로젝트이며 OpenAI와 제휴하거나 OpenAI의 보증을 받지 않습니다.
Codex는 OpenAI의 상표입니다.
