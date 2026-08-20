enum CandidateCardSimulationWeb {
    static let styles = #"""
    #view-simulation {
      --cp-sim-accent-text: light-dark(#9e2149, #ff9bb0);
      --cp-sim-muted: light-dark(#5f6b7a, #b0b8c1);
    }
    .cp-sim-empty {
      display: grid;
      place-items: center;
      min-height: 360px;
      padding: 36px 20px;
      text-align: center;
    }
    .cp-sim-empty h1 { margin: 0; font-size: clamp(28px, 7vw, 38px); letter-spacing: -.045em; }
    .cp-sim-empty p { max-width: 430px; margin: 12px 0 0; color: var(--cp-subtle); }
    .cp-sim-loading { padding: 48px 0; color: var(--cp-subtle); text-align: center; }
    .cp-sim-load-error {
      display: grid;
      justify-items: center;
      gap: 14px;
      min-height: 260px;
      padding: 48px 20px;
      text-align: center;
    }
    .cp-sim-load-error p { max-width: 430px; margin: 0; color: var(--cp-danger); }
    .cp-sim-load-error button {
      min-height: 46px;
      padding: 10px 16px;
      border: 0;
      border-radius: 12px;
      background: var(--cp-soft);
      font-weight: 700;
    }
    .cp-sim-steps {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      margin: -12px 0 30px;
      border-bottom: 1px solid var(--cp-line);
    }
    .cp-sim-steps button {
      min-width: 0;
      min-height: 54px;
      padding: 10px 5px;
      border: 0;
      border-bottom: 3px solid transparent;
      color: var(--cp-sim-muted);
      background: transparent;
      font-size: 13px;
      font-weight: 700;
    }
    .cp-sim-steps button span {
      display: inline-grid;
      place-items: center;
      width: 21px;
      height: 21px;
      margin-right: 4px;
      border-radius: 50%;
      color: var(--cp-subtle);
      background: var(--cp-soft);
      font-size: 11px;
    }
    .cp-sim-steps button[aria-current="step"] { color: var(--cp-sim-accent-text); border-bottom-color: var(--cp-accent); }
    .cp-sim-steps button[aria-current="step"] span { color: var(--cp-sim-accent-text); background: var(--cp-accent-soft); }
    .cp-sim-steps button:disabled { cursor: not-allowed; opacity: .42; }
    .cp-sim-heading { margin-bottom: 26px; }
    .cp-sim-heading-row { display: flex; align-items: flex-start; justify-content: space-between; gap: 18px; }
    .cp-sim-heading p { margin: 0 0 6px; color: var(--cp-sim-accent-text); font-size: 13px; font-weight: 750; }
    .cp-sim-heading h1 { margin: 0; font-size: clamp(28px, 6vw, 38px); line-height: 1.2; letter-spacing: -.045em; }
    .cp-sim-state {
      flex: 0 0 auto;
      padding: 6px 9px;
      border-radius: 999px;
      color: var(--cp-warning);
      background: color-mix(in srgb, var(--cp-warning) 13%, transparent);
      font-size: 12px;
      font-weight: 750;
      white-space: nowrap;
    }
    .cp-sim-state.is-confirmed { color: light-dark(#0b654a, #75ddb8); background: light-dark(#e8f6f0, #17352d); }
    .cp-sim-facts {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      margin: 0;
      overflow: hidden;
      border: 1px solid var(--cp-line);
      border-radius: 16px;
    }
    .cp-sim-facts > div { min-width: 0; padding: 16px; }
    .cp-sim-facts > div + div { border-left: 1px solid var(--cp-line); }
    .cp-sim-facts dt { color: var(--cp-sim-muted); font-size: 12px; }
    .cp-sim-facts dd { margin: 4px 0 0; font-size: 17px; font-weight: 750; font-variant-numeric: tabular-nums; }
    .cp-sim-facts small { display: block; margin-top: 2px; color: var(--cp-sim-muted); font-size: 11px; }
    .cp-sim-policy-section { margin-top: 30px; }
    .cp-sim-policy-section h2 { margin: 0 0 12px; font-size: 19px; }
    .cp-sim-policy-table { width: 100%; border-collapse: collapse; }
    .cp-sim-policy-table th,
    .cp-sim-policy-table td { padding: 12px 4px; border-bottom: 1px solid var(--cp-line); text-align: left; }
    .cp-sim-policy-table th { color: var(--cp-sim-muted); font-size: 12px; font-weight: 650; }
    .cp-sim-policy-table th:last-child,
    .cp-sim-policy-table td:last-child { text-align: right; font-variant-numeric: tabular-nums; }
    .cp-sim-policy-table td:last-child { font-weight: 750; }
    .cp-sim-grace {
      display: flex;
      justify-content: space-between;
      gap: 16px;
      margin: 14px 0 0;
      padding: 13px 14px;
      border-radius: 13px;
      color: light-dark(#0b654a, #75ddb8);
      background: light-dark(#e8f6f0, #17352d);
      font-size: 13px;
    }
    .cp-sim-grace span { text-align: right; }
    .cp-sim-benefits { margin: 0; padding: 0; border-top: 1px solid var(--cp-line); list-style: none; }
    .cp-sim-benefits li { display: grid; gap: 2px; padding: 14px 4px; border-bottom: 1px solid var(--cp-line); }
    .cp-sim-benefits span { color: var(--cp-sim-muted); font-size: 12px; }
    .cp-sim-benefit-rules { margin-top: 8px; }
    .cp-sim-benefit-rules summary { min-height: 42px; padding: 9px 0; color: var(--cp-subtle); cursor: pointer; font-size: 12px; font-weight: 700; }
    .cp-sim-benefit-rules dl,
    .cp-sim-policy-rules { margin: 0; padding: 12px 14px; border-radius: 12px; background: var(--cp-soft); }
    .cp-sim-benefit-rules dl > div,
    .cp-sim-policy-rules > div { display: grid; grid-template-columns: 104px minmax(0, 1fr); gap: 12px; }
    .cp-sim-benefit-rules dl > div + div,
    .cp-sim-policy-rules > div + div { margin-top: 7px; }
    .cp-sim-benefit-rules dt,
    .cp-sim-policy-rules dt { color: var(--cp-sim-muted); font-size: 12px; }
    .cp-sim-benefit-rules dd,
    .cp-sim-policy-rules dd { margin: 0; overflow-wrap: anywhere; text-align: right; font-size: 12px; }
    .cp-sim-policy-rules { margin-bottom: 10px; }
    .cp-sim-policy-note { margin: 13px 0 0; color: var(--cp-subtle); font-size: 13px; }
    .cp-sim-details { border-top: 1px solid var(--cp-line); }
    .cp-sim-policy-section + .cp-sim-details { margin-top: 28px; }
    .cp-sim-details summary,
    .cp-sim-calculation summary,
    .cp-sim-row-details summary {
      min-height: 46px;
      padding: 12px 2px;
      cursor: pointer;
      color: var(--cp-subtle);
      font-weight: 700;
    }
    .cp-sim-details dl { margin: 0 0 14px; padding: 13px 14px; border-radius: 12px; background: var(--cp-soft); }
    .cp-sim-details dl div { display: grid; grid-template-columns: 110px minmax(0, 1fr); gap: 14px; }
    .cp-sim-details dl div + div { margin-top: 8px; }
    .cp-sim-details dt { color: var(--cp-sim-muted); }
    .cp-sim-details dd { margin: 0; text-align: right; overflow-wrap: anywhere; }
    .cp-sim-exclusions { margin: 0 0 14px; padding: 13px 14px; border-radius: 12px; background: var(--cp-soft); }
    .cp-sim-exclusions h3 { margin: 0; font-size: 14px; }
    .cp-sim-exclusions ul { margin: 8px 0 0; padding-left: 20px; color: var(--cp-subtle); }
    .cp-sim-exclusions li + li { margin-top: 6px; }
    .cp-sim-preservation { margin: 18px 0 0; color: var(--cp-subtle); font-size: 13px; }
    .cp-sim-preservation strong { color: var(--cp-text); }
    .cp-sim-primary {
      width: 100%;
      min-height: 52px;
      margin-top: 24px;
      padding: 13px 18px;
      border: 0;
      border-radius: 15px;
      color: #17191d;
      background: var(--cp-accent);
      font-weight: 750;
    }
    .cp-sim-question-list { display: grid; gap: 26px; }
    .cp-sim-question-card { border-bottom: 1px solid var(--cp-line); padding-bottom: 26px; }
    .cp-sim-question-transaction {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 18px;
      padding: 18px 0;
      border-top: 1px solid var(--cp-line);
      border-bottom: 1px solid var(--cp-line);
    }
    .cp-sim-question-transaction > div { min-width: 0; }
    .cp-sim-question-transaction span { color: var(--cp-sim-muted); font-size: 12px; }
    .cp-sim-question-transaction h2 { margin: 3px 0 0; overflow-wrap: anywhere; font-size: 19px; }
    .cp-sim-question-transaction > strong { font-size: 20px; font-variant-numeric: tabular-nums; white-space: nowrap; }
    .cp-sim-question-fieldset { margin: 24px 0 0; padding: 0; border: 0; }
    .cp-sim-question-fieldset legend { font-size: 18px; font-weight: 750; }
    .cp-sim-question-options { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 10px; margin-top: 15px; }
    .cp-sim-question-options label {
      display: flex;
      align-items: center;
      gap: 9px;
      min-height: 52px;
      padding: 13px 14px;
      border: 1px solid var(--cp-line);
      border-radius: 13px;
      background: var(--cp-soft);
      cursor: pointer;
      font-weight: 650;
    }
    .cp-sim-question-options input { width: 20px; height: 20px; margin: 0; accent-color: var(--cp-accent); }
    .cp-sim-question-result {
      display: flex;
      justify-content: space-between;
      gap: 16px;
      margin: 18px 0 0;
      padding: 14px;
      border-radius: 13px;
      color: var(--cp-warning);
      background: color-mix(in srgb, var(--cp-warning) 13%, transparent);
      font-size: 13px;
    }
    .cp-sim-question-result.is-resolved { color: light-dark(#0b654a, #75ddb8); background: light-dark(#e8f6f0, #17352d); }
    .cp-sim-question-result span { text-align: right; }
    .cp-sim-assumption { display: grid; gap: 7px; margin-bottom: 16px; }
    .cp-sim-assumption label { color: var(--cp-subtle); font-size: 13px; font-weight: 700; }
    .cp-sim-assumption select {
      width: 100%;
      min-height: 50px;
      padding: 11px 38px 11px 13px;
      border: 1px solid var(--cp-line);
      border-radius: 13px;
      background: var(--cp-soft);
      font-size: 16px;
    }
    .cp-sim-summary {
      position: sticky;
      top: 92px;
      z-index: 5;
      margin: 0 -8px;
      padding: 14px 16px;
      border: 1px solid var(--cp-line);
      border-radius: 16px;
      background: color-mix(in srgb, var(--cp-surface) 96%, transparent);
      box-shadow: 0 8px 24px color-mix(in srgb, #141f2f 10%, transparent);
      backdrop-filter: blur(14px);
    }
    .cp-sim-summary-values { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); }
    .cp-sim-summary-values > div { min-width: 0; }
    .cp-sim-summary-values > div + div { padding-left: 14px; border-left: 1px solid var(--cp-line); }
    .cp-sim-summary-values span { display: block; color: var(--cp-sim-muted); font-size: 11px; }
    .cp-sim-summary-values strong {
      display: block;
      margin-top: 2px;
      overflow-wrap: anywhere;
      font-size: 19px;
      font-variant-numeric: tabular-nums;
      letter-spacing: -.025em;
    }
    .cp-sim-summary-values > div:first-child strong,
    .cp-sim-summary-values > div:nth-child(2) strong { color: var(--cp-sim-accent-text); }
    .cp-sim-summary > p { margin: 7px 0 0; color: var(--cp-sim-muted); font-size: 11px; }
    .cp-sim-summary .cp-sim-range-note { color: var(--cp-warning); font-weight: 650; }
    .cp-sim-calculation { margin-top: 12px; border-bottom: 1px solid var(--cp-line); }
    .cp-sim-calculation-body { padding: 4px 14px 16px; border-radius: 14px; background: var(--cp-soft); }
    .cp-sim-calculation-body dl { margin: 0; }
    .cp-sim-calculation-body dl > div { display: grid; grid-template-columns: 130px minmax(0, 1fr); gap: 16px; padding: 8px 0; }
    .cp-sim-calculation-body dt { color: var(--cp-sim-muted); }
    .cp-sim-calculation-body dd { margin: 0; text-align: right; font-weight: 650; font-variant-numeric: tabular-nums; }
    .cp-sim-progress { height: 10px; margin-top: 8px; overflow: hidden; border-radius: 999px; background: var(--cp-track); }
    .cp-sim-progress span { display: block; width: 0; height: 100%; border-radius: inherit; background: var(--cp-accent); transition: width .18s ease; }
    .cp-sim-limit-list { margin-top: 14px; }
    .cp-sim-limit-list > div { display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: 14px; padding: 7px 0; }
    .cp-sim-limit-list dt { color: var(--cp-sim-muted); }
    .cp-sim-limit-list dd { min-width: 0; margin: 0; overflow-wrap: anywhere; text-align: right; font-weight: 650; }
    .cp-sim-annual-fee {
      display: flex;
      justify-content: space-between;
      gap: 16px;
      margin: 13px 0 0;
      padding-top: 12px;
      border-top: 1px solid var(--cp-line);
      color: var(--cp-sim-muted);
      font-size: 12px;
    }
    .cp-sim-annual-fee strong { color: var(--cp-text); font-variant-numeric: tabular-nums; }
    .cp-sim-transaction-section { margin-top: 30px; }
    .cp-sim-transaction-head { display: flex; align-items: flex-end; justify-content: space-between; gap: 18px; }
    .cp-sim-transaction-head h2 { margin: 0; font-size: 20px; }
    .cp-sim-transaction-head p { margin: 3px 0 0; color: var(--cp-sim-muted); font-size: 12px; }
    .cp-sim-selection-actions { display: flex; gap: 6px; }
    .cp-sim-selection-actions button,
    .cp-sim-question-review {
      min-height: 42px;
      padding: 8px 11px;
      border: 0;
      border-radius: 11px;
      color: var(--cp-subtle);
      background: var(--cp-soft);
      font-size: 13px;
      font-weight: 700;
    }
    .cp-sim-transactions { margin: 12px 0 0; padding: 0; border-top: 1px solid var(--cp-line); border-bottom: 1px solid var(--cp-line); list-style: none; }
    .cp-sim-transaction { border-bottom: 1px solid var(--cp-line); }
    .cp-sim-transaction:last-child { border-bottom: 0; }
    .cp-sim-transaction[data-selected="true"] {
      background: color-mix(in srgb, var(--cp-accent-soft) 28%, var(--cp-surface));
      box-shadow: inset 3px 0 0 var(--cp-accent);
    }
    .cp-sim-transaction-label {
      display: grid;
      grid-template-columns: auto minmax(0, 1fr) auto;
      gap: 12px;
      align-items: center;
      min-height: 76px;
      padding: 13px 4px;
      cursor: pointer;
    }
    .cp-sim-transaction-check { width: 22px; height: 22px; margin: 0; accent-color: var(--cp-accent); }
    .cp-sim-row-copy { min-width: 0; }
    .cp-sim-row-merchant { display: block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-weight: 750; }
    .cp-sim-row-date { display: block; margin-top: 1px; color: var(--cp-sim-muted); font-size: 11px; }
    .cp-sim-row-status { display: block; margin-top: 3px; overflow: hidden; color: var(--cp-subtle); font-size: 12px; text-overflow: ellipsis; white-space: nowrap; }
    .cp-sim-row-side { min-width: 122px; text-align: right; }
    .cp-sim-row-amount { display: block; font-size: 16px; font-variant-numeric: tabular-nums; white-space: nowrap; }
    .cp-sim-row-benefit { display: block; margin-top: 2px; color: light-dark(#0b654a, #75ddb8); font-size: 12px; font-weight: 750; font-variant-numeric: tabular-nums; }
    .cp-sim-row-benefit.is-none { color: var(--cp-sim-muted); }
    .cp-sim-row-benefit.is-question { color: var(--cp-warning); }
    .cp-sim-row-actions { display: flex; justify-content: flex-end; margin: -4px 4px 8px 36px; }
    .cp-sim-question-review { color: var(--cp-warning); background: color-mix(in srgb, var(--cp-warning) 13%, transparent); }
    .cp-sim-row-details { margin: 0 4px 0 36px; border-top: 1px solid var(--cp-line); }
    .cp-sim-row-details summary { font-size: 12px; }
    .cp-sim-evidence { margin: 0 0 12px; }
    .cp-sim-evidence > div { display: grid; grid-template-columns: 72px minmax(0, 1fr); gap: 12px; padding: 5px 0; }
    .cp-sim-evidence dt { color: var(--cp-sim-muted); font-size: 12px; }
    .cp-sim-evidence dd { margin: 0; color: var(--cp-subtle); font-size: 12px; }
    .cp-sim-row-calculation { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 8px; padding: 11px; border-radius: 11px; background: var(--cp-soft); }
    .cp-sim-row-calculation + .cp-sim-row-calculation { margin-top: 8px; }
    .cp-sim-row-benefit-name { grid-column: 1 / -1; font-size: 12px; }
    .cp-sim-row-calculation span { min-width: 0; color: var(--cp-sim-muted); font-size: 11px; }
    .cp-sim-row-calculation b { display: block; margin-top: 2px; color: var(--cp-text); font-size: 13px; font-variant-numeric: tabular-nums; overflow-wrap: anywhere; }
    .cp-sim-row-note { margin: 9px 0 13px; color: var(--cp-warning); font-size: 12px; }
    .cp-sim-empty-list { padding: 38px 0; color: var(--cp-subtle); text-align: center; }

    @media (max-width: 600px) {
      .cp-sim-question-options { grid-template-columns: 1fr; }
      .cp-sim-transaction-head { display: grid; }
      .cp-sim-selection-actions { justify-self: stretch; }
      .cp-sim-selection-actions button { flex: 1; }
    }
    @media (max-width: 520px) {
      .cp-sim-steps { margin-top: -8px; }
      .cp-sim-steps button { font-size: 12px; }
      .cp-sim-steps button span { margin-right: 2px; }
      .cp-sim-facts > div { padding: 14px 11px; }
      .cp-sim-facts dd { font-size: 15px; }
      .cp-sim-grace,
      .cp-sim-question-result { display: grid; gap: 3px; }
      .cp-sim-grace span,
      .cp-sim-question-result span { text-align: left; }
      .cp-sim-details dl div { grid-template-columns: 1fr; gap: 1px; }
      .cp-sim-details dd { text-align: left; }
      .cp-sim-benefit-rules dl > div,
      .cp-sim-policy-rules > div { grid-template-columns: 1fr; gap: 1px; }
      .cp-sim-benefit-rules dd,
      .cp-sim-policy-rules dd { text-align: left; }
      .cp-sim-summary { top: 136px; margin-inline: -4px; padding-inline: 12px; }
      .cp-sim-summary-values > div + div { padding-left: 10px; }
      .cp-sim-summary-values strong { font-size: 17px; }
      .cp-sim-calculation-body dl > div { grid-template-columns: 105px minmax(0, 1fr); gap: 10px; }
      .cp-sim-transaction-label { gap: 10px; }
      .cp-sim-row-side { min-width: 106px; }
      .cp-sim-row-details { margin-left: 32px; }
      .cp-sim-annual-fee { display: grid; gap: 2px; }
    }
    @media (max-width: 360px) {
      .cp-sim-steps { margin-inline: -8px; }
      .cp-sim-steps button { padding-inline: 2px; font-size: 11px; }
      .cp-sim-steps button span { width: 19px; height: 19px; }
      .cp-sim-facts { grid-template-columns: 1fr; }
      .cp-sim-facts > div + div { border-top: 1px solid var(--cp-line); border-left: 0; }
      .cp-sim-facts > div { display: grid; grid-template-columns: 70px minmax(0, 1fr); align-items: baseline; gap: 6px; padding: 10px 13px; }
      .cp-sim-facts dd { margin: 0; }
      .cp-sim-facts small { grid-column: 2; }
      .cp-sim-question-transaction { align-items: flex-start; }
      .cp-sim-summary-values { grid-template-columns: repeat(2, minmax(0, 1fr)); row-gap: 8px; }
      .cp-sim-summary-values > div:nth-child(3) { grid-column: 1 / -1; padding-top: 8px; padding-left: 0; border-top: 1px solid var(--cp-line); border-left: 0; }
      .cp-sim-summary-values strong { overflow-wrap: normal; font-size: 15px; white-space: nowrap; }
      .cp-sim-transaction-label { grid-template-columns: auto minmax(0, 1fr) 96px; gap: 8px; }
      .cp-sim-row-side { min-width: 0; }
      .cp-sim-row-amount { font-size: 14px; }
      .cp-sim-row-benefit { font-size: 11px; }
      .cp-sim-row-calculation { grid-template-columns: 1fr; }
    }
    @media (max-width: 320px) {
      .cp-sim-steps button span { display: none; }
      .cp-sim-summary-values > div:nth-child(2) { padding-left: 7px; }
      .cp-sim-summary-values strong { font-size: 14px; }
      .cp-sim-transaction-label { grid-template-columns: auto minmax(0, 1fr) 88px; gap: 7px; }
    }
    """#

    static let body = #"""
    <section id="view-simulation" hidden>
      <p id="simulation-loading" class="cp-sim-loading">시뮬레이션을 불러오는 중입니다.</p>
      <div id="simulation-load-error" class="cp-sim-load-error" hidden>
        <p id="simulation-load-error-message">시뮬레이션을 불러오지 못했습니다.</p>
        <button id="simulation-retry" type="button">다시 시도</button>
      </div>
      <div id="simulation-empty" class="cp-sim-empty" hidden>
        <div>
          <h1>카드 시뮬레이션</h1>
          <p>카드 정보와 분석 월을 에이전트에게 전달하면 분석 결과가 준비됩니다.</p>
        </div>
      </div>
      <div id="simulation-draft" hidden>
        <nav class="cp-sim-steps" aria-label="카드 시뮬레이션 단계">
          <button type="button" data-simulation-step="policy" aria-current="step"><span>1</span>카드 조건</button>
          <button type="button" data-simulation-step="questions" disabled><span>2</span>확인할 거래</button>
          <button type="button" data-simulation-step="transactions" disabled><span>3</span>거래 선택</button>
        </nav>

        <section id="simulation-screen-policy" aria-labelledby="simulation-policy-title">
          <header class="cp-sim-heading cp-sim-heading-row">
            <div><p id="simulation-policy-card"></p><h1 id="simulation-policy-title" tabindex="-1">카드 조건</h1></div>
            <span id="simulation-policy-state" class="cp-sim-state">확인 전</span>
          </header>
          <dl class="cp-sim-facts">
            <div><dt>연회비</dt><dd id="simulation-annual-fee"></dd></div>
            <div><dt>분석월</dt><dd id="simulation-analysis-month"></dd></div>
            <div><dt>거래</dt><dd id="simulation-transaction-count"></dd></div>
          </dl>
          <section class="cp-sim-policy-section" aria-labelledby="simulation-tier-title">
            <h2 id="simulation-tier-title">전월 실적 한도</h2>
            <table class="cp-sim-policy-table">
              <thead><tr><th scope="col">전월 실적</th><th scope="col">월 한도</th></tr></thead>
              <tbody id="simulation-tier-body"></tbody>
            </table>
            <p id="simulation-grace" class="cp-sim-grace" hidden><strong id="simulation-grace-label"></strong><span id="simulation-grace-value"></span></p>
          </section>
          <section class="cp-sim-policy-section" aria-labelledby="simulation-benefit-title">
            <h2 id="simulation-benefit-title">혜택</h2>
            <dl id="simulation-benefit-policy-rules" class="cp-sim-policy-rules"></dl>
            <ul id="simulation-benefit-list" class="cp-sim-benefits"></ul>
            <p class="cp-sim-policy-note">실적 제외와 혜택 제외는 별도로 계산합니다.</p>
          </section>
          <details class="cp-sim-details">
            <summary>출처 보기</summary>
            <dl id="simulation-source-list"></dl>
          </details>
          <details class="cp-sim-details">
            <summary>제외 정책 보기</summary>
            <div class="cp-sim-exclusions"><h3>실적 제외</h3><ul id="simulation-performance-exclusions"></ul></div>
            <div class="cp-sim-exclusions"><h3>혜택 제외</h3><ul id="simulation-benefit-exclusions"></ul></div>
          </details>
          <p class="cp-sim-preservation"><strong>기존 데이터 유지</strong> · 거래 원본과 기존 판정은 바뀌지 않습니다.</p>
          <button id="simulation-confirm-policy" class="cp-sim-primary" type="button">카드 조건 확인</button>
        </section>

        <section id="simulation-screen-questions" aria-labelledby="simulation-questions-title" hidden>
          <header class="cp-sim-heading"><p id="simulation-classification-summary"></p><h1 id="simulation-questions-title" tabindex="-1">확인할 거래</h1></header>
          <div id="simulation-question-list" class="cp-sim-question-list"></div>
          <button id="simulation-confirm-questions" class="cp-sim-primary" type="button">거래 선택으로 이동</button>
        </section>

        <section id="simulation-screen-transactions" aria-labelledby="simulation-transactions-title" hidden>
          <header class="cp-sim-heading"><p id="simulation-transactions-meta"></p><h1 id="simulation-transactions-title" tabindex="-1">거래 선택</h1></header>
          <div class="cp-sim-assumption"><label for="simulation-assumption">전월 실적 가정</label><select id="simulation-assumption"></select></div>
          <section class="cp-sim-summary" aria-labelledby="simulation-summary-title">
            <h2 id="simulation-summary-title" class="cp-sr-only">선택 결과</h2>
            <div class="cp-sim-summary-values">
              <div><span>예상 혜택</span><strong id="simulation-benefit-total">0원</strong></div>
              <div><span>피킹률</span><strong id="simulation-picking-rate">—</strong></div>
              <div><span>선택액</span><strong id="simulation-selected-total">0원</strong></div>
            </div>
            <p id="simulation-picking-help">피킹률은 선택한 결제액 전체를 분모로 계산합니다.</p>
            <p id="simulation-range-note" class="cp-sim-range-note" hidden>확인 전 거래가 있어 최소–최대 범위로 표시합니다.</p>
          </section>
          <details id="simulation-calculation-details" class="cp-sim-calculation">
            <summary>계산 상세</summary>
            <div class="cp-sim-calculation-body">
              <dl>
                <div><dt>선택 거래</dt><dd id="simulation-selected-count"></dd></div>
                <div><dt>실적 인정액</dt><dd id="simulation-performance-total"></dd></div>
                <div><dt>다음 달 전망</dt><dd id="simulation-performance-outlook"></dd></div>
              </dl>
              <dl id="simulation-limit-list" class="cp-sim-limit-list"></dl>
              <p class="cp-sim-annual-fee"><span id="simulation-annual-fee-label"></span><strong id="simulation-net-picking-rate"></strong></p>
            </div>
          </details>
          <section class="cp-sim-transaction-section" aria-labelledby="simulation-transaction-list-title">
            <div class="cp-sim-transaction-head">
              <div><h2 id="simulation-transaction-list-title">거래</h2><p id="simulation-transaction-meta"></p></div>
              <div class="cp-sim-selection-actions">
                <button id="simulation-select-all" type="button">모두 선택</button>
                <button id="simulation-clear-all" type="button">모두 해제</button>
              </div>
            </div>
            <ol id="simulation-transaction-list" class="cp-sim-transactions"></ol>
            <p id="simulation-transaction-empty" class="cp-sim-empty-list" hidden>분석할 승인 거래가 없습니다.</p>
          </section>
        </section>
      </div>
    </section>
    """#

    static let script = #"""
    const candidateSimulationEndpoint = '/api/v1/candidate-simulations/current';
    let candidateSimulationResponse = null;
    let candidateSimulationStep = 'policy';
    let candidateSimulationBusy = false;
    let candidateSimulationLoading = false;

    function candidateRangeText(range, formatter) {
      if (!range) return '—';
      const minimum = formatter(range.minimum);
      const maximum = formatter(range.maximum);
      return range.minimum === range.maximum ? minimum : `${minimum}–${maximum}`;
    }

    function candidateWonRange(range) {
      return candidateRangeText(range, won);
    }

    function candidateRateRange(range) {
      return candidateRangeText(range, value => `${Number(value).toFixed(2)}%`);
    }

    function candidateRateLabel(basisPoints) {
      const percent = Number(basisPoints) / 100;
      return `${percent.toLocaleString('ko-KR', { maximumFractionDigits: 2 })}%`;
    }

    function candidateTransactionAmountRule(benefit) {
      const minimum = benefit.minimumTransactionAmount;
      const maximum = benefit.maximumTransactionAmount;
      if (minimum == null && maximum == null) return '제한 없음';
      if (minimum != null && maximum != null) {
        return minimum === maximum ? won(minimum) : `${won(minimum)}–${won(maximum)}`;
      }
      return minimum != null ? `${won(minimum)} 이상` : `${won(maximum)} 이하`;
    }

    function candidateRoundingRuleLabel(rule) {
      const directions = { floor: '버림', nearest: '반올림', ceiling: '올림' };
      return `${won(rule.unit)} 단위 ${directions[rule.direction] || rule.direction}`;
    }

    function candidateStackingRuleLabel(value) {
      if (value === 'allEligible') return '조건 충족 혜택 모두 적용';
      if (value === 'highestPriorityOnly') return '우선순위가 가장 높은 혜택 1개 적용';
      return value;
    }

    function candidateBenefitLimitGroups(policy, benefit) {
      if (benefit.limitGroupIDs.length === 0) return '월 한도 없음';
      const labels = new Map(policy.limitGroups.map(value => [value.id, value.label]));
      return benefit.limitGroupIDs.map(id => labels.get(id) || id).join(' · ');
    }

    function candidateDateLabel(value) {
      if (!value) return '날짜 미상';
      return new Intl.DateTimeFormat('ko-KR', {
        dateStyle: 'medium',
        timeZone: 'Asia/Seoul'
      }).format(new Date(value));
    }

    function candidateMonthLabel(value) {
      const [year, month] = String(value || '').split('-').map(Number);
      return year && month ? `${year}년 ${month}월` : String(value || '분석 월 미상');
    }

    function candidateText(selector, value) {
      $(selector).textContent = value == null ? '' : String(value);
    }

    function candidateUnique(values) {
      return [...new Set(values.filter(Boolean))];
    }

    function candidateByTransaction(values, id) {
      return values.find(value => value.transactionID === id);
    }

    function candidateAnswerFor(simulation, transactionID) {
      return simulation.state.answers.find(value => value.transactionId === transactionID);
    }

    function candidateChosenAlternative(simulation, classification) {
      const answer = candidateAnswerFor(simulation, classification.transactionID);
      return answer
        ? classification.alternatives.find(value => value.id === answer.alternativeId) || null
        : null;
    }

    function candidateClassificationState(response, classification) {
      const { simulation, calculation } = response;
      const chosen = candidateChosenAlternative(simulation, classification);
      if (classification.question && !chosen) {
        return { label: '확인 필요', className: 'is-question' };
      }
      const result = candidateByTransaction(calculation.transactions, classification.transactionID);
      const hasBenefit = Boolean(result && result.rawBenefitAmount.maximum > 0);
      return hasBenefit
        ? { label: '혜택 대상', className: '' }
        : { label: '혜택 없음', className: 'is-none' };
    }

    function candidateClassificationSummary(response) {
      const { simulation } = response;
      const counts = { target: 0, none: 0, question: 0 };
      simulation.classifications.forEach(classification => {
        const value = candidateClassificationState(response, classification);
        if (value.className === 'is-question') counts.question += 1;
        else if (value.className === 'is-none') counts.none += 1;
        else counts.target += 1;
      });
      return `혜택 대상 ${counts.target} · 혜택 없음 ${counts.none} · 확인 필요 ${counts.question}`;
    }

    function candidateAssumptionLimitText(policy, assumption) {
      const values = policy.limitGroups.map(group => {
        const maximum = assumption.limitGroupMaximumAmounts[group.id] ?? 0;
        return `${group.label} ${won(maximum)}`;
      });
      return values.length > 0 ? values.join(' · ') : '월 한도 없음';
    }

    function candidateAppendDefinitionListRow(list, label, value) {
      const row = document.createElement('div');
      const term = document.createElement('dt');
      const description = document.createElement('dd');
      term.textContent = label;
      description.textContent = value;
      row.append(term, description);
      list.append(row);
    }

    function candidateRenderStringList(selector, values) {
      const list = $(selector);
      const rows = values.length > 0 ? values : ['없음'];
      list.replaceChildren(...rows.map(value => {
        const item = document.createElement('li');
        item.textContent = value;
        return item;
      }));
    }

    function candidateBenefitRuleList(policy, benefit) {
      const list = document.createElement('dl');
      candidateAppendDefinitionListRow(list, '혜택률', candidateRateLabel(benefit.rateBasisPoints));
      candidateAppendDefinitionListRow(list, '결제 금액', candidateTransactionAmountRule(benefit));
      candidateAppendDefinitionListRow(
        list,
        '건별 혜택 한도',
        benefit.perTransactionMaximumBenefitAmount == null
          ? '제한 없음'
          : won(benefit.perTransactionMaximumBenefitAmount)
      );
      candidateAppendDefinitionListRow(
        list,
        '월 횟수',
        benefit.monthlyCountLimit == null ? '제한 없음' : `${benefit.monthlyCountLimit}회`
      );
      candidateAppendDefinitionListRow(list, '월 한도', candidateBenefitLimitGroups(policy, benefit));
      candidateAppendDefinitionListRow(list, '우선순위', `${benefit.priority} · 숫자가 작을수록 먼저`);
      candidateAppendDefinitionListRow(list, '반올림', candidateRoundingRuleLabel(benefit.rounding));
      return list;
    }

    function candidateRenderPolicy(response) {
      const { simulation, calculation } = response;
      const { policy } = simulation;
      candidateText('#simulation-policy-card', `${policy.cardName} · ${policy.issuerName}`);
      candidateText('#simulation-annual-fee', won(policy.annualFeeAmount));
      candidateText('#simulation-analysis-month', candidateMonthLabel(simulation.month));

      const transactionCount = $('#simulation-transaction-count');
      transactionCount.replaceChildren(document.createTextNode(`승인 ${simulation.facts.length}건`));
      const excludedParts = [];
      if (simulation.excluded.cancellations > 0) excludedParts.push(`취소 ${simulation.excluded.cancellations}건 제외`);
      if (simulation.excluded.other > 0) excludedParts.push(`기타 ${simulation.excluded.other}건 제외`);
      if (excludedParts.length > 0) {
        const excluded = document.createElement('small');
        excluded.textContent = excludedParts.join(' · ');
        transactionCount.append(excluded);
      }

      const tierBody = $('#simulation-tier-body');
      const tiers = policy.performanceAssumptions.filter(value => !value.isGrace);
      tierBody.replaceChildren(...tiers.map(assumption => {
        const row = document.createElement('tr');
        const label = document.createElement('td');
        const limit = document.createElement('td');
        label.textContent = assumption.label;
        limit.textContent = candidateAssumptionLimitText(policy, assumption);
        row.append(label, limit);
        return row;
      }));

      const grace = policy.performanceAssumptions.find(value => value.isGrace);
      $('#simulation-grace').hidden = !grace;
      if (grace) {
        candidateText('#simulation-grace-label', grace.label);
        candidateText('#simulation-grace-value', candidateAssumptionLimitText(policy, grace));
      }

      const benefitList = $('#simulation-benefit-list');
      const policyRules = $('#simulation-benefit-policy-rules');
      policyRules.replaceChildren();
      candidateAppendDefinitionListRow(
        policyRules,
        '중복 적용',
        candidateStackingRuleLabel(policy.stacking)
      );
      const benefitRows = policy.benefits.map(benefit => {
        const item = document.createElement('li');
        const label = document.createElement('strong');
        const condition = document.createElement('span');
        label.textContent = benefit.label;
        condition.textContent = benefit.conditionSummary;
        item.append(label, condition);
        if (benefit.exclusionNotes.length > 0) {
          const exclusions = document.createElement('span');
          exclusions.textContent = `제외: ${benefit.exclusionNotes.join(' · ')}`;
          item.append(exclusions);
        }
        const rules = document.createElement('details');
        rules.className = 'cp-sim-benefit-rules';
        const summary = document.createElement('summary');
        summary.textContent = '계산 조건';
        rules.append(summary, candidateBenefitRuleList(policy, benefit));
        item.append(rules);
        return item;
      });
      if (benefitRows.length === 0) {
        const empty = document.createElement('li');
        empty.textContent = '등록된 혜택이 없습니다.';
        benefitRows.push(empty);
      }
      benefitList.replaceChildren(...benefitRows);

      const sourceList = $('#simulation-source-list');
      sourceList.replaceChildren();
      candidateAppendDefinitionListRow(sourceList, '상품 식별', policy.productIdentifier);
      candidateAppendDefinitionListRow(sourceList, '출처', `${policy.source.name} · ${policy.source.reference}`);
      candidateAppendDefinitionListRow(sourceList, '기준일', candidateDateLabel(policy.source.effectiveDate));
      candidateAppendDefinitionListRow(sourceList, '구조화', candidateDateLabel(policy.source.structuredAt));
      candidateAppendDefinitionListRow(sourceList, '정책 버전', `v${policy.schemaVersion}`);
      candidateRenderStringList('#simulation-performance-exclusions', policy.performanceExclusions);
      candidateRenderStringList('#simulation-benefit-exclusions', policy.benefitExclusions);

      const policyState = $('#simulation-policy-state');
      policyState.textContent = simulation.state.policyConfirmed ? '확인함' : '확인 전';
      policyState.classList.toggle('is-confirmed', simulation.state.policyConfirmed);
      candidateText(
        '#simulation-confirm-policy',
        simulation.state.policyConfirmed ? '확인할 거래로 이동' : '카드 조건 확인'
      );

      candidateText(
        '#simulation-annual-fee-label',
        `연회비 월 환산 ${won(calculation.annualFeeMonthlyAmount)} 반영${policy.annualFeeAmount % 12 === 0 ? '' : ' · 1원 미만 버림'}`
      );
    }

    function candidateQuestionResult(response, classification) {
      const { simulation, calculation } = response;
      const chosen = candidateChosenAlternative(simulation, classification);
      const transaction = candidateByTransaction(calculation.transactions, classification.transactionID);
      const range = transaction?.rawBenefitAmount;
      if (chosen) {
        return {
          resolved: true,
          label: chosen.answerLabel || '답변 반영',
          detail: range && range.maximum > 0
            ? `${chosen.benefitReason} · 한도 전 혜택 ${candidateWonRange(range)}`
            : chosen.benefitReason
        };
      }
      return {
        resolved: false,
        label: '미응답',
        detail: range && range.maximum > 0
          ? `한도 전 혜택 ${candidateWonRange(range)}`
          : '가능한 분류를 범위로 계산합니다.'
      };
    }

    function candidateRenderQuestions(response) {
      const { simulation } = response;
      candidateText('#simulation-classification-summary', candidateClassificationSummary(response));
      const questions = simulation.classifications.filter(value => value.question);
      const questionList = $('#simulation-question-list');
      if (questions.length === 0) {
        const empty = document.createElement('p');
        empty.className = 'cp-sim-empty-list';
        empty.textContent = '확인할 거래가 없습니다.';
        questionList.replaceChildren(empty);
      } else {
        questionList.replaceChildren(...questions.map((classification, index) => {
          const fact = simulation.facts.find(value => value.id === classification.transactionID);
          const card = document.createElement('section');
          card.className = 'cp-sim-question-card';
          card.dataset.transactionId = classification.transactionID;
          card.tabIndex = -1;

          const transaction = document.createElement('div');
          transaction.className = 'cp-sim-question-transaction';
          const copy = document.createElement('div');
          const date = document.createElement('span');
          const merchant = document.createElement('h2');
          const amount = document.createElement('strong');
          date.textContent = `${candidateDateLabel(fact?.occurredAt)} · 승인`;
          merchant.textContent = fact?.merchant || '가맹점 미상';
          amount.textContent = won(fact?.amount);
          copy.append(date, merchant);
          transaction.append(copy, amount);

          const fieldset = document.createElement('fieldset');
          fieldset.className = 'cp-sim-question-fieldset';
          const legend = document.createElement('legend');
          legend.textContent = classification.question;
          const options = document.createElement('div');
          options.className = 'cp-sim-question-options';
          const answer = candidateAnswerFor(simulation, classification.transactionID);
          classification.alternatives.forEach((alternative, optionIndex) => {
            const label = document.createElement('label');
            const input = document.createElement('input');
            const text = document.createElement('span');
            input.type = 'radio';
            input.name = `candidate-question-${index}`;
            input.value = alternative.id;
            input.dataset.transactionId = classification.transactionID;
            input.dataset.alternativeId = alternative.id;
            input.checked = answer?.alternativeId === alternative.id;
            text.textContent = alternative.answerLabel || alternative.id;
            label.append(input, text);
            input.addEventListener('change', () => {
              const answers = simulation.state.answers
                .filter(value => value.transactionId !== classification.transactionID);
              answers.push({
                transactionId: classification.transactionID,
                alternativeId: alternative.id
              });
              candidatePatch(
                { answers },
                {
                  focus: {
                    type: 'answer',
                    transactionID: classification.transactionID,
                    alternativeID: alternative.id
                  },
                  message: '답변을 반영했습니다.'
                }
              ).catch(showError);
            });
            options.append(label);
          });
          fieldset.append(legend, options);

          const resultValue = candidateQuestionResult(response, classification);
          const result = document.createElement('p');
          result.className = `cp-sim-question-result${resultValue.resolved ? ' is-resolved' : ''}`;
          const resultLabel = document.createElement('strong');
          const resultDetail = document.createElement('span');
          resultLabel.textContent = resultValue.label;
          resultDetail.textContent = resultValue.detail;
          result.append(resultLabel, resultDetail);
          card.append(transaction, fieldset, result);
          return card;
        }));
      }

      const unresolvedCount = questions.filter(value => !candidateChosenAlternative(simulation, value)).length;
      candidateText(
        '#simulation-confirm-questions',
        unresolvedCount > 0 ? '범위로 거래 선택' : '거래 선택으로 이동'
      );
    }

    function candidateRenderAssumptions(response) {
      const { policy } = response.simulation;
      const selector = $('#simulation-assumption');
      selector.replaceChildren(...policy.performanceAssumptions.map(assumption => {
        const option = document.createElement('option');
        option.value = assumption.id;
        option.textContent = `${assumption.label} · ${candidateAssumptionLimitText(policy, assumption)}`;
        return option;
      }));
      selector.value = response.simulation.state.performanceAssumptionId;
    }

    function candidateNextThresholdText(value) {
      if (!value.thresholdAmount || !value.remainingAmount) {
        return value.includesNoNextThreshold ? '최고 실적 구간 충족' : '다음 구간 없음';
      }
      const remaining = `${candidateWonRange(value.remainingAmount)} 남음`;
      return value.includesNoNextThreshold
        ? `최고 구간 충족 가능 · ${remaining}`
        : `${candidateWonRange(value.thresholdAmount)}까지 ${remaining}`;
    }

    function candidateRenderSummary(response) {
      const { calculation } = response;
      candidateText('#simulation-benefit-total', candidateWonRange(calculation.benefitAmount));
      candidateText('#simulation-picking-rate', candidateRateRange(calculation.pickingRatePercentage));
      candidateText('#simulation-selected-total', won(calculation.selectedTransactionAmount));
      candidateText('#simulation-selected-count', `${calculation.selectedTransactionCount}건`);
      candidateText('#simulation-performance-total', candidateWonRange(calculation.performanceAmount));
      candidateText('#simulation-performance-outlook', candidateNextThresholdText(calculation.nextPerformanceThreshold));
      candidateText(
        '#simulation-picking-help',
        calculation.selectedTransactionCount === 0
          ? '거래를 선택하면 계산됩니다.'
          : '피킹률은 선택한 결제액 전체를 분모로 계산합니다.'
      );
      const hasRange = calculation.benefitAmount.minimum !== calculation.benefitAmount.maximum
        || calculation.performanceAmount.minimum !== calculation.performanceAmount.maximum
        || Boolean(calculation.pickingRatePercentage
          && calculation.pickingRatePercentage.minimum !== calculation.pickingRatePercentage.maximum);
      $('#simulation-range-note').hidden = !hasRange;
      candidateText(
        '#simulation-net-picking-rate',
        candidateRateRange(calculation.annualFeeAdjustedPickingRatePercentage)
      );

      const limitList = $('#simulation-limit-list');
      const limitRows = calculation.limitGroups.map(group => {
        const row = document.createElement('div');
        const label = document.createElement('dt');
        const amount = document.createElement('dd');
        label.textContent = group.label;
        amount.textContent = `${candidateWonRange(group.usedAmount)} / ${won(group.maximumAmount)} · 잔여 ${candidateWonRange(group.remainingAmount)}`;
        row.append(label, amount);
        return row;
      });
      if (limitRows.length === 0) {
        const row = document.createElement('div');
        const label = document.createElement('dt');
        const amount = document.createElement('dd');
        label.textContent = '월 한도';
        amount.textContent = '없음';
        row.append(label, amount);
        limitRows.push(row);
      }
      limitList.replaceChildren(...limitRows);
    }

    function candidateEvidenceFor(response, classification) {
      const { simulation } = response;
      const chosen = candidateChosenAlternative(simulation, classification);
      const alternatives = chosen ? [chosen] : classification.alternatives;
      const result = candidateByTransaction(response.calculation.transactions, classification.transactionID);
      const resolvedWithoutBenefit = Boolean(
        (!classification.question || chosen)
        && result
        && result.rawBenefitAmount.maximum === 0
      );
      const performance = candidateUnique(alternatives.map(value => {
        const status = value.performance === 'included' ? '실적 인정' : '실적 제외';
        return `${status} · ${value.performanceReason}`;
      })).join(' / ');
      const benefitByID = new Map(simulation.policy.benefits.map(value => [value.id, value.label]));
      const benefits = candidateUnique(alternatives.map(value => {
        const names = resolvedWithoutBenefit
          ? []
          : value.benefitIDs.map(id => benefitByID.get(id) || id);
        const status = names.length > 0 ? names.join(', ') : '혜택 없음';
        return `${status} · ${value.benefitReason}`;
      })).join(' / ');
      return { performance, benefits };
    }

    function candidateAppendEvidenceRow(list, label, value) {
      const row = document.createElement('div');
      const term = document.createElement('dt');
      const description = document.createElement('dd');
      term.textContent = label;
      description.textContent = value;
      row.append(term, description);
      list.append(row);
    }

    function candidateAppendCalculationValue(list, label, range) {
      const item = document.createElement('span');
      const value = document.createElement('b');
      item.append(document.createTextNode(label), value);
      value.textContent = candidateWonRange(range);
      list.append(item);
    }

    function candidateAppendBenefitCalculations(details, response, result) {
      const benefitByID = new Map(response.simulation.policy.benefits.map(value => [value.id, value]));
      const allocations = result.benefitBreakdownIsAdditive && result.benefits.length > 0
        ? result.benefits
        : [{
            benefitID: null,
            label: '전체 예상 혜택',
            rawBenefitAmount: result.rawBenefitAmount,
            appliedBenefitAmount: result.appliedBenefitAmount,
            missedBenefitAmount: result.missedBenefitAmount
          }];
      allocations.forEach(allocation => {
        const calculations = document.createElement('div');
        calculations.className = 'cp-sim-row-calculation';
        const label = document.createElement('strong');
        label.className = 'cp-sim-row-benefit-name';
        label.textContent = benefitByID.get(allocation.benefitID)?.label
          || allocation.label
          || '혜택';
        calculations.append(label);
        candidateAppendCalculationValue(calculations, '한도 전', allocation.rawBenefitAmount);
        candidateAppendCalculationValue(calculations, '실제 적용', allocation.appliedBenefitAmount);
        candidateAppendCalculationValue(calculations, '미수혜', allocation.missedBenefitAmount);
        details.append(calculations);
      });
      if (!result.benefitBreakdownIsAdditive && result.benefits.length > 0) {
        const note = document.createElement('p');
        note.className = 'cp-sim-row-note';
        note.textContent = '혜택별 가능 금액이 함께 변해 합계 범위로 표시합니다.';
        details.append(note);
      }
    }

    function candidateBenefitDisplay(response, classification, result) {
      const stateValue = candidateClassificationState(response, classification);
      const range = result.isSelected ? result.appliedBenefitAmount : result.rawBenefitAmount;
      const prefix = result.isSelected ? '' : '한도 전 ';
      return {
        text: `${prefix}${candidateWonRange(range)}`,
        className: stateValue.className,
        status: stateValue.label
      };
    }

    function candidateOpenTransactionIDs() {
      return new Set($$('#simulation-transaction-list .cp-sim-row-details[open]')
        .map(value => value.dataset.transactionId));
    }

    function candidateRenderTransactions(response, openTransactionIDs = new Set()) {
      const { simulation, calculation } = response;
      const list = $('#simulation-transaction-list');
      const rows = calculation.transactions.map((result, index) => {
        const fact = simulation.facts.find(value => value.id === result.transactionID);
        const classification = candidateByTransaction(simulation.classifications, result.transactionID);
        if (!fact || !classification) return null;
        const benefit = candidateBenefitDisplay(response, classification, result);

        const row = document.createElement('li');
        row.className = 'cp-sim-transaction';
        row.dataset.transactionId = fact.id;
        row.dataset.selected = String(result.isSelected);

        const label = document.createElement('label');
        label.className = 'cp-sim-transaction-label';
        const checkbox = document.createElement('input');
        checkbox.className = 'cp-sim-transaction-check';
        checkbox.type = 'checkbox';
        checkbox.checked = result.isSelected;
        checkbox.dataset.transactionId = fact.id;
        checkbox.setAttribute(
          'aria-label',
          `${fact.merchant}, ${candidateDateLabel(fact.occurredAt)}, ${won(fact.amount)}, ${benefit.status}, 예상 혜택 ${benefit.text}`
        );

        const copy = document.createElement('span');
        copy.className = 'cp-sim-row-copy';
        const merchant = document.createElement('strong');
        merchant.className = 'cp-sim-row-merchant';
        merchant.textContent = fact.merchant;
        const date = document.createElement('span');
        date.className = 'cp-sim-row-date';
        date.textContent = `${candidateDateLabel(fact.occurredAt)} · 승인`;
        const status = document.createElement('span');
        status.className = 'cp-sim-row-status';
        status.textContent = benefit.status;
        copy.append(merchant, date, status);

        const side = document.createElement('span');
        side.className = 'cp-sim-row-side';
        const amount = document.createElement('strong');
        amount.className = 'cp-sim-row-amount';
        amount.textContent = won(fact.amount);
        const benefitAmount = document.createElement('span');
        benefitAmount.className = `cp-sim-row-benefit ${benefit.className}`.trim();
        benefitAmount.textContent = benefit.text;
        side.append(amount, benefitAmount);
        label.append(checkbox, copy, side);
        row.append(label);

        checkbox.addEventListener('change', () => {
          const selected = new Set(simulation.state.selectedTransactionIds);
          if (checkbox.checked) selected.add(fact.id);
          else selected.delete(fact.id);
          candidatePatch(
            { selectedTransactionIds: [...selected] },
            {
              focus: { type: 'transaction', transactionID: fact.id },
              message: '계산을 갱신했습니다.'
            }
          ).catch(showError);
        });

        const unresolved = Boolean(classification.question && !candidateChosenAlternative(simulation, classification));
        if (unresolved) {
          const actions = document.createElement('div');
          actions.className = 'cp-sim-row-actions';
          const review = document.createElement('button');
          review.className = 'cp-sim-question-review';
          review.type = 'button';
          review.textContent = '확인하기';
          review.setAttribute('aria-label', `${fact.merchant} 분류 확인`);
          review.addEventListener('click', () => {
            candidateSetStep('questions');
            candidateRestoreFocus({
              type: 'question',
              transactionID: classification.transactionID
            });
          });
          actions.append(review);
          row.append(actions);
        }

        const details = document.createElement('details');
        details.className = 'cp-sim-row-details';
        details.dataset.transactionId = fact.id;
        details.open = openTransactionIDs.has(fact.id);
        const summary = document.createElement('summary');
        summary.textContent = '근거 보기';
        const evidence = document.createElement('dl');
        evidence.className = 'cp-sim-evidence';
        const evidenceValue = candidateEvidenceFor(response, classification);
        candidateAppendEvidenceRow(evidence, '실적', evidenceValue.performance);
        candidateAppendEvidenceRow(evidence, '혜택', evidenceValue.benefits);
        details.append(summary, evidence);

        if (result.isSelected) {
          candidateAppendBenefitCalculations(details, response, result);
          if (unresolved || result.missedBenefitAmount.maximum > 0) {
            const note = document.createElement('p');
            note.className = 'cp-sim-row-note';
            note.textContent = unresolved
              ? '미응답에 따라 적용액이 범위로 표시됩니다.'
              : '조건과 한도 적용 후 받지 못한 금액이 있습니다.';
            details.append(note);
          }
        }
        row.append(details);
        return row;
      }).filter(Boolean);

      list.replaceChildren(...rows);
      $('#simulation-transaction-empty').hidden = rows.length > 0;
      candidateText(
        '#simulation-transaction-meta',
        [
          `승인 ${simulation.facts.length}건`,
          simulation.excluded.cancellations > 0 ? `취소 ${simulation.excluded.cancellations}건 제외` : '',
          simulation.excluded.other > 0 ? `기타 ${simulation.excluded.other}건 제외` : ''
        ].filter(Boolean).join(' · ')
      );
    }

    function candidateCanOpenStep(step) {
      const simulation = candidateSimulationResponse?.simulation;
      if (!simulation || step === 'policy') return Boolean(simulation);
      if (step === 'questions') return simulation.state.policyConfirmed;
      return simulation.state.policyConfirmed && simulation.state.questionsReviewed;
    }

    function candidateRenderStepAccess() {
      if (!candidateSimulationResponse) return;
      if (!candidateCanOpenStep(candidateSimulationStep)) {
        candidateSimulationStep = candidateSimulationResponse.simulation.state.policyConfirmed
          ? 'questions'
          : 'policy';
      }
      $$('[data-simulation-step]').forEach(button => {
        const step = button.dataset.simulationStep;
        button.disabled = !candidateCanOpenStep(step);
        if (step === candidateSimulationStep) button.setAttribute('aria-current', 'step');
        else button.removeAttribute('aria-current');
      });
      ['policy', 'questions', 'transactions'].forEach(step => {
        $(`#simulation-screen-${step}`).hidden = step !== candidateSimulationStep;
      });
    }

    function candidateRender(openTransactionIDs = candidateOpenTransactionIDs()) {
      const loading = $('#simulation-loading');
      const loadError = $('#simulation-load-error');
      const empty = $('#simulation-empty');
      const draft = $('#simulation-draft');
      loading.hidden = true;
      loadError.hidden = true;
      empty.hidden = Boolean(candidateSimulationResponse);
      draft.hidden = !candidateSimulationResponse;
      if (!candidateSimulationResponse) return;

      const { simulation } = candidateSimulationResponse;
      candidateRenderPolicy(candidateSimulationResponse);
      candidateRenderQuestions(candidateSimulationResponse);
      candidateRenderAssumptions(candidateSimulationResponse);
      candidateRenderSummary(candidateSimulationResponse);
      candidateText('#simulation-transactions-meta', `${simulation.policy.cardName} · ${candidateMonthLabel(simulation.month)}`);
      candidateText('#simulation-transactions-title', `${Number(simulation.month.slice(5))}월 거래 선택`);
      candidateRenderTransactions(candidateSimulationResponse, openTransactionIDs);
      candidateRenderStepAccess();
    }

    function candidateSetBusy(value) {
      candidateSimulationBusy = value;
      const draft = $('#simulation-draft');
      draft.setAttribute('aria-busy', String(value));
      draft.toggleAttribute('inert', value);
    }

    function candidateRestoreFocus(focus) {
      if (!focus) return;
      requestAnimationFrame(() => {
        let element = null;
        if (focus.type === 'id') element = document.getElementById(focus.id);
        if (focus.type === 'transaction') {
          element = $$('#simulation-transaction-list input[data-transaction-id]')
            .find(value => value.dataset.transactionId === focus.transactionID);
        }
        if (focus.type === 'answer') {
          element = $$('#simulation-question-list input[data-transaction-id]')
            .find(value => value.dataset.transactionId === focus.transactionID
              && value.dataset.alternativeId === focus.alternativeID);
        }
        if (focus.type === 'question') {
          element = $$('#simulation-question-list input[data-transaction-id]')
            .find(value => value.dataset.transactionId === focus.transactionID)
            || $$('#simulation-question-list [data-transaction-id]')
              .find(value => value.dataset.transactionId === focus.transactionID);
        }
        element?.focus({ preventScroll: focus.type === 'question' });
        if (focus.type === 'question') element?.scrollIntoView({ block: 'center' });
      });
    }

    function candidateCalculationAnnouncement(response, message) {
      const { calculation } = response;
      const summary = `선택 ${calculation.selectedTransactionCount}건 · 예상 혜택 ${candidateWonRange(calculation.benefitAmount)} · 피킹률 ${candidateRateRange(calculation.pickingRatePercentage)}`;
      return message ? `${message} ${summary}` : summary;
    }

    async function candidatePatch(patch, options = {}) {
      if (!candidateSimulationResponse || candidateSimulationBusy) return;
      const openTransactionIDs = candidateOpenTransactionIDs();
      const { simulation } = candidateSimulationResponse;
      const body = { ...patch, draftId: simulation.id, expectedState: simulation.state };
      candidateSetBusy(true);
      clearError();
      try {
        const response = await api(candidateSimulationEndpoint, {
          method: 'PATCH',
          body: JSON.stringify(body)
        });
        candidateSimulationResponse = response;
        if (options.step) candidateSimulationStep = options.step;
        candidateRender(openTransactionIDs);
        candidateRestoreFocus(options.focus);
        toast(candidateCalculationAnnouncement(response, options.message));
      } catch (error) {
        candidateRender(openTransactionIDs);
        throw error;
      } finally {
        candidateSetBusy(false);
      }
    }

    function candidateSetStep(step, focusHeading = false) {
      if (!candidateCanOpenStep(step)) {
        toast(step === 'questions' ? '카드 조건을 먼저 확인하세요.' : '확인할 거래를 먼저 검토하세요.');
        return;
      }
      candidateSimulationStep = step;
      candidateRenderStepAccess();
      if (focusHeading) candidateRestoreFocus({ type: 'id', id: `simulation-${step}-title` });
    }

    function candidateShowLoadError() {
      $('#simulation-loading').hidden = true;
      $('#simulation-empty').hidden = true;
      $('#simulation-draft').hidden = true;
      $('#simulation-load-error').hidden = false;
      candidateText('#simulation-load-error-message', '시뮬레이션을 불러오지 못했습니다. 다시 시도해 주세요.');
      toast('시뮬레이션을 불러오지 못했습니다. 다시 시도해 주세요.');
      candidateRestoreFocus({ type: 'id', id: 'simulation-retry' });
    }

    async function loadCandidateCardSimulation() {
      if (candidateSimulationLoading) return;
      candidateSimulationLoading = true;
      const retry = $('#simulation-retry');
      retry.disabled = true;
      $('#simulation-loading').hidden = false;
      $('#simulation-load-error').hidden = true;
      $('#simulation-empty').hidden = true;
      $('#simulation-draft').hidden = true;
      clearError();
      try {
        const response = await fetch(candidateSimulationEndpoint);
        if (response.status === 404) {
          candidateSimulationResponse = null;
          candidateRender();
          return;
        }
        if (!response.ok) throw new Error(`요청을 처리하지 못했습니다 (${response.status})`);
        const value = await response.json();
        if (!value.simulation || !value.calculation) throw new Error('시뮬레이션 응답을 확인할 수 없습니다.');
        const isFirstLoad = !candidateSimulationResponse;
        candidateSimulationResponse = value;
        if (isFirstLoad) {
          candidateSimulationStep = value.simulation.state.policyConfirmed
            ? value.simulation.state.questionsReviewed ? 'transactions' : 'questions'
            : 'policy';
        }
        candidateRender();
      } catch (error) {
        candidateShowLoadError();
      } finally {
        candidateSimulationLoading = false;
        retry.disabled = false;
      }
    }

    $$('[data-simulation-step]').forEach(button => {
      button.addEventListener('click', () => candidateSetStep(button.dataset.simulationStep, true));
    });
    $('#simulation-retry').addEventListener('click', () => loadCandidateCardSimulation());
    $('#simulation-confirm-policy').addEventListener('click', () => {
      if (candidateSimulationResponse?.simulation.state.policyConfirmed) {
        candidateSetStep('questions', true);
        return;
      }
      candidatePatch(
        { policyConfirmed: true },
        {
          step: 'questions',
          focus: { type: 'id', id: 'simulation-questions-title' },
          message: '카드 조건을 확인했습니다.'
        }
      ).catch(showError);
    });
    $('#simulation-confirm-questions').addEventListener('click', () => {
      if (candidateSimulationResponse?.simulation.state.questionsReviewed) {
        candidateSetStep('transactions', true);
        return;
      }
      candidatePatch(
        { questionsReviewed: true },
        {
          step: 'transactions',
          focus: { type: 'id', id: 'simulation-transactions-title' },
          message: '거래 선택을 시작합니다.'
        }
      ).catch(showError);
    });
    $('#simulation-assumption').addEventListener('change', event => {
      candidatePatch(
        { performanceAssumptionId: event.target.value },
        { focus: { type: 'id', id: 'simulation-assumption' }, message: '계산을 갱신했습니다.' }
      ).catch(showError);
    });
    $('#simulation-select-all').addEventListener('click', () => {
      const ids = candidateSimulationResponse?.simulation.facts.map(value => value.id) || [];
      candidatePatch(
        { selectedTransactionIds: ids },
        { focus: { type: 'id', id: 'simulation-select-all' }, message: '모든 거래를 선택했습니다.' }
      ).catch(showError);
    });
    $('#simulation-clear-all').addEventListener('click', () => {
      candidatePatch(
        { selectedTransactionIds: [] },
        { focus: { type: 'id', id: 'simulation-clear-all' }, message: '모든 선택을 해제했습니다.' }
      ).catch(showError);
    });
    """#
}
