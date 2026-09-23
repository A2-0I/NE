# AI 프로세스 VIP 종합 테스트 V1

## 테스트 V1에 들어간 기능

### 사용자
- 기존 AI 프로세스 로그인 상태 그대로 사용 (자동 로그아웃 추가하지 않음)
- VIP 홈
- VIP 단체채팅
- 사진 첨부 (8MB 이하)
- 자기 메시지 삭제
- 답장
- 최초 입장 시스템 메시지
- 관리자 강퇴 시 단체채팅 입력 차단
- 1:1 관리자 상담 + 사진 첨부 + 메시지 삭제
- 이벤트 목록 / 참여 / 당첨 결과
- 동물·음식·사물·자연 100종 프로필 프리셋 (사람 이미지 없음)
- 이벤트/관리자 공지 알림 ON/OFF
- 1:1 답변 알림 ON/OFF
- 단체채팅 일반 메시지 알림은 항상 OFF

### 관리자
- VIP 운영 대시보드
- 원하는 문구로 VIP 전체 알림 등록
- 단체채팅 메시지 관리자 삭제
- 회원 강퇴 / 강퇴 해제
- 1:1 상담 3단 UI (상담 목록 / 채팅 / 회원·AI프로세스 정보)
- 새 1:1 문의 브라우저 알림 + 알람음
- Realtime + 30초 보조 조회
- 이벤트 생성 / 알림 문구 / 참여자 자동 추첨 / 당첨 알림

## 설치 순서

1. Supabase SQL Editor에서 `AI_PROCESS_VIP_TEST_V1_SETUP.sql`을 한 번 실행합니다.
2. `AI_PROCESS_VIP_TEST_V1.zip`의 `AI-main` 내용을 현재 GitHub Pages 프로젝트에 반영합니다.
3. 유저로 로그인 후 기존 대시보드 상단의 `VIP` 버튼으로 입장합니다.
4. 관리자 페이지에는 `VIP 관리` 메뉴가 추가됩니다.
5. VIP 홈 또는 관리자 VIP 대시보드에서 `알림 허용`을 눌러 브라우저 알림 권한을 허용합니다.
6. 관리자 1:1 문의 알람음을 사용하려면 `문의 알람 켜기`를 한 번 누릅니다.

## 알림 테스트 범위

V1 기본 상태:
- 사이트/브라우저가 열려 있으면 Supabase Realtime으로 즉시 감지
- Realtime을 놓쳐도 30초마다 보조 확인
- 단체채팅 일반 메시지는 알림 없음
- 이벤트/관리자 지정 공지/1:1 상담만 알림
- 알림 클릭 시 해당 VIP/관리자 화면으로 이동

브라우저가 완전히 종료된 상태에서도 카카오톡처럼 알림을 받으려면 Web Push 서버 발송이 필요합니다.
그 역할을 하는 샘플이 `supabase/functions/vip-push/index.ts`입니다.

## Edge Function이란?

Supabase 서버에서 실행되는 작은 서버 프로그램입니다.
현재 사이트 HTML/JS는 사용자의 브라우저에서 실행되므로 비밀키를 숨길 수 없습니다.

Edge Function을 사용하면:
1. DB에 `새 1:1 문의` 또는 `이벤트 알림`이 등록됨
2. Supabase 서버의 Edge Function이 그 알림을 확인
3. 사용자가 등록한 Push Subscription으로 Web Push 전송
4. 브라우저 탭을 닫았어도 OS 알림 배너 표시
5. 배너를 누르면 `sw.js`가 AI 프로세스 VIP의 해당 화면을 다시 엶

즉, 전체 AI 프로세스를 Edge Function으로 바꾸는 것이 아니라 **백그라운드 푸시 발송 부분만 서버에 맡기는 것**입니다.

## 배경 Web Push를 나중에 활성화하려면

V1에는 준비 코드만 포함되어 있습니다.

필요한 것:
- VAPID public/private key
- Supabase Edge Function `vip-push` 배포
- Edge Function Secrets 설정:
  - `VAPID_PUBLIC_KEY`
  - `VAPID_PRIVATE_KEY`
  - `VAPID_SUBJECT`
  - `VIP_PUSH_HOOK_SECRET`
- `shared/vip-push-config.js`에 VAPID 공개키 입력
- `vip_notifications` INSERT 시 Edge Function을 호출하는 Supabase Database Webhook 생성

Database Webhook 요청에는 `x-vip-push-secret` 헤더로 `VIP_PUSH_HOOK_SECRET` 값을 넣습니다.

## 중요: 테스트 보안

현재 기존 AI 프로세스가 자체 로그인 + anon key + RLS OFF 구조이므로,
이번 VIP V1도 **기능 검증용으로 같은 방식**에 맞췄습니다.

따라서 이 버전은 기능/화면 테스트용입니다.
실제 다수 회원이 사용하는 운영판으로 전환할 때는 채팅·1:1 상담 데이터에
Supabase Auth/RLS 또는 Edge Function 기반 서버 검증을 추가하는 것이 안전합니다.
