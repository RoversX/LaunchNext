# LaunchNext

**언어**: [English](../README.md) | [中文](README.zh.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Français](README.fr.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [Русский](README.ru.md) | [हिन्दी](README.hi.md) | [Tiếng Việt](README.vi.md) | [Italiano](README.it.md) | [Čeština](README.cs.md)

## 📥 다운로드

**[눌러서 다운받기](https://github.com/RoversX/LaunchNext/releases/latest)** - 여기서 최신 버전을 받을 수 있어요

🌐 **웹사이트**: [closex.org/launchnext](https://closex.org/launchnext/)  
📚 **문서**: [docs.closex.org/launchnext](https://docs.closex.org/launchnext/)

⭐ [LaunchNext](https://github.com/RoversX/LaunchNext)와 원본 프로젝트 [LaunchNow](https://github.com/ggkevinnnn/LaunchNow)에 star를 달아주세요!

| | |
|:---:|:---:|
| ![](../public/banner.webp) | ![](../public/setting1.webp) |
| ![](../public/setting2.webp) | ![](../public/setting3.webp) |

macOS Tahoe는 런치패드가 사라졌고, 새로운 인터페이스는 비직관적이며 Bio GPU를 제대로 활용하지 못해요.
Apple이 런치패드를 다시 제공하는날이 올때, 그때까지 LaunchNext를 사용해보세요.

*[LaunchNow](https://github.com/ggkevinnnn/LaunchNow) (ggkevinnnn 제작)을 기반으로 개발되었어요. 원본 프로젝트에 진심으로 감사드려요!❤️*

*LaunchNow는 GPL 3 라이선스를 선택했습니다. LaunchNext도 동일한 라이선스 조건을 따릅니다.*

⚠️ **macOS가 앱을 차단하면 터미널에서 실행하세요:**
```bash
sudo xattr -r -d com.apple.quarantine /Applications/LaunchNext.app
```
**왜요?**: 저는 Apple의 개발자 인증서($99/년)를 살 여유가 없어서 macOS가 서명되지 않은 앱을 차단해요. 이 명령어는 격리 플래그를 제거해서 앱이 실행되도록 합니다. **반드시 신뢰할 수 있는 앱에만 사용하세요.**

## LaunchNext가 제공하는 것

- ✅ **기존 시스템 Launchpad 원클릭 가져오기** - 네이티브 Launchpad SQLite 데이터베이스를 직접 읽어 폴더, 앱 위치, 레이아웃을 복원해요
- ✅ **수동 앱 정리** - 앱 이동, 폴더 생성, 원하는 레이아웃 유지가 가능해요
- ✅ **두 가지 렌더링 경로** - 호환성을 위한 `Legacy Engine`, 최고의 경험을 위한 `Next Engine + Core Animation`
- ✅ **컴팩트 / 전체화면 모드** - 각각 별도 설정을 유지할 수 있어요
- ✅ **키보드 중심 워크플로우** - 빠른 검색, 탐색, 실행 지원
- ✅ **CLI / TUI 자동화 지원** - 터미널에서 레이아웃을 확인하고 관리 가능
- ✅ **Hot Corner와 네이티브 제스처 활성화** - 다양한 전역 실행 방식 제공
- ✅ **앱을 Dock으로 직접 드래그** - Core Animation 엔진에서 사용 가능
- ✅ **Markdown 릴리즈 노트를 지원하는 업데이트 센터** - 더 풍부한 인앱 업데이트 경험
- ✅ **백업 / 복원 도구** - 더 안전한 내보내기와 복구 흐름
- ✅ **접근성과 컨트롤러 지원** - 음성 피드백과 컨트롤러 탐색 강화
- ✅ **다국어 지원** - 폭넓은 현지화 제공

## macOS Tahoe가 없애버린 것

- ❌ 커스텀 앱 정리 불가
- ❌ 사용자 폴더 생성 불가
- ❌ 드래그 앤 드롭 사용자화 불가
- ❌ 시각적 앱 관리 불가
- ❌ 강제 카테고리 그룹화

## 데이터 저장

앱 데이터는 다음 위치에 저장돼요:

```text
~/Library/Application Support/LaunchNext/Data.store
```

## 네이티브 Launchpad 통합

LaunchNext는 시스템 Launchpad 데이터베이스를 직접 읽을 수 있어요:

```bash
/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db
```

## 설치

### 요구사항

- macOS 26 (Tahoe) 이상
- Apple Silicon 또는 Intel 프로세서
- Xcode 26 (소스에서 빌드할 경우)

### 소스에서 빌드

1. **저장소 복제**
   ```bash
   git clone https://github.com/RoversX/LaunchNext.git
   cd LaunchNext
   ```

2. **Xcode에서 열기**
   ```bash
   open LaunchNext.xcodeproj
   ```

3. **빌드 및 실행**
   - 타겟 디바이스 선택
   - `⌘+R`로 빌드 및 실행
   - `⌘+B`로 빌드만 가능

### 명령줄 빌드

**일반 빌드:**
```bash
xcodebuild -project LaunchNext.xcodeproj -scheme LaunchNext -configuration Release
```

**유니버설 바이너리 빌드 (Intel + Apple Silicon):**
```bash
xcodebuild -project LaunchNext.xcodeproj -scheme LaunchNext -configuration Release ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build
```

## 사용법

### 시작하기

1. LaunchNext는 첫 실행 시 설치된 앱을 스캔해요
2. 기존 Launchpad 레이아웃을 가져오거나 빈 레이아웃에서 시작해요
3. 검색, 키보드 탐색, 마우스 드래그, 폴더로 앱을 정리해요
4. 설정에서 엔진, 레이아웃 모드, 활성화 방식, 자동화를 구성해요

### Launchpad 가져오기

1. 설정 열기
2. **Import Launchpad** 클릭
3. 기존 레이아웃과 폴더가 자동으로 가져와져요

### 엔진과 레이아웃 모드

- **Legacy Engine** - 오래된 렌더링 경로를 유지해 호환성을 우선해요
- **Next Engine + Core Animation** - 권장. 전체 경험과 신기능 지원이 더 좋아요
- **컴팩트 / 전체화면** - 두 모드를 모두 지원하며 각각 별도 설정을 저장할 수 있어요

## 주요 기능

### 활성화와 입력

- **Hot Corner 지원** - 설정 가능한 화면 모서리에서 LaunchNext 열기
- **실험적 네이티브 제스처 지원** - 4손가락 pinch / tap 동작
- **전역 단축키 지원** - 어디서든 LaunchNext 열기
- **Dock으로 드래그** - Core Animation 엔진에서 macOS Dock에 직접 앱 넘기기

### 자동화와 파워유저 워크플로우

- **CLI / TUI 지원** - 레이아웃 확인, 앱 검색, 폴더 생성, 앱 이동, 자동화 가능
- **agent 친화적 워크플로우** - 터미널 기반 AI agent와 shell 자동화에 잘 맞아요
- **설정에서 명령줄 활성화** - 관리되는 `launchnext` 명령을 설치하거나 제거 가능

### 업데이트 경험

- **앱 내 업데이트 센터** - 앱을 떠나지 않고 업데이트 확인
- **Markdown 릴리즈 노트** - 설정 안에서 더 풍부한 릴리즈 노트 표시
- **최신 알림 API** - 새로운 macOS 알림 경로 지원

### 백업과 복원

- 설정에서 백업 생성 및 복원 가능
- 더 신뢰할 수 있는 백업 내보내기 동작
- 임시 파일 및 정리 경로를 더 안전하게 처리

### 접근성과 탐색

- **음성 피드백 지원** - 탐색 중 앱과 폴더 이름을 읽어줘요
- **컨트롤러 지원** - 게임 컨트롤러로 LaunchNext와 폴더를 조작 가능
- **키보드 중심 상호작용** - 마우스 없이도 빠른 검색과 이동 가능

## 성능과 안정성

- 부드러운 탐색을 위한 지능형 아이콘 캐시
- 대규모 라이브러리를 위한 지연 로딩과 백그라운드 스캔
- 설정 및 탐색 흐름 전반의 상태 동기화 개선
- 업데이트 처리, 백업 내보내기, 제스처 복구의 신뢰성 향상

## 문제 해결

### 일반적인 문제

**Q: 앱이 실행되지 않아요?**  
A: macOS 26 이상인지 확인하고, 필요하면 quarantine을 제거한 뒤, 신뢰할 수 있는 빌드를 사용하세요.

**Q: 어떤 엔진을 써야 하나요?**  
A: `Next Engine + Core Animation` 을 권장해요. 오래된 호환성 경로가 꼭 필요할 때만 `Legacy Engine` 을 사용하세요.

**Q: CLI 명령이 아직 없어요. 왜 그런가요?**  
A: 먼저 설정에서 명령줄 인터페이스를 활성화하세요. LaunchNext가 관리되는 `launchnext` shim을 설치하고 제거할 수 있어요.

## 기여

기여를 환영해요.

1. 저장소 포크
2. 기능 브랜치 생성 (`git checkout -b feature/amazing-feature`)
3. 변경사항 커밋 (`git commit -m 'Add amazing feature'`)
4. 브랜치에 푸시 (`git push origin feature/amazing-feature`)
5. Pull Request 열기

### 개발 가이드라인

- Swift 스타일 규칙 따르기
- 복잡한 로직에 의미 있는 주석 추가
- 가능하면 여러 macOS 버전에서 테스트
- 실험적 기능을 관련 없는 파일에 흩뿌리지 않기
- 제거 가능한 통합은 가능한 한 분리하기

## 앱 관리의 미래

Apple이 커스터마이징 가능한 앱 런처에서 멀어지는 동안, LaunchNext는 현대 macOS에서도 수동 정리, 사용자 제어, 빠른 접근을 유지하려고 합니다.

**LaunchNext**는 단순한 Launchpad 대체제가 아니라, 퇴행한 워크플로우에 대한 실용적인 대응입니다.

---

**LaunchNext** - 앱 런처의 주도권을 되찾으세요 🚀

*커스터마이징을 포기하고 싶지 않은 macOS 사용자를 위해.*

## 개발 도구

- Claude Code
- Cursor
- OpenAI Codex CLI
- Perplexity
- Google

- 실험적 제스처 지원은 [OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport) 와 [KrishKrosh](https://github.com/KrishKrosh/OpenMultitouchSupport) 포크를 기반으로 합니다.❤️

![GitHub downloads](https://img.shields.io/github/downloads/RoversX/LaunchNext/total)
