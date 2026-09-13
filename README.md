# DataGuard — iPad 셀룰러 사용량 추정 프로토타입

개인 iPad mini 6 Cellular용 SwiftUI 앱입니다. **초과 요금 차단을 보장하는 도구가 아닙니다.** 공개 API로 읽은 인터페이스 RX + TX 증가량을 저장하고, 단축어에 중단 권고를 전달합니다. VPN·프록시·외부 서버·광고·분석 SDK·Private API·NetworkExtension을 사용하지 않습니다.

사용자 확인: 대상 iPadOS **26.6.2**, 이번 달 초기 사용량 **0바이트**. 실제 테스트 중 소비한 데이터는 이후 보정값에 포함해야 합니다. 이 Mac의 검증 환경은 **Xcode 26.6 (17F113), iOS/iPadOS SDK 26.5**, 설치된 Simulator 런타임은 **26.4**입니다. 최소 지원 버전은 iPadOS 17.0입니다. 실기기 연결·서명·26.6.2 실행은 아직 검증하지 않았습니다.

## 먼저 알아야 할 결론

- `getifaddrs`, `ifaddrs`, `if_data`, `ifi_ibytes`, `ifi_obytes`를 실제 SDK로 컴파일했습니다. 인터페이스별 카운터를 읽을 수 있지만 정확한 월별 과금량 API는 아닙니다.
- SDK `net/if_var.h`의 `if_data.ifi_ibytes`와 `ifi_obytes`는 각각 **UInt32**입니다. 각 방향에서 4,294,967,296바이트(약 4.29 GB)마다 순환할 수 있습니다. UInt64로 변환해도 원래 값이 64비트가 되지는 않습니다. `ifa_data`를 임의로 `if_data64`로 해석하지 않습니다.
- 카운터 초기화와 순환, 측정 사이에 사라졌다 되살아난 인터페이스, 여러 번 순환한 카운터를 완전히 복원할 수 없습니다. 현재 값이 이전보다 커도 중간 초기화·순환이 없었다는 증거가 되지 않습니다.
- `pdp_ip*`는 **미검증 후보 힌트**입니다. 자동 후보만으로 안전 상태를 선언하지 않습니다. 실기기 비교 후 수동 선택과 현재 사용량 보정이 필요합니다.
- 앱이 셀룰러 데이터/라디오를 켜거나 끄는 공개 API를 구현한 것은 아닙니다. **BLOCK은 차단 권고이지 실제 차단 완료가 아닙니다.**
- 일반 앱의 지속 백그라운드 실행, 정시 검사, 사용량 도달 순간 자동 차단을 보장하지 않습니다. 영상 재생을 시작할 때 한 번 검사했다고 재생 중 계속 보호되지는 않습니다.

