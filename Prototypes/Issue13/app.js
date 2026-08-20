(() => {
  const won = value => `${Number(value).toLocaleString('ko-KR')}원`;
  const escapeHTML = value => String(value).replace(/[&<>'"]/g, character => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    "'": '&#39;',
    '"': '&quot;'
  })[character]);

  const assumptions = {
    missed: { label: '실적 미달', limit: 0 },
    tier300: { label: '30만원 달성', limit: 15_000 },
    tier600: { label: '60만원 달성', limit: 30_000 },
    grace: { label: '신규 발급 유예', limit: 15_000 }
  };

  const transactions = [
    {
      id: 'cherry-market',
      dateLabel: '07.02',
      merchant: '체리마켓 온라인',
      amount: 43_000,
      category: '온라인 쇼핑',
      performanceIncluded: true,
      performanceReason: '일반 신용판매 승인 거래',
      benefit: { rule: '간편결제 10% 청구할인', reason: '체리페이 결제 · 건당 1만원 이상', raw: 4_300 }
    },
    {
      id: 'apartment',
      dateLabel: '07.04',
      merchant: '합성아파트 관리비',
      amount: 168_000,
      category: '관리비',
      performanceIncluded: false,
      performanceReason: '아파트관리비는 실적 제외',
      benefit: null,
      noBenefitReason: '관리비는 혜택 제외'
    },
    {
      id: 'streaming',
      dateLabel: '07.07',
      merchant: '체리플레이',
      amount: 13_500,
      category: '영상 스트리밍',
      performanceIncluded: true,
      performanceReason: '정기결제 승인 거래',
      benefit: { rule: '영상 스트리밍 50% 청구할인', reason: '공식 홈페이지 월 정기결제', raw: 6_750 }
    },
    {
      id: 'mobile',
      dateLabel: '07.10',
      merchant: '체리모바일',
      amount: 72_400,
      category: '통신요금',
      performanceIncluded: true,
      performanceReason: '통신요금은 실적 인정',
      benefit: { rule: '생활요금 자동납부 5% 청구할인', reason: '이동통신 자동납부', raw: 3_620 }
    },
    {
      id: 'open-market',
      dateLabel: '07.13',
      merchant: '오픈마켓 주문',
      amount: 95_000,
      category: '온라인 쇼핑',
      performanceIncluded: true,
      performanceReason: '일반 신용판매 승인 거래',
      benefit: { rule: '간편결제 10% 청구할인', reason: '지정 간편결제라면 건당 조건 충족', raw: 9_500 },
      question: {
        yesLabel: '네, 체리페이',
        noLabel: '아니요, 카드 직접 결제',
        noReason: '지정 간편결제가 아니라 혜택 제외'
      }
    },
    {
      id: 'electricity',
      dateLabel: '07.18',
      merchant: '체리에너지 전기요금',
      amount: 86_000,
      category: '공과금',
      performanceIncluded: false,
      performanceReason: '전기요금은 실적 제외',
      benefit: { rule: '생활요금 자동납부 5% 청구할인', reason: '전기요금 자동납부는 혜택 대상', raw: 4_300 }
    },
    {
      id: 'academy',
      dateLabel: '07.22',
      merchant: '체리외국어학원',
      amount: 120_000,
      category: '교육',
      performanceIncluded: true,
      performanceReason: '학원 결제는 실적 인정',
      benefit: null,
      noBenefitReason: '교육 업종은 혜택 제외'
    },
    {
      id: 'gift-card',
      dateLabel: '07.25',
      merchant: '합성 기프트카드',
      amount: 50_000,
      category: '상품권',
      performanceIncluded: false,
      performanceReason: '상품권 구매는 실적 제외',
      benefit: null,
      noBenefitReason: '상품권 구매는 혜택 제외'
    },
    {
      id: 'fresh-store',
      dateLabel: '07.27',
      merchant: '체리프레시',
      amount: 21_000,
      category: '생활 쇼핑',
      performanceIncluded: true,
      performanceReason: '일반 신용판매 승인 거래',
      benefit: { rule: '간편결제 10% 청구할인', reason: '체리페이 결제 · 건당 1만원 이상', raw: 2_100 }
    }
  ];

  const scenarioPresets = {
    partial: {
      assumption: 'tier300',
      selected: ['cherry-market', 'streaming', 'mobile'],
      answers: {}
    },
    empty: {
      assumption: 'tier300',
      selected: [],
      answers: {}
    },
    exhausted: {
      assumption: 'tier300',
      selected: ['cherry-market', 'streaming', 'mobile', 'open-market', 'electricity', 'academy', 'fresh-store'],
      answers: { 'open-market': 'yes' }
    },
    ambiguous: {
      assumption: 'tier300',
      selected: ['cherry-market', 'open-market', 'electricity'],
      answers: {}
    }
  };

  const state = {
    activeScreen: 'policy',
    policyConfirmed: false,
    questionsReviewed: false,
    assumption: 'tier300',
    selected: new Set(),
    answers: {}
  };

  const $ = selector => document.querySelector(selector);
  const $$ = selector => Array.from(document.querySelectorAll(selector));

  function rawBenefitFor(transaction, unresolvedMode) {
    if (!transaction.benefit) return 0;
    if (!transaction.question) return transaction.benefit.raw;
    const answer = state.answers[transaction.id];
    if (answer === 'yes') return transaction.benefit.raw;
    if (answer === 'no') return 0;
    return unresolvedMode === 'maximum' ? transaction.benefit.raw : 0;
  }

  function allocateBenefits(unresolvedMode) {
    const limit = assumptions[state.assumption].limit;
    let remaining = limit;
    let total = 0;
    const rows = new Map();

    transactions.forEach(transaction => {
      if (!state.selected.has(transaction.id)) {
        rows.set(transaction.id, { raw: 0, applied: 0 });
        return;
      }
      const raw = rawBenefitFor(transaction, unresolvedMode);
      const applied = Math.min(raw, remaining);
      rows.set(transaction.id, { raw, applied });
      remaining -= applied;
      total += applied;
    });

    return { limit, total, rows };
  }

  function formatRange(low, high, formatter) {
    return low === high ? formatter(low) : `${formatter(low)}–${formatter(high)}`;
  }

  function wonRange(first, second) {
    return formatRange(Math.min(first, second), Math.max(first, second), won);
  }

  function hasUnresolvedSelectedTransaction() {
    return transactions.some(transaction =>
      transaction.question && state.selected.has(transaction.id) && !state.answers[transaction.id]
    );
  }

  function classificationFor(transaction) {
    if (!transaction.benefit) return { label: '혜택 없음', className: 'is-none' };
    if (!transaction.question) return { label: '혜택 대상', className: 'is-target' };
    if (state.answers[transaction.id] === 'yes') return { label: '혜택 대상', className: 'is-target' };
    if (state.answers[transaction.id] === 'no') return { label: '혜택 없음', className: 'is-none' };
    return { label: '확인 필요', className: 'is-question' };
  }

  function policyReasonFor(transaction) {
    if (!transaction.benefit) return transaction.noBenefitReason;
    if (transaction.question && state.answers[transaction.id] === 'no') return transaction.question.noReason;
    return `${transaction.benefit.rule} · ${transaction.benefit.reason}`;
  }

  function rowSummaryFor(transaction) {
    const classification = classificationFor(transaction);
    if (classification.className === 'is-question') return '확인 필요 · 결제수단';
    return classification.label;
  }

  function benefitDisplay(transaction, minimumEntry, maximumEntry) {
    const selected = state.selected.has(transaction.id);
    const classification = classificationFor(transaction);

    if (!selected) {
      if (classification.className === 'is-none') return { text: '0원', className: 'is-none' };
      if (classification.className === 'is-question') {
        return { text: `한도 전 0–${won(transaction.benefit.raw)}`, className: 'is-question' };
      }
      return { text: `한도 전 +${won(transaction.benefit.raw)}`, className: '' };
    }

    if (transaction.question && !state.answers[transaction.id]) {
      return { text: wonRange(minimumEntry.applied, maximumEntry.applied), className: 'is-question' };
    }
    const low = Math.min(minimumEntry.applied, maximumEntry.applied);
    const high = Math.max(minimumEntry.applied, maximumEntry.applied);
    if (low !== high) return { text: wonRange(low, high), className: 'is-question' };
    if (minimumEntry.applied > 0) return { text: `+${won(minimumEntry.applied)}`, className: '' };
    if (classification.className === 'is-none') return { text: '0원', className: 'is-none' };
    return { text: '실제 0원', className: 'is-none' };
  }

  function lossNoteFor(transaction, minimumEntry, maximumEntry) {
    if (!transaction.benefit || state.answers[transaction.id] === 'no') return '';
    if (transaction.question && !state.answers[transaction.id]) {
      return '결제수단 확인 전이라 실제 혜택과 뒤 거래의 한도 배분이 범위로 계산됩니다.';
    }
    if (assumptions[state.assumption].limit === 0) return '전월 실적 가정으로 월 한도가 0원입니다.';
    if (minimumEntry.applied !== maximumEntry.applied) return '확인 전 거래에 따라 실제 적용액이 달라집니다.';
    const missed = minimumEntry.raw - minimumEntry.applied;
    if (missed > 0 && minimumEntry.applied > 0) return '거래일 순으로 남은 월 한도만 적용했습니다.';
    if (missed > 0) return '앞선 거래에서 월 한도를 모두 사용했습니다.';
    return '';
  }

  function calculationMarkup(transaction, minimumEntry, maximumEntry) {
    if (!state.selected.has(transaction.id)) return '';
    const rawLow = Math.min(minimumEntry.raw, maximumEntry.raw);
    const rawHigh = Math.max(minimumEntry.raw, maximumEntry.raw);
    const appliedLow = Math.min(minimumEntry.applied, maximumEntry.applied);
    const appliedHigh = Math.max(minimumEntry.applied, maximumEntry.applied);
    const missedMinimumPath = minimumEntry.raw - minimumEntry.applied;
    const missedMaximumPath = maximumEntry.raw - maximumEntry.applied;
    const note = lossNoteFor(transaction, minimumEntry, maximumEntry);

    return `
      <div class="calculation-values">
        <span>한도 전<b>${escapeHTML(wonRange(rawLow, rawHigh))}</b></span>
        <span>실제 적용<b>${escapeHTML(wonRange(appliedLow, appliedHigh))}</b></span>
        <span>미수혜<b>${escapeHTML(wonRange(missedMinimumPath, missedMaximumPath))}</b></span>
      </div>
      ${note ? `<p class="calculation-note">${escapeHTML(note)}</p>` : ''}
    `;
  }

  function rowDetailsMarkup(transaction, minimumEntry, maximumEntry, isOpen) {
    const performanceStatus = transaction.performanceIncluded ? '실적 인정' : '실적 제외';
    const benefitStatus = classificationFor(transaction).label;
    return `
      <details class="row-details"${isOpen ? ' open' : ''}>
        <summary>근거 보기</summary>
        <dl class="row-evidence">
          <div><dt>실적</dt><dd>${escapeHTML(`${performanceStatus} · ${transaction.performanceReason}`)}</dd></div>
          <div><dt>혜택</dt><dd>${escapeHTML(`${benefitStatus} · ${policyReasonFor(transaction)}`)}</dd></div>
        </dl>
        ${calculationMarkup(transaction, minimumEntry, maximumEntry)}
      </details>
    `;
  }

  function renderTransactions(minimum, maximum) {
    const openDetails = new Set(
      $$('#transaction-list .transaction-row > details[open]').map(details =>
        details.closest('.transaction-row').dataset.transactionId
      )
    );
    // This innerHTML boundary contains only escaped fixture text and numeric formatting.
    $('#transaction-list').innerHTML = transactions.map(transaction => {
      const selected = state.selected.has(transaction.id);
      const minimumEntry = minimum.rows.get(transaction.id);
      const maximumEntry = maximum.rows.get(transaction.id);
      const benefit = benefitDisplay(transaction, minimumEntry, maximumEntry);
      const rowId = escapeHTML(transaction.id);
      const checkboxId = `select-${rowId}`;
      const merchantId = `merchant-${rowId}`;
      const dateId = `date-${rowId}`;
      const amountId = `amount-${rowId}`;
      const summaryId = `summary-${rowId}`;
      const benefitId = `benefit-${rowId}`;
      const needsQuestion = transaction.question && !state.answers[transaction.id];

      return `
        <li class="transaction-row" data-transaction-id="${rowId}" data-selected="${selected}">
          <label class="transaction-label" for="${checkboxId}">
            <input
              id="${checkboxId}"
              class="transaction-check"
              type="checkbox"
              data-transaction-id="${rowId}"
              aria-labelledby="${merchantId} ${dateId} ${amountId}"
              aria-describedby="${summaryId} ${benefitId}"
              ${selected ? 'checked' : ''}
            >
            <span class="row-copy">
              <strong id="${merchantId}" class="row-merchant">${escapeHTML(transaction.merchant)}</strong>
              <span id="${dateId}" class="row-date">${escapeHTML(transaction.dateLabel)} · 승인</span>
              <span id="${summaryId}" class="row-summary">${escapeHTML(rowSummaryFor(transaction))}</span>
            </span>
            <span class="row-side">
              <strong id="${amountId}" class="row-amount">${escapeHTML(won(transaction.amount))}</strong>
              <span id="${benefitId}" class="row-benefit ${escapeHTML(benefit.className)}">${escapeHTML(benefit.text)}</span>
            </span>
          </label>
          ${needsQuestion ? `<div class="row-actions"><button class="question-review-button" type="button" data-review-question="${rowId}" aria-label="${escapeHTML(transaction.merchant)} 결제수단 확인">확인하기</button></div>` : ''}
          ${rowDetailsMarkup(transaction, minimumEntry, maximumEntry, openDetails.has(transaction.id))}
        </li>
      `;
    }).join('');
  }

  function performanceOutlook(performanceTotal) {
    if (performanceTotal < 300_000) return `30만원 구간까지 ${won(300_000 - performanceTotal)} 남음`;
    if (performanceTotal < 600_000) return `30만원 구간 · 60만원까지 ${won(600_000 - performanceTotal)} 남음`;
    return '60만원 구간 충족';
  }

  function renderSummary(minimum, maximum) {
    const selectedTransactions = transactions.filter(transaction => state.selected.has(transaction.id));
    const selectedTotal = selectedTransactions.reduce((sum, transaction) => sum + transaction.amount, 0);
    const performanceTotal = selectedTransactions.reduce(
      (sum, transaction) => sum + (transaction.performanceIncluded ? transaction.amount : 0),
      0
    );
    const minimumBenefit = minimum.total;
    const maximumBenefit = maximum.total;
    const assumption = assumptions[state.assumption];
    const unresolved = hasUnresolvedSelectedTransaction();
    const benefitText = wonRange(minimumBenefit, maximumBenefit);
    const rateText = selectedTotal > 0
      ? formatRange(
          minimumBenefit / selectedTotal * 100,
          maximumBenefit / selectedTotal * 100,
          value => `${value.toFixed(2)}%`
        )
      : '—';
    const netRateText = selectedTotal > 0
      ? formatRange(
          (minimumBenefit - 1_000) / selectedTotal * 100,
          (maximumBenefit - 1_000) / selectedTotal * 100,
          value => `${value.toFixed(2)}%`
        )
      : '—';
    const remainingLow = Math.max(0, assumption.limit - maximumBenefit);
    const remainingHigh = Math.max(0, assumption.limit - minimumBenefit);

    $('#benefit-total').textContent = benefitText;
    $('#picking-rate').textContent = rateText;
    $('#selected-total').textContent = won(selectedTotal);
    $('#selected-count').textContent = `${selectedTransactions.length}건`;
    $('#performance-total').textContent = won(performanceTotal);
    $('#performance-outlook').textContent = performanceOutlook(performanceTotal);
    $('#limit-usage').textContent = `${benefitText} / ${won(assumption.limit)}`;
    $('#limit-remaining').textContent = assumption.limit > 0 ? wonRange(remainingLow, remainingHigh) : '없음';
    $('#net-picking-rate').textContent = netRateText;
    $('#picking-rate-help').textContent = selectedTotal > 0
      ? '피킹률은 선택한 결제액 전체를 분모로 계산합니다.'
      : '거래를 선택하면 계산됩니다.';
    $('#range-note').hidden = !(unresolved && minimumBenefit !== maximumBenefit);

    const progress = $('#limit-progress');
    const progressPercent = assumption.limit > 0 ? Math.min(100, maximumBenefit / assumption.limit * 100) : 0;
    progress.setAttribute('aria-valuemax', String(Math.max(1, assumption.limit)));
    progress.setAttribute('aria-valuenow', String(maximumBenefit));
    progress.setAttribute(
      'aria-valuetext',
      assumption.limit === 0
        ? '제공되는 통합 월 한도 없음'
        : unresolved && minimumBenefit !== maximumBenefit
          ? `혜택 ${benefitText}, 남은 한도 ${wonRange(remainingLow, remainingHigh)}`
          : `${won(maximumBenefit)} 사용, ${won(remainingLow)} 남음`
    );
    progress.querySelector('span').style.width = `${progressPercent}%`;

    return { count: selectedTransactions.length, benefitText, rateText };
  }

  function renderQuestion() {
    const answer = state.answers['open-market'];
    $('#question-answer-yes').checked = answer === 'yes';
    $('#question-answer-no').checked = answer === 'no';
    const result = $('#question-result');
    const button = $('#confirm-questions');
    const classificationSummary = $('#classification-summary');

    result.className = 'question-result';
    if (answer === 'yes') {
      classificationSummary.textContent = '혜택 대상 6 · 혜택 없음 3 · 확인 필요 0';
      result.classList.add('is-resolved');
      result.querySelector('strong').textContent = '체리페이';
      result.querySelector('span').textContent = '한도 전 혜택 9,500원';
      button.textContent = '답변 반영하고 거래 선택';
    } else if (answer === 'no') {
      classificationSummary.textContent = '혜택 대상 5 · 혜택 없음 4 · 확인 필요 0';
      result.classList.add('is-resolved');
      result.querySelector('strong').textContent = '카드 직접 결제';
      result.querySelector('span').textContent = '간편결제 혜택 0원';
      button.textContent = '답변 반영하고 거래 선택';
    } else {
      classificationSummary.textContent = '혜택 대상 5 · 혜택 없음 3 · 확인 필요 1';
      result.classList.add('is-pending');
      result.querySelector('strong').textContent = '미응답';
      result.querySelector('span').textContent = '0원–최대 9,500원 범위로 계산';
      button.textContent = '범위로 거래 선택';
    }
  }

  function canOpenScreen(screen) {
    if (screen === 'policy') return true;
    if (screen === 'questions') return state.policyConfirmed;
    return state.policyConfirmed && state.questionsReviewed;
  }

  function renderStepAccess() {
    $$('[data-product-screen]').forEach(button => {
      const screen = button.dataset.productScreen;
      button.disabled = !canOpenScreen(screen);
      if (screen === state.activeScreen) button.setAttribute('aria-current', 'step');
      else button.removeAttribute('aria-current');
    });

    const policyState = $('#policy-confirmation');
    policyState.className = `state-badge ${state.policyConfirmed ? 'is-confirmed' : 'is-pending'}`;
    policyState.textContent = state.policyConfirmed ? '확인함' : '확인 전';
    $('#confirm-policy').textContent = state.policyConfirmed ? '조건 확인하고 다음' : '카드 조건 확인';
  }

  function render(options = {}) {
    const minimum = allocateBenefits('minimum');
    const maximum = allocateBenefits('maximum');
    const summary = renderSummary(minimum, maximum);
    renderQuestion();
    renderTransactions(minimum, maximum);
    renderStepAccess();
    $('#performance-assumption').value = state.assumption;

    if (options.focusId) requestAnimationFrame(() => document.getElementById(options.focusId)?.focus());
    if (options.announce) {
      $('#update-announcement').textContent = typeof options.announce === 'string'
        ? options.announce
        : `계산 갱신. 선택 ${summary.count}건, 예상 혜택 ${summary.benefitText}, 피킹률 ${summary.rateText}.`;
    }
  }

  function setProductScreen(screen, options = {}) {
    if (!options.force && !canOpenScreen(screen)) {
      $('#update-announcement').textContent = screen === 'questions'
        ? '카드 조건을 먼저 확인하세요.'
        : '카드 조건과 확인할 거래를 먼저 검토하세요.';
      return;
    }

    state.activeScreen = screen;
    $('#policy-screen').hidden = screen !== 'policy';
    $('#questions-screen').hidden = screen !== 'questions';
    $('#transactions-screen').hidden = screen !== 'transactions';
    $('#review-screen').value = screen;
    renderStepAccess();

    if (options.focusId) requestAnimationFrame(() => document.getElementById(options.focusId)?.focus());
    if (options.announce) {
      const labels = { policy: '카드 조건', questions: '확인할 거래', transactions: '거래 선택' };
      $('#update-announcement').textContent = `${labels[screen]} 화면으로 이동했습니다.`;
    }
  }

  function applyScenario(name) {
    const preset = scenarioPresets[name];
    state.assumption = preset.assumption;
    state.selected = new Set(preset.selected);
    state.answers = { ...preset.answers };
    render({ announce: true });
  }

  $('#scenario').addEventListener('change', event => applyScenario(event.target.value));
  $('#review-screen').addEventListener('change', event => {
    const headingIds = { policy: 'policy-page-title', questions: 'questions-page-title', transactions: 'transactions-page-title' };
    setProductScreen(event.target.value, { force: true, focusId: headingIds[event.target.value], announce: true });
  });
  $$('[data-product-screen]').forEach(button => {
    button.addEventListener('click', () => setProductScreen(button.dataset.productScreen, { announce: true }));
  });

  $('#confirm-policy').addEventListener('click', () => {
    state.policyConfirmed = true;
    renderStepAccess();
    setProductScreen('questions', { focusId: 'questions-page-title', announce: true });
  });

  $('#question-form').addEventListener('change', event => {
    state.answers['open-market'] = event.target.value;
    const announcement = event.target.value === 'yes'
      ? '체리페이로 분류했습니다. 한도 전 혜택 9,500원.'
      : '카드 직접 결제로 분류했습니다. 간편결제 혜택 0원.';
    render({ focusId: event.target.id, announce: announcement });
  });

  $('#confirm-questions').addEventListener('click', () => {
    state.questionsReviewed = true;
    renderStepAccess();
    if (state.policyConfirmed) {
      setProductScreen('transactions', { focusId: 'transactions-page-title', announce: true });
    } else {
      setProductScreen('policy', { focusId: 'policy-page-title', announce: true });
    }
  });

  $('#performance-assumption').addEventListener('change', event => {
    state.assumption = event.target.value;
    render({ focusId: event.target.id, announce: true });
  });

  $('#transaction-list').addEventListener('change', event => {
    const transactionId = event.target.dataset.transactionId;
    if (!transactionId) return;
    if (event.target.checked) state.selected.add(transactionId);
    else state.selected.delete(transactionId);
    render({ focusId: event.target.id, announce: true });
  });

  $('#transaction-list').addEventListener('click', event => {
    const transactionId = event.target.dataset.reviewQuestion;
    if (!transactionId) return;
    setProductScreen('questions', { focusId: 'questions-page-title', announce: true });
  });

  $('#select-all').addEventListener('click', () => {
    state.selected = new Set(transactions.map(transaction => transaction.id));
    render({ focusId: 'select-all', announce: true });
  });

  $('#clear-all').addEventListener('click', () => {
    state.selected.clear();
    render({ focusId: 'clear-all', announce: true });
  });

  applyScenario('partial');
  setProductScreen('policy');
})();
