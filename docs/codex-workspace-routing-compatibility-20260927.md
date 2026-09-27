# Codex workspace routing과 CodexMulti 호환성 진단

진단일: 2026-09-27. 최초 재현은 전역 설정을 바꾸지 않는 별도 프로세스로 수행했다.

## 결론

`chatgpt_base_url`은 기본 공식 백엔드를 사용하고, `openai_base_url`만 로컬 프록시를 사용하면 된다. 두 설정을 모두 HTTP 프록시로 보내는 기존 방식은 최근 Codex의 워크스페이스 조회 및 HTTPS 검증과 충돌한다.

```toml
# 사용자 config.toml의 최상위, [projects...] 등 테이블보다 위에 둔다.
# chatgpt_base_url의 로컬 프록시 재정의는 제거하거나 주석으로 유지한다.
openai_base_url = "http://127.0.0.1:8787/backend-api/codex"
```

로그인·워크스페이스 조회는 Codex에 로그인한 계정으로 공식 백엔드에 연결한다. 모델 목록과 Responses 요청은 프록시로 연결하고, 프록시는 선택한 계정으로 요청한다. 별도 테스트에서 이 분리가 실제로 동작했다.

## 확인한 환경

- 독립 설치 CLI: `0.157.1`.
- 데스크톱 앱: `/Applications/ChatGPT.app`, `26.924.22138` / build `11645`.
- 앱 내장 CLI: `0.158.0-alpha.2.1`.
- CodexMulti: `0.2.14`.
- 프록시 서비스는 `127.0.0.1:8787`에서 실행 중이다. 비활성화된 것은 사용자 Codex 설정의 두 base URL 재정의다.

## 원인

### 계정이 다를 때

1. Codex는 로그인된 계정 A의 workspace/account ID를 가지고 `GET /backend-api/wham/accounts/check`를 호출한다.
2. 기존 프록시는 모든 upstream HTTP 요청의 Authorization 및 ChatGPT-Account-ID를 선택 계정 B의 값으로 바꾼다 (`proxy/src/upstream.mjs`).
3. 응답에는 B가 접근 가능한 워크스페이스가 들어온다.
4. Codex가 A의 ID와 일치하는 항목을 찾지 못하면 `selected workspace missing from routing discovery`를 반환한다.

현재 선택된 두 계정으로 이 오류를 재현했다. 계정이 다르다는 사실만으로 항상 실패한다는 뜻은 아니며, 정확한 실패 조건은 반환 목록에 로그인된 workspace ID가 없다는 것이다.

### 계정이 같을 때

계정 일치는 첫 검증을 통과하게 하지만, 조회 결과의 `workspace_backend_origin`이 `NO_CONSTRAINT`이면 Codex는 설정된 `chatgpt_base_url`의 origin을 사용한다. 이어서 `parse_backend_url`이 HTTPS와 URL 내 userinfo 부재를 검사한다. 기존 `http://127.0.0.1:8787/backend-api/`는 HTTP이므로 `workspace backend must use an HTTPS origin without credentials`가 발생한다.

여기서 credentials는 URL의 `https://user:pass@host` 같은 userinfo를 뜻한다. 이번 재현에서 실패 원인은 HTTP scheme이다.

### 업데이트 근거

OpenAI 공식 저장소의 변경 이력에는 다음 두 변경이 있다.