Apple DTS는 시스템 인터페이스 통계에 제약이 있으며 다른 앱별 사용량 API는 없다고 설명합니다. [Apple DTS: 데이터 사용량](https://developer.apple.com/forums/thread/81833). Apple은 BSD 이름이 API 계약이 아니라고 명시합니다. [Apple DTS: 인터페이스 이름](https://developer.apple.com/forums/thread/798519).

## 설치

1. `DataGuard.xcodeproj`를 Xcode로 엽니다. `Package.swift`는 계산 테스트용이므로 앱 설치는 **xcodeproj**로 진행합니다.
2. iPad를 Mac에 연결하고 양쪽의 신뢰 요청을 처리합니다.
3. iPad에서 필요하면 **설정 → 개인정보 보호 및 보안 → 개발자 모드**를 활성화합니다.
4. Xcode에서 DataGuard 타깃 → Signing & Capabilities → Automatically manage signing을 켜고 본인의 **Team / Personal Team**을 선택합니다.
5. `com.local.dataguard`가 계정에서 사용 불가능하면 본인만의 Bundle Identifier로 변경합니다. 프로젝트에 임의의 계정이나 인증서를 넣지 않았습니다.
6. 실행 대상으로 실제 iPad를 선택하고 Run(⌘R) 합니다. 개인 서명의 유효 기간이 끝나면 다시 빌드·설치해야 할 수 있습니다.
7. Xcode가 OS 지원 구성요소를 요구하면 Xcode → Settings → Components에서 해당 플랫폼 지원을 설치합니다. OS 업데이트 직후라면 대응 Xcode도 필요할 수 있습니다.

**이 Mac의 환경 특이사항:** generic iOS destination 빌드는 Xcode가 “iOS 26.5 is not installed”라고 표시했습니다. SDK 헤더·컴파일러·링커는 설치되어 있으므로 `-target DataGuard -sdk iphoneos`를 직접 지정한 실제 arm64 빌드로 검증했습니다. 실기기 설치에 필요한 플랫폼 구성요소나 개발자 디스크 이미지는 연결 시 추가 확인해야 합니다. 초기 Swift 매크로 빌드는 실행 샌드박스에 막혔으나 정상 Xcode 실행 환경에서는 통과했습니다.

추가 entitlement/Capability는 없습니다. App Intents는 앱 타깃 내부에서 실행되며 별도 Extension이나 App Group이 필요하지 않습니다. 로컬 알림에는 앱 설정 화면에서 요청하는 사용자 알림 허용만 필요합니다. Push Notifications, Background Modes, VPN, 위치·Wi-Fi 정보 entitlement는 필요 없습니다.

## 첫 실기기 테스트 — 적은 데이터로 확인

1. 앱을 처음 열면 0 GB라도 **UNKNOWN / 확인 필요**가 정상입니다. 모르는 사용량을 SAFE로 오인하지 않게 한 동작입니다.
2. 셀룰러를 아직 사용하지 않았다면 현재 과금 사용량은 알려주신 대로 0바이트입니다. 앱 설치는 Wi-Fi로 진행합니다.
3. **인터페이스 진단 → 비교 기준 저장**을 누릅니다. 모든 인터페이스의 이름·index·RX·TX·합계·IP·미검증 후보 표시가 나옵니다.
4. Wi-Fi를 끄고 셀룰러 연결을 확인합니다. 먼저 수 MB 정도만 사용한 뒤 앱에 돌아와 **새로 측정**합니다. 후보가 명확하지 않을 때만 충분한 잔여량을 확인하고 50~100 MB 정도로 비교합니다. 앱이 테스트 파일을 자동 다운로드하지는 않습니다.
5. 기준 이후 RX/TX가 증가한 인터페이스를 확인하고 **이 인터페이스 사용 (Expert)**을 켭니다. 이름만 보고 `pdp_ip0`를 무조건 선택하지 마세요. 겹치는 여러 인터페이스를 합산하면 중복 집계할 수 있으므로 검증된 최소 집합을 선택합니다.
6. **설정 → 실제 사용량 보정**에 이번 달 현재 누적량을 Decimal GB로 입력합니다. 처음 0이어도 테스트에서 쓴 양은 포함합니다. 통신사 값의 지연 반영도 고려합니다. 보정은 앱 숫자를 덮어쓰고 현재 카운터를 새 기준으로 저장합니다.
7. 소량을 더 사용하고 RX + TX 증가가 반영되는지 비교합니다. Wi-Fi만 사용할 때 선택한 카운터가 불필요하게 증가하는지도 비교합니다. 통신사 값과 차이가 크거나 카운터가 고정돼 있으면 안전 도구로 의존하지 마세요.
8. 비행기 모드 ON/OFF, 재부팅, 앱 종료 후 재실행, SIM 변경을 각각 별도로 시험합니다. UNKNOWN과 보정 요구를 확인하고 실제 사용량을 보정합니다.

통신사 사용량이 가장 중요한 비교 기준입니다. iPad 설정의 ‘현재 사용량’도 같은 날짜에 통계를 초기화했을 때만 비교하기 쉽습니다. 앱의 Reset now는 통신사/설정 통계를 바꾸지 않습니다.

## 기본 요금제 및 안전 기준

| 설정 | 기본값 |
|---|---:|
| 월 한도 | 5.00 GB |
| WARNING | 3.50 GB |
| CRITICAL | 3.80 GB |
| BLOCK / 중단 권장 | 4.00 GB |
| 안전 여유 | 1.00 GB |
| 청구 시작일 | 매월 1일 |

`0 < 경고 < 위험 < 차단 기준 < 월 한도`를 검증합니다. 차단 기준과 안전 여유는 `월 한도 − 차단 기준` 관계로 함께 바뀝니다. 5 GB 요금제에서 4.5 GB 이상 또는 안전 여유 0.5 GB 미만이면 영상 사용 위험을 경고합니다. 기본 권장은 **4.0 GB 이하**, 오래 영상을 보거나 점검이 드물면 3.5 GB처럼 더 낮게 잡고 경고·위험 값도 함께 낮추는 것입니다. 이 값 자체가 초과 요금 방지를 보증하지 않습니다.

표시 단위는 GB/GiB를 선택할 수 있습니다. 요금제 입력과 단축어의 `*GB`는 항상 **Decimal GB**입니다. 단위 변경으로 실제 차단 기준이 달라지지 않습니다.

## 측정·저장·초기화 정책

- 앱 활성화, 열린 동안 30초마다, 수동 검사, App Intent 실행 때 측정합니다. `BGTaskScheduler` 및 백그라운드 무한 타이머를 사용하지 않습니다.
- 같은 이름의 IPv4/IPv6 행을 중복 합산하지 않습니다. AF_LINK 행의 `if_data`를 한 번씩 읽고 RX/TX를 각각 비교합니다.
- 최초 인터페이스는 기준값만 저장합니다. 부팅 이후 전체 카운터를 이번 달 사용량으로 잘못 더하지 않습니다.
- 정상 증가에서는 각 방향의 `current − previous`를 누적합니다. 한 방향이 감소하면 그 방향은 `current`만 더하고 **초기화/순환 미확인**을 남깁니다. 이는 복원 가능한 하한 추정이며 누락량은 보정해야 합니다.
- index 변경 또는 감지된 재부팅에서는 현재 RX + TX를 더하고 보정을 요구합니다. uptime과 실제 측정 시각 차이로 재부팅/시간 변경 징후를 확인합니다. 모든 재생성을 탐지할 수는 없습니다.
- 선택 인터페이스가 사라지거나 counter가 없으면 기존 누적량과 기준값을 보존하고 확인 필요로 전환합니다. 다시 나타나도 보정 전까지 확인 필요 상태는 유지합니다.
- **15분 이상 측정 공백**이면 여러 번 순환·재생성 가능성을 보수적으로 표시합니다. 이 15분은 신뢰성을 보장하는 API 수치가 아니라 앱 정책입니다. 더 짧은 공백에서도 누락은 가능합니다.
- 새 청구 기간은 고정된 청구 시간대의 달력으로 계산합니다. 시작일이 31일인데 해당 날짜가 없으면 말일을 사용합니다. 다음 검사 때 누적량을 0으로 바꾸고, 월 경계에 걸친 증가량은 모두 새 기간에 더해 과소집계를 줄이며 확인을 요구합니다. 자정에 앱을 자동 실행하는 것은 아닙니다.
- 청구 날짜·시간대 설정을 변경하면 기존 누적량은 보존하고 새 기간 기준을 적용한 뒤 보정을 요구합니다. 여행 중 기기 시간대 변경으로 자동 초기화하지 않습니다.
- Reset now는 확인창을 거친 0 GB 보정입니다. 현재 유효한 수동 선택 인터페이스가 있어야 합니다. 보정/초기화 시 알림 단계 이력도 초기화됩니다.
- 누적값·설정·최근 100개 timestamp/delta를 앱 내부 `Application Support/DataGuard/state.json`에 Codable JSON으로 원자적 저장합니다. 앱과 앱 내부 Intent는 MainActor의 읽기/수정/쓰기 트랜잭션을 공유합니다. 앱 삭제 시 로컬 기록도 사라집니다.
- 파일 손상·읽기/쓰기 실패를 0 GB / SAFE로 조용히 바꾸지 않습니다. 오류를 표시하고 기존 손상 파일을 보존합니다. 백업 복구 또는 앱 재설치 후 현재 통신사 값으로 재보정해야 합니다.

## Shortcuts 설정 — 권장 Boolean 방식

이 앱의 액션:

| 액션 검색명 | 결과 |
|---|---|
| Get Cellular Usage | 속성들을 가진 Cellular Usage 엔티티 |
| Check Data Limit | 한국어 안내 문자열 |
| Should Block Cellular | IF에서 바로 사용할 Boolean |

Get Cellular Usage 속성: `usedBytes`(Int), `usedGB`, `remainingToCutoffGB`, `remainingToAllowanceGB`(Double), `status`(safe/warning/critical/block/unknown), `shouldBlock`(Bool), `increaseBytes`(Int), `rapidUsage`, `requiresReview`, `isSimulated`(Bool), `sampledAt`(Date), `explanation`(String).

`shouldBlock`은 4 GB 이상뿐 아니라 **미검증·측정 누락 의심**에서도 true입니다. Should Block Cellular는 측정/저장 오류를 잡아 true를 반환합니다. Get Cellular Usage는 오류를 던지므로 오류 때 단축어가 중단될 수 있습니다. 안전 자동화에는 Boolean 액션을 권장합니다. OS가 앱 실행 자체를 거부하거나 강제 종료하면 Boolean조차 반환하지 못할 수 있습니다.

### 셀룰러 OFF 액션의 검증 범위

Apple 기본 셀룰러 제어 동작은 DataGuard의 SDK API가 아닙니다. 설치된 26.4 Simulator의 Shortcuts 리소스에는 셀룰러 미지원 기기 안내가 있으며, **이 Mac의 Simulator에서 iPad mini 6 Cellular + 26.6.2의 실제 OFF 동작을 검증할 수 없습니다.** SDK 컴파일 성공만으로 대상 기기의 Apple 액션 존재·실행 성공을 확정하지 않습니다.

따라서 실제 iPad의 단축어에서 **‘셀룰러 데이터 설정’ / ‘Set Cellular Data’**를 검색해 액션이 제공되는지 먼저 확인하세요. 존재하면 다음 흐름을 구성합니다. 없다면 아래 알림·수동 OFF 대안을 사용합니다. ‘요금제 토글’과 ‘셀룰러 데이터 끄기’는 서로 다른 동작일 수 있으므로 이름이 비슷하다고 대신 연결하지 마세요.

### 1. 재사용할 단축어 만들기

1. DataGuard를 설치 후 한 번 실행합니다.
2. 단축어 → `+` → 새 단축어 이름을 ‘DataGuard 안전 검사’로 지정합니다.
3. 앱/동작 검색에서 **DataGuard → Should Block Cellular**(차단 권장 확인)를 추가합니다.
4. **If / 조건문**을 추가하고 이전 동작의 Boolean 결과가 **참**인 조건으로 설정합니다.
5. 참 분기에 대상 iPad에 실제로 제공되는 **셀룰러 데이터 설정 → 끔**을 넣습니다. ‘토글’로 두면 꺼져 있던 데이터를 켤 수 있으므로 반드시 **끔**으로 고정합니다.
6. 선택적으로 **알림 보기** 또는 **알림 표시** 동작으로 ‘셀룰러 중단 권장: DataGuard 확인’을 알립니다. iPad 언어/버전에 따라 UI 명칭이 다를 수 있습니다.
7. 거짓 분기는 비워둡니다. 데이터를 자동으로 다시 켜지 않습니다.
8. 저장 후 먼저 수동 실행합니다. 테스트 모드 4.00 GB에서 결과 true와 실제 제어 센터의 셀룰러 OFF 여부를 확인합니다. 시험이 끝나면 테스트 모드를 끕니다.

**Apple OFF 동작이 없는 경우:** 참 분기에서 위 알림만 표시하고, 제어 센터 또는 **설정 → 셀룰러 데이터**에서 직접 끕니다. 앱은 undocumented `prefs:` URL이나 강제 설정 조작을 사용하지 않습니다. 알림만으로 물리적 차단이 되는 것은 아닙니다.

### 2. 영상 앱 실행 자동화

1. 단축어 → 자동화 → `+` → **앱**을 선택합니다.
2. YouTube, Netflix 또는 원하는 설치 앱을 선택하고 **열릴 때**를 선택합니다.
3. 실행 옵션에서 **즉시 실행**이 제공되면 선택합니다. 확인이 필요한 OS/정책 상태에서는 자동 실행을 보장할 수 없습니다.
4. ‘단축어 실행’ 동작으로 위 **DataGuard 안전 검사**를 연결합니다.
5. Disney+, Wavve, TVING, Safari, App Store 등에도 필요한 범위로 반복합니다. 닫힐 때 검사도 다음 사용 전 누적 갱신에 도움이 되지만 재생 중 감시는 아닙니다.

Apple 문서가 확인하는 앱 열림/닫힘과 Wi-Fi 연결 트리거를 기준으로 안내합니다. [Apple: 설정 트리거](https://support.apple.com/guide/shortcuts/apde31e9638b/ios).

### 3. Wi-Fi 관련

Wi-Fi 자동화에서 선택한 네트워크 또는 Any Network에 **연결될 때** 같은 검사 단축어를 실행할 수 있습니다. 검증한 Apple 가이드는 연결 트리거를 설명합니다. 연결 해제 트리거는 대상 OS UI에서 실제 제공되는지 별도 확인하기 전까지 이 프로젝트의 확정 기능으로 안내하지 않습니다. Wi-Fi 연결 자동화만으로 셀룰러 전환 직전 보호가 되지는 않습니다.

## 테스트 모드와 알림

설정 → Developer / Test Mode → 가상 사용량 사용 → 0 / 3.4 / 3.5 / 3.8 / 3.99 / 4.00 / 4.5 / 5.0 GB → **설정 저장**. 대시보드와 세 Intent가 같은 가상값을 사용합니다. 항상 테스트 배너가 표시되고 바로 종료할 수 있습니다. Release에서도 사용자가 명시적으로 켤 수 있으며 기본은 OFF입니다.

실제 누적량과 테스트 단계 이력은 분리됩니다. 테스트 중 실측 누적은 멈추며 종료 후 이전 실측 snapshot과 비교합니다. 그 사이의 공백·순환·초기화는 기존 한계가 적용됩니다. 가상값이 감소하면 rapid 증가량을 0으로 처리합니다. 테스트 단축어에 Apple OFF 동작을 연결해 두었다면 **실제 셀룰러는 꺼질 수 있습니다**.

설정 → 로컬 알림에서 권한을 요청합니다. 측정 시 새로 도달한 가장 높은 단계만 한 번 알립니다. 3.4→4.0 GB로 건너뛰면 BLOCK 알림 하나를 보냅니다. 단계가 낮아졌다 올라와도 같은 기간에는 중복하지 않습니다. 새 기간·수동 보정·초기화에서 이력이 새로 시작됩니다. 테스트 이력은 테스트 종료/진입 때 초기화됩니다. 권한 거부 또는 OS 알림 설정·집중 모드로 배너가 보이지 않을 수 있습니다. 허용 전에는 단계 이력을 소비하지 않습니다.

Rapid Usage는 **최근 두 검사 사이 300 MB 이상 증가하고 경고 기준 이상**일 때 true입니다. 실시간 전송률이 아닙니다.

## 공개 API / 개인정보

사용 API: SwiftUI, Foundation(Date/Calendar/Codable/FileManager/Data/ProcessInfo.systemUptime), Observation, Darwin(getifaddrs/freeifaddrs/if_data/if_nametoindex/getnameinfo), AppIntents(AppIntent/AppEntity/EntityQuery/AppShortcutsProvider), UserNotifications(UNUserNotificationCenter/UNNotificationRequest).

인터넷 요청이나 사용자 데이터 외부 전송 코드가 없습니다. 숫자와 설정을 앱 내부에 저장합니다. IP 주소는 진단 화면에서만 표시하며 저장하지 않습니다. `PrivacyInfo.xcprivacy`에 외부 수집/추적 없음, 측정 사이 경과 시간 비교에 사용하는 SystemBootTime 사유 `35F9.1`을 선언했습니다. [Apple: Required Reason API](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype). 패킷을 가로채거나 라우팅하지 않으므로 트래픽 경로·핑·회선 속도를 바꾸지 않습니다. 주기적 화면 갱신에 따른 일반적인 앱 CPU/전력 비용은 있습니다.

## 빌드와 테스트

```sh
./Scripts/build.sh iphoneos Release
./Scripts/build.sh iphonesimulator Debug
swift test
```

스크립트는 컴파일 검증용으로 서명을 끕니다. 실제 iPad 설치는 앞의 Xcode 서명 절차를 사용하세요. 빌드 로그는 `Validation/`에 기록됩니다.

검증 내용과 최종 결과는 **Validation/REPORT.md**를 참고하세요. 핵심 계산 테스트는 macOS에서 같은 Core 소스로 실행됩니다. macOS 테스트를 iPad 실측 검증으로 표현하지 않습니다.

## 파일 구조

- `DataGuard.xcodeproj/`: 앱 타깃, Debug/Release, 공유 DataGuard scheme
- `DataGuard/Core/NetworkUsageMonitor.swift`: 공개 BSD API 읽기·중복 제거
- `DataGuard/Core/UsageStore.swift`: delta, 보정, 기간, 상태/리포트
- `DataGuard/Core/SettingsStore.swift`: 요금제·단위·청구일 검증
- `DataGuard/Core/PersistentStore.swift`: Codable 파일 저장
- `DataGuard/Core/NotificationPolicy.swift`: 알림 단계 결정
- `DataGuard/AppModel.swift`: 화면과 Intent의 공통 측정·저장 흐름
- `DataGuard/DataGuardApp.swift`: iPad 내비게이션·활성 상태 측정
- `DataGuard/Views/`: DashboardView, DiagnosticsView, SettingsView
- `DataGuard/Intents/DataGuardIntents.swift`: 세 가지 Intent와 엔티티
- `DataGuard/NotificationService.swift`: 로컬 알림·권한·중복 방지
- `DataGuard/PrivacyInfo.xcprivacy`: 개인정보 manifest
- `Package.swift`, `Tests/`: Core 테스트
- `Scripts/build.sh`, `Validation/`: 재현 가능한 빌드와 검증 자료

아이콘은 설치된 SDK/Simulator 런타임 버전 차이로 인한 asset catalog 컴파일 문제를 피하도록 `Config/Info.plist`와 두 개의 표준 iPad PNG 리소스로 구성했습니다. 생성 원본은 `Scripts/GenerateIcon.swift`, 1024px 디자인은 `Design/`에 있습니다.
