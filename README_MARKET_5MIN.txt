AI PROCESS · 5분 시장현황 적용 방법
==================================

1. GitHub 파일은 이 ZIP 전체를 기준으로 업로드합니다.

2. Supabase > SQL Editor에서
   AI_PROCESS_MARKET_5MIN_SETUP.sql
   파일 내용을 전체 실행합니다.

3. SQL 마지막 결과에서 아래를 확인합니다.
   - refreshed_symbols : 1 이상 (정상이라면 최대 4)
   - app_market_5m 테이블에 TSLA / NVDA / BTC / SOL 행 생성
   - cron.job 에 ai-market-pulse-5m / */5 * * * * / active=true

4. 사용자 AI 프로세스 페이지를 새로고침합니다.

표시 규칙
---------
- 실제 시장 데이터는 Supabase가 5분마다 갱신합니다.
- 대상: Tesla(TSLA), NVIDIA(NVDA), Bitcoin(BTC), Solana(SOL)
- 최근 5분 변동률이 +인 종목만 화면에 표시합니다.
- 주식 데이터가 장 마감 등으로 오래된 경우 화면에서 자동 제외합니다.
- '투자금 기준 +금액'은 선택한 AI 프로세스 투자금 × 최근 5분 상승률의 단순 환산입니다.
- 이 환산값은 실제 app_profit_logs / realized_amount에 더하지 않습니다.

데이터 출처
-----------
- 주식: Yahoo Finance chart endpoint (5m)
- 코인: Coinbase Exchange public candle endpoint (5m)

중요
----
Yahoo Finance chart endpoint는 비공식 API 성격이므로 향후 제공자 응답 형식이나 접근 정책이 바뀌면
주식 데이터 제공자를 정식 API(Twelve Data 등)로 교체해야 할 수 있습니다.
