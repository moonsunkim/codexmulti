# 테마 전환 오류: 재현과 수정 설계

2026-09-12 · 상태: 제품 코드 반영 및 실제 창 전환 검증 완료.

## 확인된 원인

현재 테마 적용 경로가 둘로 나뉜다. `SettingsShell`은 자체 `Tone`을 계산해 본문 글자와 배경을 바꾸고, `WindowChrome`은 `NSWindow.appearance`를 직접 바꾼다. 그러나 SwiftUI의 presentation과 `colorScheme`에는 같은 설정을 전달하지 않는다.

실제 `SettingsWindowScene`을 사용하는 격리된 앱에서 Light → Dark → Light → Dark → System을 실행했다. 계정·인증·프록시 서비스는 사용하지 않았다.

| 상태 | 실제 창 | 네이티브 언어 선택·헤더 효과 뷰 | 계정 팝오버 |
| --- | --- | --- | --- |
| 현재 구현, Light | DarkAqua로 돌아감 | Aqua | VibrantDark |
| 현재 구현, Dark | DarkAqua | Aqua로 남음 | VibrantDark |
| 시제품, Light | Aqua | Aqua | VibrantLight |
| 시제품, Dark | DarkAqua | DarkAqua | VibrantDark |

실험의 애플리케이션 기본 appearance는 DarkAqua로 고정했다. 이 값은 실험 프로세스에만 적용했다.

뷰 계층을 추적하면 `AppKitPlatformViewHost<...LanguageSelect>`와 `AppKitPlatformViewHost<...BandVisualEffectView>`에 Aqua가 명시적으로 남는다. 따라서 창을 DarkAqua로 바꾸어도 하위 네이티브 뷰는 Aqua를 유지한다. Light로 전환할 때는 SwiftUI가 창의 직접 지정 값을 nil로 되돌리는 것도 확인했다. `WindowChrome`의 마지막 요청 값 캐시는 이 외부 변경을 검사하지 않는다.

팝오버는 별도 presentation이다. 본문은 Light의 검은 글씨를 받지만 팝오버 창은 VibrantDark를 유지해 첨부 화면처럼 글자와 배경 테마가 달라진다. 언어 선택 너비 수정으로 추가한 NSPopUpButton에도 같은 전달 누락이 드러났다.

## 기존 검증이 놓친 부분

`ScreenshotCapture`는 처음부터 SwiftUI `colorScheme`과 `NSWindow.appearance`를 모두 강제한다. 캡처용 헤더도 실제 toolbar 대신 별도 overlay로 그린다. 그래서 정적인 라이트·다크 스크린샷은 정상이어도 실제 창의 전환 오류는 통과할 수 있다.

기존 WindowChrome 테스트는 가짜 writer의 호출 횟수를 검사한다. 실제 SwiftUI 창, 하위 native host, 별도 팝오버가 전환 뒤 같은 appearance를 갖는지는 검사하지 않는다. 일반 NSWindow + NSHostingView만 사용하는 추가 실험도 정상이라 실제 SwiftUI Window 구성이 재현에 필요했다.

## 적용한 수정

1. **테마 적용 주체를 SwiftUI presentation으로 통일한다.** 설정 값을 최상위 화면의 `preferredColorScheme`에 전달한다. Light는 `.light`, Dark는 `.dark`로 매핑한다. System은 macOS의 현재 appearance를 관찰해 `.light` 또는 `.dark`를 전달한다. [Apple 공식 문서](https://developer.apple.com/documentation/SwiftUI/View/preferredColorScheme%28_%3A%29)는 이 설정이 창·시트·팝오버 같은 presentation에 적용된다고 설명한다.
2. **본문의 색상표도 같은 환경에서 도출한다.** `SettingsShell`은 전달된 `colorScheme`과 `colorSchemeContrast`로 Tone을 고른다. 본문의 별도 SystemAppearance 관찰을 제거한다. 시스템 관찰은 presentation 최상단에서만 사용한다.
3. **WindowChrome에서 테마 쓰기와 캐시를 제거한다.** 이 컴포넌트는 창 모양·위치·닫기 동작만 담당한다. SwiftUI와 NSWindow를 동시에 조작하는 두 번째 테마 적용 경로를 없앤다.
4. **네이티브 부품과 팝오버는 같은 환경을 상속한다.** 언어 선택 폭 240pt와 오른쪽 정렬은 유지한다. 부품마다 색을 하드코딩하거나 창을 재생성하지 않는다. 별도 presentation의 환경 상속은 통합 검증으로 확인한다.

초기 시제품의 `nil` 복귀 방식은 실제 macOS Dark → Light → System 전환 검사에서 하위 네이티브 뷰에 DarkAqua가 남았다. 제품 구현은 `SettingsPresentation`이 시스템 appearance를 관찰해 구체적인 색상 모드를 전달하도록 보완했다. 본문은 SwiftUI 환경만 읽으며 WindowChrome의 직접 appearance 쓰기와 캐시는 제거했다.

`NSApp.appearance`만 바꾸는 실험은 실제 macOS 테마 전환과 다르다. 최종 검증은 System Events로 macOS 테마를 실제로 바꾸고, 명시적 Light/Dark 유지와 System 추적을 확인한 뒤 기존 설정을 복원했다. 닫힌 팝오버 창을 억지로 다시 표시하는 실험도 제외하고 실제로 표시 중인 presentation만 검사한다.

## 검증 범위

- 같은 창에서 Light → Dark → Light, Dark → Light → Dark를 반복한다. 언어 메뉴와 계정 팝오버를 전환 전후에 열어 확인한다.
- System 복귀와 시스템 appearance 변경을 검사한다. 명시적 Light/Dark 선택은 시스템 변경의 영향을 받지 않아야 한다.
- 창 비활성화·재활성화와 닫아 숨긴 뒤 재열기에서도 상태를 유지한다.
- 헤더, 언어 선택, 팝오버, 계정 추가·이름 변경 시트의 글자와 배경이 같은 테마를 사용해야 한다.
- 고대비·투명도 줄이기 설정에서도 대비와 재질이 일관되어야 한다.
- 실제 SwiftUI Window를 사용하는 재현 검증을 유지한다. 새로 시작한 정적 캡처만으로 전환 검증을 대신하지 않는다.

## 재현 자료

로컬 `dist/theme-transition-2026-09-12/`에 시제품 소스 `ThemeProbe.swift`, 현재 구현과 시제품의 appearance 로그, 전환별 창 캡처가 있다. `preferred/`가 시제품 결과다. 실제 계정 대신 생성된 fixture를 사용했다.

제품 구현 검증 기록은 `dist/theme-transition-2026-09-12/system-resolved/`에 있다. 설정, 계정 팝오버, 계정 추가 시트, 이름 변경 시트의 실제 Window 전환 검사가 통과했다. `live-settings.log`, `live-accounts.log`는 실제 macOS 테마 변경까지 포함한다. 고대비 색상표의 대비와 재질 분기는 기존 ThemeTests로 검사했으며, macOS 접근성 설정 자체는 이번에 변경하지 않았다.

재현 명령은 `bash app/scripts/verify-theme-transitions.sh /absolute/output/path`다. `--system-changes`를 두 번째 인자로 주면 macOS 테마도 실제로 변경하며 종료 시 복원한다. 일반 실행은 시스템 설정을 변경하지 않는다. 스크린샷은 Window Server에서 캡처하며 화면 기록 권한이 없는 환경에서는 이미지 없이 appearance 검사를 수행한다.

README 스크린샷은 제품 소개 자료로 별도 갱신한다. 전환 오류의 회귀 검증은 위 실제 Window 검사로 유지한다.
