AI PROCESS VIP · GITHUB + SUPABASE V4

기준
- 기존 NE-main + Supabase 스키마/인증 구조 유지
- SQL/DB 구조 변경 없음

V4 핵심 변경
- Warm Ivory + Charcoal + Champagne Gold + Muted Coral 디자인 시스템
- 그룹채팅 말풍선 전면 재설계
- 내 메시지 오른쪽 / 상대 메시지 왼쪽 고정
- 모바일 채팅 내부 스크롤 및 하단 입력창 고정
- 이벤트 Dock 유지 및 새 테마 적용
- 귀여운 프리미엄 동물 아바타 세트 적용
- 이벤트 페이지 LIVE/UP NEXT Spotlight 추가
- 관리자 투자 생성 모달 글자/입력칸 가독성 오류 수정
- 기존 app_users / app_investments / VIP 테이블 / 세션키 유지

이번 버전에서 하지 않은 것
- 채팅 운영시간 DB 기능
- 블랙리스트 로그인 차단 DB 기능
- 20회 자동 이벤트 엔진
- 실제 5분 시장 데이터 연동
위 기능은 다음 단계에서 기존 DB를 보존한 채 확장 예정입니다.

V4 후속 수정 - PROFIT ENGINE REPAIR
- 채팅 높이 수정 유지
- 프로필 100종 수정 유지
- 자동 수익/손실 미발생 문제용 AI_PROCESS_PROFIT_ENGINE_REPAIR.sql 추가
- 최소 1시간 ~ 최대 30일 기준 유지
- GitHub 파일만으로 DB 함수/cron은 바뀌지 않으므로 Supabase SQL Editor에서 위 SQL을 1회 실행해야 함