- 2026-09-14 UTC: [Expose selected workspace routing in app-server account reads, #45529](https://github.com/openai/codex/commit/a4354e2d27fd9a1822ba72617fe2f30d0ef6954b). 계정 조회 시 워크스페이스 라우팅을 발견·검증하고 실패를 반환하도록 했다.
- 2026-09-17 UTC: [Connect app-server workspace discovery to model request routing, #46281](https://github.com/openai/codex/commit/0a5b9991698e8e3c126da6101aa9e4da421f7ddd). 모델 요청에 워크스페이스 라우팅 제약을 적용하고, 별도 목적지 여부도 성공한 discovery 이후 판단하도록 했다.

이는 인증 주체 및 워크스페이스 라우팅 검증 강화로 설명할 수 있다. 특정 개인 프록시를 차단하려는 의도까지 확인된 것은 아니다.

구체적인 분기와 오류 문자열은 [CLI 0.157.1 workspace_routing.rs](https://github.com/openai/codex/blob/rust-v0.157.1/codex-rs/app-server/src/request_processors/account_processor/workspace_routing.rs)에 있다. `rust-v0.158.0-alpha.2` 태그의 같은 파일도 바이트 단위로 일치했다. 설치된 앱 내장 바이너리의 동작은 별도로 재현했다.

## 검증 결과

| 설정 및 조건 | CLI 0.157.1 | 앱 내장 0.158.0-alpha.2.1 |
|---|---|---|
| 두 URL 모두 프록시, 로그인/프록시 계정 불일치 | missing workspace 오류 재현 | 같은 오류 재현 |
| 두 URL 모두 프록시, 로그인/프록시 계정 일치 | HTTPS origin 오류 재현 | 같은 오류 재현 |
| ChatGPT 기본 공식 주소 + 모델 URL만 프록시, 계정 불일치 | account/read 성공 | account/read 성공 |
| 분리 설정에서 실제 모델 요청 | 완료, `OK` | 완료, `OK` |

실제 모델 요청은 `gpt-6-luna`에 짧은 응답을 요청한 두 번의 별도 검증이다. 루프백 관측 중계가 `GET /backend-api/codex/models`와 WebSocket `GET /backend-api/codex/responses`를 실제 실행 중인 8787 프록시로 전달했음을 확인했다. 따라서 계정 조회만 통과하고 모델 요청이 공식 서버로 직접 빠진 결과가 아니다.

각 검증은 임시 CODEX_HOME과 별도 app-server 프로세스로 수행했다. 갱신 토큰은 복제하지 않았으며, 임시 자격 증명 파일은 권한 0600으로 생성하고 종료 시 삭제했다. 원본 `~/.codex/auth.json`의 바이트가 유지됨을 확인했다. 프록시 선택 계정은 검증 전후 동일하며 종료 후 in-flight는 0이다.

데스크톱 UI를 재시작하여 로그인 화면과 기존 대화를 확인하는 검증은 수행하지 않았다. 이번 결과는 앱 내장 app-server의 계정 조회와 새 임시 대화의 실제 모델 응답까지를 입증한다. 실제 자동 failover, 기존 대화 재개, 모든 앱/Remote 기능은 별도 검증 범위다.

## CodexMulti 수정 대상

0.2.14의 `core/src/codex_routing_editor.zig`는 두 프록시 URL을 생성하고, 두 값이 모두 일치해야 `.on`으로 판정했다. 모델 URL만 프록시인 설정은 `.conflicting`으로 판정되었다.

0.2.15의 수정 범위는 다음과 같다.

1. 기본 활성화 설정을 모델 URL만 프록시로 보내도록 변경한다.
2. 그 설정을 정상 활성화 상태로 판정하고 비활성화할 수 있게 한다.
3. 기존의 두 URL 프록시 설정을 인식하여 안전하게 전환한다. 사용자가 별도로 지정한 기업용 ChatGPT backend 등은 무조건 삭제하지 않는다.
4. README와 최신 app-server smoke 검증에 로그인/프록시 계정 불일치를 포함한다.

0.2.15에서 위 설정 생성·판정·이전 설정 전환을 구현했다. 레거시 설정은 활성 상태를 유지하며 유휴 시 전환하고, 꺼진 설정과 사용자 지정 ChatGPT 백엔드는 보존한다. 회귀 검증은 현재 app-server의 account/read와 모델 요청을 서로 다른 인증 주체로 실행한다.

설정 의미는 [공식 설정 레퍼런스](https://learn.chatgpt.com/docs/config-file/config-reference)에도 구분되어 있다: `chatgpt_base_url`은 ChatGPT 로그인 흐름, `openai_base_url`은 내장 OpenAI 모델 provider의 base URL 재정의다.

## 0.2.15 구현 검증

- 코어·bridge 회귀 검증: 529개 통과. 설정 백업, 멱등 전환, 사용자 지정 백엔드 보존, 유휴 대기와 프록시 무재시작을 포함한다.
- 프록시 검증: 178개 통과. 로컬 최신 Codex CLI를 사용하는 7개 smoke 검증도 포함하며, app-server의 계정 조회와 모델 요청이 다른 계정을 사용하는 조건에서 성공했다.
