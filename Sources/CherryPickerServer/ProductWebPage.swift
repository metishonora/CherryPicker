import Foundation

enum ProductWebPage {
    static func render(
        transactions: [SafeTransaction],
        receipts: [SafeEventReceipt]
    ) -> String {
        let parseStatuses = transactions.map { "parseStatus: \($0.parseStatus.rawValue) summary" }
        let syncResults = receipts.map {
            "syncResult: \($0.disposition?.rawValue ?? $0.status.rawValue)"
        }
        let diagnostics = htmlEscape((parseStatuses + syncResults).joined(separator: " · "))

        return #"""
        <!doctype html>
        <html lang="ko">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>CherryPicker</title>
          <style>
            :root {
              color-scheme: light dark;
              --cp-bg: light-dark(#f7f8fa, #101214);
              --cp-surface: light-dark(#ffffff, #171a1d);
              --cp-soft: light-dark(#f2f4f6, #202428);
              --cp-text: light-dark(#191f28, #f2f4f6);
              --cp-subtle: light-dark(#4e5968, #b0b8c1);
              --cp-muted: light-dark(#8b95a1, #8b95a1);
              --cp-line: light-dark(#e5e8eb, #2d3339);
              --cp-accent: light-dark(#e94d79, #ff7895);
              --cp-accent-soft: light-dark(#fff0f4, #3a2028);
              --cp-track: light-dark(#e5e8eb, #333a43);
              --cp-danger: light-dark(#d52f4c, #ff7990);
              --cp-warning: light-dark(#946200, #e8ba64);
              --cp-negative: light-dark(#a53b53, #ff8da6);
            }

            * { box-sizing: border-box; }
            body {
              margin: 0;
              background: var(--cp-bg);
              color: var(--cp-text);
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
              font-size: 16px;
              line-height: 1.5;
            }
            button, input, select, textarea { font: inherit; color: inherit; }
            button { cursor: pointer; }
            [hidden] { display: none !important; }
            .cp-shell { width: min(100%, 760px); margin: 0 auto; min-height: 100vh; background: var(--cp-surface); }
            .cp-header {
              display: flex; gap: 16px; align-items: center; justify-content: space-between;
              padding: 20px 24px 14px; border-bottom: 1px solid var(--cp-line);
              position: sticky; top: 0; z-index: 10; background: color-mix(in srgb, var(--cp-surface) 94%, transparent);
              backdrop-filter: blur(16px);
            }
            .cp-brand { display: grid; gap: 1px; }
            .cp-brand strong { font-size: 20px; font-weight: 700; }
            .cp-brand span { color: var(--cp-muted); font-size: 13px; }
            .cp-card-select {
              min-width: 220px; max-width: 58%; padding: 10px 34px 10px 12px;
              border: 0; border-radius: 12px; background: var(--cp-soft); font-size: 16px;
            }
            .cp-nav {
              display: flex; gap: 4px; overflow-x: auto; padding: 10px 12px;
              border-bottom: 1px solid var(--cp-line); scrollbar-width: none;
            }
            .cp-nav button {
              flex: 0 0 auto; padding: 10px 12px; border: 0; border-radius: 12px;
              color: var(--cp-muted); background: transparent; font-weight: 650;
            }
            .cp-nav button[aria-current="page"] { color: var(--cp-accent); background: var(--cp-accent-soft); }
            .cp-main { padding: 34px 24px 110px; }
            .cp-heading { margin-bottom: 28px; }
            .cp-heading h1 { margin: 0; font-size: clamp(26px, 6vw, 34px); line-height: 1.25; letter-spacing: -0.04em; }
            .cp-heading p { margin: 10px 0 0; color: var(--cp-subtle); }
            .cp-accent { color: var(--cp-accent); }
            .cp-period {
              display: grid; grid-template-columns: 44px minmax(0, 1fr) 44px; align-items: center;
              gap: 10px; margin-bottom: 18px; padding: 8px; border-radius: 16px; background: var(--cp-soft);
            }
            .cp-period strong { text-align: center; font-size: 18px; }
            .cp-period button { width: 44px; height: 44px; border: 0; border-radius: 12px; background: var(--cp-surface); font-size: 25px; line-height: 1; }
            .cp-period button:disabled { cursor: default; opacity: .34; }
            .cp-list { border-top: 1px solid var(--cp-line); }
            .cp-row {
              width: 100%; display: grid; grid-template-columns: minmax(0, 1fr) auto;
              gap: 18px; padding: 19px 2px; border: 0; border-bottom: 1px solid var(--cp-line);
              text-align: left; background: transparent;
            }
            .cp-row-main, .cp-row-side { display: grid; gap: 4px; }
            .cp-row-main { min-width: 0; }
            .cp-row-card, .cp-row-meta { color: var(--cp-muted); font-size: 13px; }
            .cp-row-merchant { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-weight: 650; }
            .cp-row-side { justify-items: end; align-content: center; }
            .cp-row-amount { font-size: 18px; font-weight: 750; font-variant-numeric: tabular-nums; white-space: nowrap; }
            .cp-row-amount.is-cancellation { color: var(--cp-negative); }
            .cp-status { color: var(--cp-subtle); font-size: 13px; }
            .cp-status.is-unconfirmed { color: var(--cp-warning); }
            .cp-empty, .cp-error { padding: 48px 0; color: var(--cp-subtle); text-align: center; }
            .cp-error { color: var(--cp-danger); }
            .cp-panel { padding: 22px; border-radius: 20px; background: var(--cp-soft); }
            .cp-panel + .cp-panel, .cp-section + .cp-section { margin-top: 18px; }
            .cp-panel h2, .cp-section h2 { margin: 0 0 18px; font-size: 18px; }
            .cp-panel-head { display: flex; align-items: baseline; justify-content: space-between; gap: 16px; margin-bottom: 22px; }
            .cp-panel-head h2 { margin: 0; }
            .cp-hero-value { display: flex; align-items: baseline; flex-wrap: wrap; gap: 7px; }
            .cp-hero-value strong { font-size: clamp(30px, 8vw, 42px); line-height: 1.15; letter-spacing: -0.045em; font-variant-numeric: tabular-nums; }
            .cp-hero-value span { color: var(--cp-muted); font-weight: 650; }
            .cp-hero-value.is-negative strong { color: var(--cp-negative); }
            .cp-remaining { margin: 9px 0 0; color: var(--cp-subtle); }
            .cp-remaining strong { color: var(--cp-accent); }
            .cp-breakdown { margin: 22px 0 0; padding: 0; border-top: 1px solid var(--cp-line); }
            .cp-breakdown > div { display: flex; justify-content: space-between; gap: 16px; padding-top: 14px; }
            .cp-breakdown dt { color: var(--cp-subtle); }
            .cp-breakdown dd { margin: 0; font-weight: 700; text-align: right; font-variant-numeric: tabular-nums; }
            .cp-unconfirmed { color: var(--cp-warning); }
            .cp-policy { margin-top: 22px; border-top: 1px solid var(--cp-line); }
            .cp-policy summary {
              display: flex; align-items: center; justify-content: space-between; gap: 16px;
              padding-top: 17px; cursor: pointer; list-style: none; font-weight: 700;
            }
            .cp-policy summary::-webkit-details-marker { display: none; }
            .cp-policy-summary-meta { display: flex; align-items: center; gap: 9px; color: var(--cp-muted); font-size: 13px; font-weight: 600; }
            .cp-policy-chevron { display: inline-block; font-size: 18px; line-height: 1; transition: transform .18s ease; }
            .cp-policy[open] .cp-policy-chevron { transform: rotate(180deg); }
            .cp-policy-list { margin: 14px 0 0; padding: 0; list-style: none; border-top: 1px solid var(--cp-line); }
            .cp-policy-list li { display: grid; grid-template-columns: 12px minmax(0, 1fr); gap: 8px; padding: 13px 0; color: var(--cp-subtle); }
            .cp-policy-list li + li { border-top: 1px solid var(--cp-line); }
            .cp-policy-list li::before { content: "·"; color: var(--cp-muted); font-weight: 800; }
            .cp-metric-label { display: flex; justify-content: space-between; gap: 16px; color: var(--cp-subtle); }
            .cp-metric-label span { min-width: 0; }
            .cp-metric-label strong { color: var(--cp-text); font-variant-numeric: tabular-nums; }
            .cp-progress { height: 12px; margin-top: 12px; overflow: hidden; border-radius: 999px; background: var(--cp-track); }
            .cp-progress span { display: block; height: 100%; width: 0; border-radius: inherit; background: var(--cp-accent); transition: width .18s ease; }
            .cp-benefit-progress + .cp-benefit-progress { margin-top: 20px; }
            .cp-benefit + .cp-benefit { margin-top: 24px; padding-top: 24px; border-top: 1px solid var(--cp-line); }
            .cp-benefit-name { color: var(--cp-text); font-size: 18px; font-weight: 750; line-height: 1.35; }
            .cp-benefit-terms { margin: 10px 0 0; color: var(--cp-subtle); font-size: 14px; white-space: pre-line; }
            .cp-filter { display: flex; gap: 8px; margin: 0 0 20px; overflow-x: auto; }
            .cp-filter button {
              flex: 0 0 auto; padding: 9px 14px; border: 0; border-radius: 999px;
              color: var(--cp-subtle); background: var(--cp-soft);
            }
            .cp-filter button[aria-pressed="true"] { color: var(--cp-accent); background: var(--cp-accent-soft); font-weight: 700; }
            .cp-facts { padding: 10px 0 34px; }
            .cp-facts-card { color: var(--cp-subtle); }
            .cp-facts-amount { margin: 10px 0 18px; font-size: clamp(38px, 10vw, 54px); font-weight: 760; letter-spacing: -0.05em; }
            .cp-facts-grid { display: grid; grid-template-columns: 90px minmax(0, 1fr); gap: 12px 16px; }
            .cp-facts-grid dt { color: var(--cp-muted); }
            .cp-facts-grid dd { margin: 0; text-align: right; }
            .cp-section { padding: 28px 0; border-top: 1px solid var(--cp-line); }
            .cp-section.is-disabled { opacity: .34; pointer-events: none; }
            .cp-choice-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
            .cp-choice { position: relative; }
            .cp-choice input { position: absolute; opacity: 0; }
            .cp-choice label {
              display: block; padding: 15px; border-radius: 14px; text-align: center;
              background: var(--cp-soft); border: 2px solid transparent;
            }
            .cp-choice input:checked + label { color: var(--cp-accent); border-color: var(--cp-accent); background: var(--cp-accent-soft); font-weight: 700; }
            .cp-check-row {
              display: grid; grid-template-columns: auto minmax(0,1fr); gap: 13px; align-items: start;
              padding: 16px; border-radius: 16px; background: var(--cp-soft);
            }
            .cp-check-row + .cp-check-row { margin-top: 10px; }
            .cp-check-row input { width: 22px; height: 22px; margin: 1px 0 0; accent-color: var(--cp-accent); }
            .cp-check-row label { font-weight: 650; }
            .cp-check-progress { grid-column: 2; margin-top: 8px; }
            .cp-switch-row { display: flex; justify-content: space-between; gap: 18px; align-items: center; padding: 18px 0; }
            .cp-switch-row input { width: 24px; height: 24px; accent-color: var(--cp-accent); }
            .cp-field { display: grid; gap: 8px; margin-top: 18px; }
            .cp-field label { color: var(--cp-subtle); font-weight: 650; }
            .cp-field input, .cp-field textarea {
              width: 100%; min-height: 50px; padding: 13px 14px; border: 1px solid var(--cp-line);
              border-radius: 12px; background: var(--cp-soft); font-size: 16px;
            }
            .cp-field textarea { min-height: 100px; resize: vertical; }
            .cp-actions { display: grid; grid-template-columns: 1fr 1.35fr; gap: 10px; margin-top: 28px; }
            .cp-button { min-height: 52px; padding: 13px 18px; border: 0; border-radius: 15px; background: var(--cp-soft); font-weight: 700; }
            .cp-button-primary { color: #17191d; background: var(--cp-accent); }
            .cp-detail-back { padding: 8px 0; border: 0; background: transparent; color: var(--cp-subtle); }
            .cp-toast {
              position: fixed; left: 50%; bottom: 24px; translate: -50% 0; z-index: 20;
              padding: 12px 18px; border-radius: 999px; color: var(--cp-text); background: var(--cp-soft);
              box-shadow: 0 12px 30px color-mix(in srgb, #000 20%, transparent);
            }
            .cp-sr-only { position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px; overflow: hidden; clip: rect(0,0,0,0); white-space: nowrap; border: 0; }
            @media (max-width: 520px) {
              .cp-header { padding: 16px; align-items: stretch; flex-direction: column; gap: 10px; }
              .cp-card-select { width: 100%; max-width: none; }
              .cp-main { padding: 28px 18px 100px; }
              .cp-panel { padding: 18px; }
              .cp-panel-head { align-items: center; }
              #view-dashboard .cp-metric-label { display: grid; gap: 3px; }
              #view-dashboard .cp-metric-label strong { justify-self: start; }
              .cp-actions { grid-template-columns: 1fr 1.25fr; }
            }
            @media (prefers-reduced-motion: reduce) { .cp-progress span { transition: none; } }
          </style>
        </head>
        <body>
          <div class="cp-shell">
            <header class="cp-header">
              <div class="cp-brand"><strong>CherryPicker</strong><span id="context-label">미확인 거래</span></div>
              <select id="card-selector" class="cp-card-select" aria-label="카드 선택">
                <option value="">카드 선택</option>
              </select>
            </header>
            <nav class="cp-nav" aria-label="주요 메뉴">
              <button type="button" data-view="inbox" aria-current="page">미확인 거래</button>
              <button type="button" data-view="dashboard" hidden>대시보드</button>
              <button type="button" data-view="transactions" hidden>거래</button>
              <button type="button" data-view="settings" hidden>카드 설정</button>
            </nav>
            <main class="cp-main">
              <section id="view-inbox">
                <div class="cp-heading"><h1>확인할 거래가 <span class="cp-accent"><span id="inbox-count">0</span>건</span> 있어요</h1><p>모든 카드에서 아직 확인하지 않은 거래를 모았습니다.</p></div>
                <div id="inbox-list" class="cp-list"></div>
                <p id="inbox-empty" class="cp-empty" hidden>확인할 거래가 없습니다.</p>
              </section>

              <section id="view-dashboard" hidden>
                <div class="cp-heading"><h1 id="dashboard-title">카드 대시보드</h1><p id="dashboard-meta"></p></div>
                <div class="cp-period" data-period-control>
                  <button type="button" data-month-step="-1" aria-label="이전 달">‹</button>
                  <strong data-period-label></strong>
                  <button type="button" data-month-step="1" aria-label="다음 달">›</button>
                </div>
                <div class="cp-panel">
                  <div class="cp-panel-head"><h2>실적</h2></div>
                  <div id="performance-value" class="cp-hero-value"><strong>0원</strong><span>/ 0원</span></div>
                  <p id="remaining-value" class="cp-remaining">목표까지 <strong>0원</strong> 남았어요</p>
                  <div class="cp-progress" role="progressbar" id="performance-progress" aria-label="월 실적 진행도"><span></span></div>
                  <dl class="cp-breakdown">
                    <div><dt>실적 제외</dt><dd id="excluded-value">0원</dd></div>
                    <div><dt>미확인 거래</dt><dd id="unconfirmed-value" class="cp-unconfirmed">0건 · 0원</dd></div>
                  </dl>
                  <details class="cp-policy" id="performance-exclusion-policy">
                    <summary>
                      <span>실적 제외 항목</span>
                      <span class="cp-policy-summary-meta"><span id="performance-exclusion-count">0개</span><span class="cp-policy-chevron" aria-hidden="true">⌄</span></span>
                    </summary>
                    <ul class="cp-policy-list" id="performance-exclusion-list"></ul>
                  </details>
                </div>
                <div class="cp-panel">
                  <div class="cp-panel-head"><h2>혜택</h2></div>
                  <div id="dashboard-benefits"></div>
                  <details class="cp-policy" id="benefit-exclusion-policy">
                    <summary>
                      <span>혜택 제외 항목</span>
                      <span class="cp-policy-summary-meta"><span id="benefit-exclusion-count">0개</span><span class="cp-policy-chevron" aria-hidden="true">⌄</span></span>
                    </summary>
                    <ul class="cp-policy-list" id="benefit-exclusion-list"></ul>
                  </details>
                </div>
              </section>

              <section id="view-transactions" hidden>
                <div class="cp-heading"><h1 id="transactions-title">카드 거래</h1><p id="transactions-meta"></p></div>
                <div class="cp-period" data-period-control>
                  <button type="button" data-month-step="-1" aria-label="이전 달">‹</button>
                  <strong data-period-label></strong>
                  <button type="button" data-month-step="1" aria-label="다음 달">›</button>
                </div>
                <div class="cp-filter" aria-label="거래 필터">
                  <button type="button" data-filter="all" aria-pressed="true">전체</button>
                  <button type="button" data-filter="approval" aria-pressed="false">승인</button>
                  <button type="button" data-filter="cancellation" aria-pressed="false">취소</button>
                  <button type="button" data-filter="excluded" aria-pressed="false">집계 제외</button>
                </div>
                <div id="transaction-list" class="cp-list"></div>
                <p id="transaction-empty" class="cp-empty" hidden>조건에 맞는 거래가 없습니다.</p>
              </section>

              <section id="view-settings" hidden>
                <div class="cp-heading"><h1>카드 설정</h1><p>선택한 카드의 표시 정보와 실적 목표를 관리합니다.</p></div>
                <form id="settings-form">
                  <div class="cp-field"><label for="setting-name">카드 이름</label><input id="setting-name" required></div>
                  <div class="cp-field"><label for="setting-issuer">카드사</label><input id="setting-issuer" readonly></div>
                  <div class="cp-field"><label for="setting-last-four">끝 네 자리</label><input id="setting-last-four" inputmode="numeric" minlength="4" maxlength="4" required></div>
                  <div class="cp-field"><label for="setting-target">월 실적 목표</label><input id="setting-target" type="number" inputmode="numeric" min="1" required></div>
                  <div class="cp-actions"><span></span><button class="cp-button cp-button-primary" type="submit">저장</button></div>
                </form>
              </section>

              <section id="view-detail" hidden>
                <button id="detail-back" class="cp-detail-back" type="button">‹ 목록으로</button>
                <div class="cp-facts">
                  <div id="detail-card" class="cp-facts-card"></div>
                  <div id="detail-amount" class="cp-facts-amount"></div>
                  <dl class="cp-facts-grid">
                    <dt>사용처</dt><dd id="detail-merchant"></dd>
                    <dt>거래 종류</dt><dd id="detail-kind"></dd>
                    <dt>거래 일시</dt><dd id="detail-date"></dd>
                  </dl>
                </div>

                <div class="cp-switch-row">
                  <label for="aggregation-excluded">이 거래를 집계하지 않음</label>
                  <input id="aggregation-excluded" type="checkbox">
                </div>

                <div id="review-section" class="cp-section">
                  <h2>검토</h2>
                  <div class="cp-field"><label>실적</label></div>
                  <div class="cp-choice-grid">
                    <div class="cp-choice"><input id="performance-included" name="performance" type="radio" value="included"><label for="performance-included">인정</label></div>
                    <div class="cp-choice"><input id="performance-excluded" name="performance" type="radio" value="excluded"><label for="performance-excluded">제외</label></div>
                  </div>
                  <div class="cp-panel" style="margin-top:14px">
                    <div class="cp-metric-label"><span>이번 달 실적</span><strong id="detail-performance-value">0원 / 0원</strong></div>
                    <div class="cp-progress" id="detail-performance-progress" role="progressbar" aria-label="검토 반영 후 카드 실적"><span></span></div>
                  </div>
                  <div class="cp-field"><label>해당 혜택</label></div>
                  <div id="detail-benefits"></div>
                </div>

                <div class="cp-section">
                  <div class="cp-field"><label for="detail-memo">메모</label><textarea id="detail-memo"></textarea></div>
                  <details style="margin-top:20px"><summary>파싱 상태 보기</summary><p id="detail-parse-status" class="cp-status"></p></details>
                  <div class="cp-actions"><button id="detail-cancel" class="cp-button" type="button">취소</button><button id="detail-save" class="cp-button cp-button-primary" type="button">저장하고 확인</button></div>
                </div>
              </section>

              <p id="page-error" class="cp-error" hidden></p>
              <div class="cp-sr-only" aria-hidden="true">\#(diagnostics)</div>
            </main>
          </div>
          <div id="toast" class="cp-toast" role="status" aria-live="polite" hidden>저장했습니다</div>

          <script>
            (() => {
              const $ = selector => document.querySelector(selector);
              const $$ = selector => Array.from(document.querySelectorAll(selector));
              const won = value => value == null ? '금액 미상' : `${Number(value).toLocaleString('ko-KR')}원`;
              const kindLabel = value => value === 'approval' ? '승인' : value === 'cancellation' ? '취소' : '종류 미상';
              const dateLabel = value => value ? new Intl.DateTimeFormat('ko-KR', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'Asia/Seoul' }).format(new Date(value)) : '일시 미상';
              const monthKeyForDate = value => {
                const parts = new Intl.DateTimeFormat('en-US', { timeZone: 'Asia/Seoul', year: 'numeric', month: '2-digit' }).formatToParts(new Date(value));
                const part = type => parts.find(value => value.type === type)?.value;
                return `${part('year')}-${part('month')}`;
              };
              const currentMonth = monthKeyForDate(new Date());
              const state = { cards: [], selectedCardId: null, view: 'inbox', filter: 'all', month: currentMonth, activeTransaction: null, dashboard: null, returnView: 'inbox' };
              const card = () => state.cards.find(value => value.id === state.selectedCardId);

              function shiftedMonth(value, offset) {
                const [year, month] = value.split('-').map(Number);
                const shifted = new Date(Date.UTC(year, month - 1 + offset, 1));
                return `${shifted.getUTCFullYear()}-${String(shifted.getUTCMonth() + 1).padStart(2, '0')}`;
              }

              function monthLabel(value) {
                const [year, month] = value.split('-').map(Number);
                return `${year}년 ${month}월`;
              }

              function syncPeriodControls() {
                $$('[data-period-label]').forEach(value => { value.textContent = monthLabel(state.month); });
                $$('[data-month-step="1"]').forEach(value => { value.disabled = state.month >= currentMonth; });
              }

              function renderPolicyList(type, items) {
                $(`#${type}-exclusion-count`).textContent = `${items.length}개`;
                const list = $(`#${type}-exclusion-list`);
                list.replaceChildren(...items.map(item => {
                  const row = document.createElement('li'); row.textContent = item; return row;
                }));
                $(`#${type}-exclusion-policy`).hidden = items.length === 0;
              }

              async function api(path, options = {}) {
                const headers = new Headers(options.headers || {});
                if (options.body) {
                  headers.set('Content-Type', 'application/json');
                  headers.set('X-CherryPicker-CSRF', 'same-origin');
                }
                const response = await fetch(path, { ...options, headers });
                if (!response.ok) throw new Error(`요청을 처리하지 못했습니다 (${response.status})`);
                return response.json();
              }

              function showError(error) {
                $('#page-error').textContent = error instanceof Error ? error.message : '요청을 처리하지 못했습니다.';
                $('#page-error').hidden = false;
              }

              function clearError() { $('#page-error').hidden = true; }

              function setCurrentTab(view) {
                $$('.cp-nav button').forEach(button => {
                  if (button.dataset.view === view) button.setAttribute('aria-current', 'page');
                  else button.removeAttribute('aria-current');
                });
              }

              function setCardNavigationVisible(visible) {
                $$('.cp-nav button').forEach(button => {
                  if (button.dataset.view !== 'inbox') button.hidden = !visible;
                });
              }

              async function showView(view) {
                clearError();
                if (view === 'inbox') {
                  state.selectedCardId = null;
                  $('#card-selector').value = '';
                  setCardNavigationVisible(false);
                }
                state.view = view;
                $$('[id^="view-"]').forEach(section => { section.hidden = section.id !== `view-${view}`; });
                setCurrentTab(view === 'detail' ? state.returnView : view);
                const labels = { inbox: '미확인 거래', dashboard: '대시보드', transactions: '거래', settings: '카드 설정', detail: '거래 검토' };
                $('#context-label').textContent = labels[view];
                if (view === 'inbox') await loadInbox();
                if (view === 'dashboard') await loadDashboard();
                if (view === 'transactions') await loadTransactions();
                if (view === 'settings') renderSettings();
              }

              function transactionRow(transaction, includeCard) {
                const button = document.createElement('button');
                button.type = 'button';
                button.className = 'cp-row';
                button.setAttribute('aria-label', `${transaction.cardDisplayName}, ${transaction.merchant || '확인 필요'}, ${won(transaction.amount)}, ${kindLabel(transaction.kind)}, 상세 검토`);
                const main = document.createElement('span'); main.className = 'cp-row-main';
                if (includeCard) {
                  const cardText = document.createElement('span'); cardText.className = 'cp-row-card'; cardText.textContent = `${transaction.cardDisplayName} · ${transaction.cardLastFour}`; main.append(cardText);
                }
                const merchant = document.createElement('span'); merchant.className = 'cp-row-merchant'; merchant.textContent = transaction.merchant || '확인 필요';
                const meta = document.createElement('span'); meta.className = 'cp-row-meta'; meta.textContent = `${kindLabel(transaction.kind)} · ${dateLabel(transaction.occurredAt)}`;
                main.append(merchant, meta);
                const side = document.createElement('span'); side.className = 'cp-row-side';
                const amount = document.createElement('span'); amount.className = `cp-row-amount${transaction.kind === 'cancellation' ? ' is-cancellation' : ''}`; amount.textContent = `${transaction.kind === 'cancellation' ? '−' : ''}${won(transaction.amount)}`;
                const status = document.createElement('span'); status.className = `cp-status${transaction.reviewStatus === 'unreviewed' ? ' is-unconfirmed' : ''}`; status.textContent = transaction.aggregationExcluded ? '집계 제외' : transaction.reviewStatus === 'unreviewed' ? '미확인' : '확인';
                side.append(amount, status); button.append(main, side);
                button.addEventListener('click', () => openDetail(transaction.id));
                return button;
              }

              async function loadCards() {
                const data = await api('/api/v1/cards');
                state.cards = data.cards;
                const selector = $('#card-selector');
                selector.replaceChildren(new Option('카드 선택', ''));
                data.cards.forEach(value => selector.add(new Option(`${value.displayName} · ${value.lastFour}`, value.id)));
              }

              async function loadInbox() {
                const data = await api('/api/v1/transactions?scope=unreviewed');
                $('#inbox-count').textContent = data.transactions.length;
                const list = $('#inbox-list'); list.replaceChildren(...data.transactions.map(value => transactionRow(value, true)));
                $('#inbox-empty').hidden = data.transactions.length !== 0;
              }

              function setProgress(element, current, maximum) {
                const percent = maximum > 0 ? Math.max(0, Math.min(100, current / maximum * 100)) : 0;
                element.setAttribute('aria-valuemin', String(Math.min(0, current))); element.setAttribute('aria-valuemax', String(maximum)); element.setAttribute('aria-valuenow', String(current));
                element.querySelector('span').style.width = `${percent}%`;
              }

              async function loadDashboard() {
                if (!state.selectedCardId) return showView('inbox');
                syncPeriodControls();
                const data = await api(`/api/v1/cards/${state.selectedCardId}/dashboard?month=${state.month}`);
                state.dashboard = data.dashboard;
                const selected = card();
                $('#dashboard-title').textContent = selected.displayName;
                $('#dashboard-meta').textContent = `${selected.issuerCode} · ${selected.lastFour}`;
                const performance = data.dashboard.performance;
                const performanceValue = $('#performance-value');
                performanceValue.classList.toggle('is-negative', performance.currentAmount < 0);
                performanceValue.replaceChildren();
                const current = document.createElement('strong'); current.textContent = won(performance.currentAmount);
                const target = document.createElement('span'); target.textContent = `/ ${won(performance.targetAmount)}`;
                performanceValue.append(current, target);
                $('#remaining-value').replaceChildren();
                if (performance.remainingAmount > 0) {
                  $('#remaining-value').append('목표까지 ');
                  const remaining = document.createElement('strong'); remaining.textContent = won(performance.remainingAmount);
                  $('#remaining-value').append(remaining, ' 남았어요');
                } else {
                  const achieved = document.createElement('strong'); achieved.textContent = '목표를 달성했어요';
                  $('#remaining-value').append(achieved);
                }
                setProgress($('#performance-progress'), performance.currentAmount, performance.targetAmount);
                $('#excluded-value').textContent = won(performance.excludedAmount);
                $('#unconfirmed-value').textContent = `${performance.unconfirmedCount}건 · ${won(performance.unconfirmedAmount)}`;
                const benefits = $('#dashboard-benefits'); benefits.replaceChildren();
                data.dashboard.benefits.forEach(value => {
                  const wrap = document.createElement('div'); wrap.className = 'cp-benefit';
                  const label = document.createElement('div'); label.className = 'cp-metric-label';
                  const name = document.createElement('span'); name.className = 'cp-benefit-name'; name.textContent = value.label;
                  const amount = document.createElement('strong'); amount.textContent = `${won(value.receivedAmount)} / ${won(value.maximumAmount)}`;
                  label.append(name, amount);
                  const definition = selected.benefits.find(benefit => benefit.id === value.id);
                  const terms = document.createElement('p'); terms.className = 'cp-benefit-terms'; terms.textContent = definition ? benefitTerms(definition) : '';
                  const progress = document.createElement('div'); progress.className = 'cp-progress'; progress.setAttribute('role', 'progressbar'); progress.setAttribute('aria-label', value.label); progress.append(document.createElement('span'));
                  setProgress(progress, value.receivedAmount, value.maximumAmount); wrap.append(label, progress, terms); benefits.append(wrap);
                });
                if (data.dashboard.benefits.length === 0) {
                  const empty = document.createElement('p'); empty.className = 'cp-empty'; empty.textContent = '등록된 혜택이 없습니다.'; benefits.append(empty);
                }
                renderPolicyList('performance', selected.performanceExclusions || []);
                renderPolicyList('benefit', selected.benefitExclusions || []);
              }

              async function loadTransactions() {
                if (!state.selectedCardId) return showView('inbox');
                syncPeriodControls();
                const selected = card(); $('#transactions-meta').textContent = `${selected.displayName} · ${selected.lastFour}`;
                const data = await api(`/api/v1/cards/${state.selectedCardId}/transactions?filter=${state.filter}&month=${state.month}`);
                $('#transactions-title').textContent = `${Number(state.month.slice(5))}월 거래 ${data.transactions.length}건`;
                const list = $('#transaction-list'); list.replaceChildren(...data.transactions.map(value => transactionRow(value, false)));
                $('#transaction-empty').hidden = data.transactions.length !== 0;
              }

              function renderSettings() {
                const selected = card(); if (!selected) return;
                $('#setting-name').value = selected.displayName; $('#setting-issuer').value = selected.issuerCode;
                $('#setting-last-four').value = selected.lastFour; $('#setting-target').value = selected.performanceTargetAmount;
              }

              function benefitContribution(transaction, benefit) {
                if (transaction.amount == null) return 0;
                const sign = transaction.kind === 'cancellation' ? -1 : 1;
                return sign * Math.trunc(transaction.amount * benefit.rateBasisPoints / 10000);
              }

              function benefitTerms(benefit) {
                const values = [`조건: 건당 ${won(benefit.minimumTransactionAmount)} 이상`];
                benefit.exclusionNotes.forEach(note => values.push(`제외: ${note}`));
                return values.join('\n');
              }

              function updateReviewPreview() {
                const transaction = state.activeTransaction, dashboard = state.dashboard, selectedCard = card();
                if (!transaction || !dashboard || !selectedCard) return;
                const excluded = $('#aggregation-excluded').checked;
                $('#review-section').classList.toggle('is-disabled', excluded);
                $$('#review-section input').forEach(input => { input.disabled = excluded; });
                const chosenPerformance = document.querySelector('input[name="performance"]:checked')?.value;
                const sign = transaction.kind === 'cancellation' ? -1 : 1;
                let performance = dashboard.performance.currentAmount;
                if (transaction.reviewStatus === 'reviewed' && !transaction.aggregationExcluded && transaction.performance === 'included' && transaction.amount != null) performance -= sign * transaction.amount;
                if (!excluded && chosenPerformance === 'included' && transaction.amount != null) performance += sign * transaction.amount;
                $('#detail-performance-value').textContent = `${won(performance)} / ${won(dashboard.performance.targetAmount)}`;
                setProgress($('#detail-performance-progress'), performance, dashboard.performance.targetAmount);

                selectedCard.benefits.forEach(benefit => {
                  const checkbox = document.getElementById(`benefit-${benefit.id}`);
                  const progressWrap = document.getElementById(`benefit-progress-${benefit.id}`);
                  let received = dashboard.benefits.find(value => value.id === benefit.id)?.calculationAmount || 0;
                  if (transaction.reviewStatus === 'reviewed' && !transaction.aggregationExcluded && transaction.benefitIds.includes(benefit.id)) received -= benefitContribution(transaction, benefit);
                  if (!excluded && checkbox.checked) received += benefitContribution(transaction, benefit);
                  received = Math.max(0, Math.min(benefit.maximumAmount, received));
                  progressWrap.hidden = !checkbox.checked || excluded;
                  progressWrap.querySelector('strong').textContent = `${won(received)} / ${won(benefit.maximumAmount)}`;
                  setProgress(progressWrap.querySelector('.cp-progress'), received, benefit.maximumAmount);
                });
              }

              async function openDetail(id) {
                clearError();
                state.returnView = state.view;
                const data = await api(`/api/v1/transactions/${id}`); state.activeTransaction = data.transaction;
                state.selectedCardId = data.transaction.cardId; $('#card-selector').value = state.selectedCardId; setCardNavigationVisible(true);
                const transaction = data.transaction, selectedCard = card();
                state.month = monthKeyForDate(transaction.occurredAt);
                const dashboardData = await api(`/api/v1/cards/${state.selectedCardId}/dashboard?month=${state.month}`); state.dashboard = dashboardData.dashboard;
                $('#detail-card').textContent = `${transaction.cardDisplayName} · ${transaction.cardLastFour}`;
                $('#detail-amount').textContent = won(transaction.amount); $('#detail-merchant').textContent = transaction.merchant || '확인 필요';
                $('#detail-kind').textContent = kindLabel(transaction.kind); $('#detail-date').textContent = dateLabel(transaction.occurredAt);
                $('#detail-parse-status').textContent = transaction.parseStatus === 'parsed' ? '문자를 정상적으로 분류했습니다.' : '문자 분류를 확인해야 합니다.';
                $('#aggregation-excluded').checked = transaction.aggregationExcluded;
                $('#performance-included').checked = transaction.performance === 'included'; $('#performance-excluded').checked = transaction.performance === 'excluded';
                $('#detail-memo').value = transaction.memo || '';
                const benefits = $('#detail-benefits'); benefits.replaceChildren();
                selectedCard.benefits.forEach(benefit => {
                  const row = document.createElement('div'); row.className = 'cp-check-row';
                  const checkbox = document.createElement('input'); checkbox.type = 'checkbox'; checkbox.id = `benefit-${benefit.id}`; checkbox.value = benefit.id; checkbox.checked = transaction.benefitIds.includes(benefit.id);
                  const label = document.createElement('label'); label.htmlFor = checkbox.id; label.textContent = benefit.label;
                  const wrap = document.createElement('div'); wrap.className = 'cp-check-progress'; wrap.id = `benefit-progress-${benefit.id}`;
                  const metric = document.createElement('div'); metric.className = 'cp-metric-label'; const caption = document.createElement('span'); caption.textContent = '받은 혜택'; const amount = document.createElement('strong'); metric.append(caption, amount);
                  const progress = document.createElement('div'); progress.className = 'cp-progress'; progress.setAttribute('role', 'progressbar'); progress.setAttribute('aria-label', benefit.label); progress.append(document.createElement('span'));
                  wrap.append(metric, progress); row.append(checkbox, label, wrap); benefits.append(row); checkbox.addEventListener('change', updateReviewPreview);
                });
                await showView('detail'); updateReviewPreview();
              }

              function toast(message) { const value = $('#toast'); value.textContent = message; value.hidden = false; window.setTimeout(() => { value.hidden = true; }, 1800); }

              async function saveReview() {
                const transaction = state.activeTransaction; if (!transaction) return;
                const aggregationExcluded = $('#aggregation-excluded').checked;
                const performance = aggregationExcluded ? null : document.querySelector('input[name="performance"]:checked')?.value || null;
                if (!aggregationExcluded && !performance) { showError(new Error('실적 인정 또는 제외를 선택해 주세요.')); return; }
                const benefitIds = aggregationExcluded ? [] : $$('#detail-benefits input:checked').map(input => input.value);
                await api(`/api/v1/transactions/${transaction.id}`, { method: 'PATCH', body: JSON.stringify({ review: { performance, benefitIds, memo: $('#detail-memo').value }, aggregationExcluded }) });
                toast('저장했습니다'); await showView(state.returnView);
              }

              $$('.cp-nav button').forEach(button => button.addEventListener('click', async () => {
                if (button.dataset.view === 'inbox') { state.selectedCardId = null; $('#card-selector').value = ''; setCardNavigationVisible(false); }
                await showView(button.dataset.view);
              }));
              $('#card-selector').addEventListener('change', async event => {
                state.selectedCardId = event.target.value || null; state.month = currentMonth; setCardNavigationVisible(Boolean(state.selectedCardId));
                await showView(state.selectedCardId ? 'dashboard' : 'inbox');
              });
              $$('[data-month-step]').forEach(button => button.addEventListener('click', async () => {
                const next = shiftedMonth(state.month, Number(button.dataset.monthStep));
                state.month = next > currentMonth ? currentMonth : next;
                if (state.view === 'dashboard') await loadDashboard();
                if (state.view === 'transactions') await loadTransactions();
              }));
              $$('.cp-filter button').forEach(button => button.addEventListener('click', async () => {
                state.filter = button.dataset.filter; $$('.cp-filter button').forEach(value => value.setAttribute('aria-pressed', String(value === button))); await loadTransactions();
              }));
              $('#settings-form').addEventListener('submit', async event => {
                event.preventDefault();
                const body = { displayName: $('#setting-name').value, lastFour: $('#setting-last-four').value, performanceTargetAmount: Number($('#setting-target').value) };
                const data = await api(`/api/v1/cards/${state.selectedCardId}`, { method: 'PUT', body: JSON.stringify(body) });
                state.cards = state.cards.map(value => value.id === data.card.id ? data.card : value); await loadCards(); $('#card-selector').value = state.selectedCardId; toast('카드 설정을 저장했습니다');
              });
              $('#aggregation-excluded').addEventListener('change', updateReviewPreview);
              $$('input[name="performance"]').forEach(input => input.addEventListener('change', updateReviewPreview));
              $('#detail-save').addEventListener('click', () => saveReview().catch(showError));
              $('#detail-cancel').addEventListener('click', () => showView(state.returnView).catch(showError));
              $('#detail-back').addEventListener('click', () => showView(state.returnView).catch(showError));

              loadCards().then(() => { setCardNavigationVisible(false); return showView('inbox'); }).catch(showError);
            })();
          </script>
        </body>
        </html>
        """#
    }

    private static func htmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
