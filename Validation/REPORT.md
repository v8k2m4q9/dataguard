# DataGuard 검증 결과

검증일: 2026-09-13. Xcode 26.6 (17F113), iOS SDK 26.5, Swift 6 strict concurrency. 대상 기기는 사용자가 알려준 iPad mini 6 Cellular / iPadOS 26.6.2입니다.

## 최종 결과

| 검증 | 결과 | 증거 |
|---|---|---|
| iOS arm64 Release 실기기용 컴파일·링크 | **BUILD SUCCEEDED**, 오류/경고 0 | `final-iphoneos-Release.log` |
| iOS Simulator Debug 컴파일·링크 | **BUILD SUCCEEDED**, 오류/경고 0 | `final-iphonesimulator-Debug.log` |
| 계산·저장 단위 테스트 | **16 tests, 0 failures** | `core-tests.log` |
| App Intents 메타데이터 | 액션 3개, 엔티티 1개, App Shortcuts 3개 추출 | `appintents-summary.json` |
| Info.plist / PrivacyInfo | plutil 검증 통과 | 실제 빌드 앱 내부에도 확인 |
| iPad 시뮬레이터 설치·프로세스 실행 | 성공, bundle `com.local.dataguard` | simctl install / launch |
| 최초 UNKNOWN 화면 | 정상 렌더링, 0 GB를 안전으로 단정하지 않음 | `dashboard.png` |
| 4.00 GB 테스트 화면 | BLOCK, 남은 안전 용량 0, 테스트 배너 표시 확인 | `dashboard-block.png` |
| 테스트 후 정리 | 시뮬레이터 원래 저장값 복원, 테스트 OFF 후 재실행 | simctl launch 성공 |

최종 빌드는 `Scripts/build.sh`로 재현할 수 있습니다. 코드 서명을 끈 컴파일 검증입니다. 인증서 서명, 실기기 설치 성공, 실제 셀룰러 OFF 성공을 의미하지 않습니다.

## 단계별 빌드

1. Phase 1: getifaddrs/if_data 최소 앱 — 성공 (`phase1.log`). SDK 헤더에서 RX/TX UInt32 확인.
2. Phase 2: Diagnostics — 성공 (`phase2.log`).
3. Phase 3: 설정/사용량 누적/저장 — 성공 (`phase3.log`).
4. Phase 4: Dashboard/Settings — 성공 (`phase4.log`). Swift 매크로 실행은 정상 Xcode 환경에서 재검증.
5. Phase 5: App Intents — 성공, 경고 0 (`phase5.log`).
6. Phase 6: 알림 — 성공, 경고 0 (`phase6.log`).
7. Phase 7: 문서·아이콘·최종 수정 — Release/Simulator 최종 로그의 성공 확인.

초기 단계에서는 AppIntents를 아직 추가하지 않아 Xcode의 metadata extraction skipped 경고가 있었습니다. Phase 5 이후 사라졌습니다. 초기 샌드박스 Simulator 접근 오류와 현재 SDK/설치 런타임 간의 아이콘 카탈로그 호환 오류는 코드의 경고와 구분합니다. 최종 앱은 추가 런타임 다운로드 없이 컴파일되도록 `Info.plist` 기반 표준 PNG iPad 아이콘을 사용합니다. 원본 디자인은 `Design/`에 있습니다.

## 단위 테스트 내용

- 최초 카운터를 월 사용량으로 잘못 합산하지 않음
- RX와 TX 각각의 증가량, 동일 snapshot 중복 집계 방지
- RX 감소를 TX 증가가 가리는 경우의 초기화 탐지
- UInt32 순환 의심 시 UNKNOWN / shouldBlock
- 인터페이스 소실·재생성, index 변경
- 재부팅, 시간 변경, 15분 초과 측정 공백
- 월 경계의 보수적 증가량 배분 및 알림 단계 초기화
- 31일 청구일의 평년·윤년 2월 처리
- 3.5/3.8/4.0 GB 정확한 임계값, 300 MB rapid 조건
- 가상 사용량과 실제 누적값 분리, GiB 표시와 Decimal 기준 분리
- 잘못된 설정 거부, 유효 인터페이스 없는 보정 거부
- 알림의 최고 새 단계만 발송하는 정책
- 저장 round-trip, 손상 파일을 0으로 덮어쓰지 않는 오류 처리
- macOS 호스트의 실제 getifaddrs 열거 및 인터페이스 이름 중복 제거

테스트는 macOS에서 앱과 같은 Core Swift 소스로 수행했습니다. 네트워크 재부팅·카운터 순환 사례는 주입한 snapshot에 대한 로직 테스트이며 실제 iPad의 통신사 사용량 정확도 실험이 아닙니다.

## 실제 iPad에서 반드시 추가 확인

- Xcode Team 선택, 신뢰/개발자 모드, 26.6.2 장치 지원 구성요소, 서명 후 실행
- AF_LINK counter가 실제로 제공되고 다른 앱 셀룰러 사용을 반영하는지
- 수동 선택할 인터페이스와 RX/TX 증분, 중복 인터페이스 여부
- Wi-Fi-only 사용, 비행기 모드, 재부팅, 네트워크 재접속, SIM/eSIM 변경
- 통신사 과금값과 장기간 차이, 최초 보정과 누락 구간 보정
- 단축어 검색 노출, Boolean IF, Entity 속성 선택, 앱 닫힘/잠금 상태 실행
- Apple 기본 셀룰러 데이터 OFF 액션의 존재와 실제 작동, 즉시 실행 가능 여부
- 알림 허용/거부/집중 모드에서 실제 배너 및 같은 단계 중복 방지
- 테스트 모드를 종료하고 실측 상태로 복귀

UI 자동 조작 도구는 macOS 접근성/화면 기록 권한이 준비되지 않아 사용하지 못했습니다. 시뮬레이터 CLI로 설치·실행·캡처를 확인했습니다. 실제 Shortcuts 편집기에서 검색·조건 실행과 모든 화면 조작을 검증했다고 주장하지 않습니다.

## 한계

공개 API만으로 누락 없는 월별 과금량 및 실시간 자동 차단은 보장할 수 없습니다. 이 프로젝트는 구현 가능한 **진단·추정·중단 권고 프로토타입**입니다. 자세한 측정 정책, Shortcuts 구성, 설치와 실기기 시험 순서는 루트 `README.md`에 있습니다.
