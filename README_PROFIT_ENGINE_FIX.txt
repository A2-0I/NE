AI PROCESS · 자동 수익 발생 문제 수정

이 ZIP은 GitHub 버전 기준이며 Vercel 파일은 사용하지 않습니다.
진행 기간 기준은 최소 1시간 ~ 최대 30일 그대로 유지합니다.

[이번 수정]
- 기존 채팅 높이 수정 유지
- 프로필 100종 수정 유지
- Supabase 자동 수익/손실 지급 엔진 복구 SQL 추가
- run_multi_investment_payouts() 복구
- 각 투자별 last_payout_at 기준 독립 지급 주기 복구
- pg_cron 중복 잡 제거 후 ai-process-timecurve-payout 하나만 등록
- 진행중 투자에 필요한 return_profile / 투자금 로그 / 수익 로그 구조 보완
- 기존 설정값(지급 간격/확률/비율)은 보존하고 enabled만 ON으로 복구
- 기존 회원/투자/수익 데이터 삭제 없음

[중요]
GitHub Pages 파일만 업로드해서는 Supabase의 지급 엔진이 바뀌지 않습니다.
Supabase > SQL Editor에서 AI_PROCESS_PROFIT_ENGINE_REPAIR.sql을 1회 실행해야 합니다.

SQL 실행 직후 마지막 결과에서 다음을 확인하세요.
1) app_payout_settings: enabled = true
2) cron: ai-process-timecurve-payout / active = true
3) running_investments가 1 이상이면 진행중 투자 존재
4) 설정된 every_minutes가 지난 뒤 app_profit_logs에 process_payout 기록 생성

주의: 실제 DB에 이 SQL을 실행하지 않은 상태에서는 '수익 발생 문제 수정 완료'라고 볼 수 없습니다.
