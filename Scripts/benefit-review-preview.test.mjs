import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../Sources/CherryPickerServer/ProductWebPage.swift', import.meta.url), 'utf8');
const preview = source.slice(source.indexOf('              async function updateReviewPreview()'), source.indexOf('              async function openDetail('));

function fixture({ integrated = false, maximum = 100 } = {}) {
  const amount = { textContent: '' };
  const progress = { hidden: false };
  const wrap = { hidden: false, querySelector: selector => selector === 'strong' ? amount : progress };
  const excluded = { checked: false };
  const input = { value: 'benefit', disabled: false };
  const requests = [];
  const errors = [];
  const goals = [];
  const selectedCard = { benefits: [{ id: 'benefit', maximumAmount: 999 }] };
  const state = { activeTransaction: { id: 'transaction' }, dashboard: {}, view: 'detail' };
  const context = vm.createContext({
    state,
    card: () => selectedCard,
    $: selector => selector === '#aggregation-excluded' ? excluded : { classList: { toggle() {} } },
    $$: () => [input],
    document: {
      querySelector: () => ({ value: 'included' }),
      getElementById: () => wrap,
    },
    api: (path, options) => new Promise((resolve, reject) => requests.push({ path, options, resolve, reject })),
    won: value => `${value}원`,
    clearError() { errors.length = 0; },
    showError(error) { errors.push(error); },
    performanceGoalFor: amount => amount,
    renderPerformanceGoal: goal => goals.push(goal),
    setProgress: (_, received, limit) => { progress.received = received; progress.maximum = limit; },
  });
  vm.runInContext(`let reviewPreviewSequence = 0; ${preview}`, context);
  return {
    state, amount, progress, wrap, excluded, input, requests, errors, goals,
    update: () => vm.runInContext('updateReviewPreview()', context),
    response: received => ({ dashboard: {
      performance: { currentAmount: 500 },
      benefitLimit: { type: integrated ? 'integrated' : 'perBenefit', receivedAmount: received, maximumAmount: maximum },
      benefits: [{ id: 'benefit', receivedAmount: received, maximumAmount: maximum }],
    } }),
  };
}

test('preview uses server allocation and effective limit, without saving the review', async () => {
  const f = fixture({ maximum: 0 });
  const pending = f.update();
  assert.equal(f.amount.textContent, '계산 중…');
  assert.equal(f.progress.hidden, true);
  assert.equal(f.requests[0].path, '/api/v1/transactions/transaction/review-preview');
  assert.equal(f.requests[0].options.method, 'POST');
  assert.deepEqual(JSON.parse(f.requests[0].options.body), {
    review: { performance: 'included', benefitIds: ['benefit'], memo: '' }, aggregationExcluded: false,
  });
  f.requests[0].resolve(f.response(0));
  await pending;
  assert.equal(f.amount.textContent, '0원 / 0원');
  assert.equal(f.progress.maximum, 0);
  assert.equal(f.requests.length, 1);
  assert.deepEqual(f.state.dashboard, {});
});

test('out-of-order responses cannot replace the latest integrated preview', async () => {
  const f = fixture({ integrated: true });
  const older = f.update();
  const newer = f.update();
  f.requests[1].resolve(f.response(10));
  await newer;
  f.requests[0].resolve(f.response(50));
  await older;
  assert.equal(f.amount.textContent, '10원 / 100원');
  assert.equal(f.progress.received, 10);
  assert.deepEqual(f.goals, [500]);
});

test('errors clear pending values and a later successful preview recovers', async () => {
  const f = fixture();
  const first = f.update();
  f.requests[0].reject(new Error('offline'));
  await first;
  assert.equal(f.amount.textContent, '계산 실패');
  assert.equal(f.errors.length, 1);
  const retry = f.update();
  f.requests[1].resolve(f.response(10));
  await retry;
  assert.equal(f.amount.textContent, '10원 / 100원');
  assert.equal(f.errors.length, 0);
});

test('excluded reviews hide benefits and responses after leaving detail are ignored', async () => {
  const f = fixture();
  f.excluded.checked = true;
  const pending = f.update();
  assert.equal(f.wrap.hidden, true);
  assert.equal(f.input.disabled, true);
  assert.deepEqual(JSON.parse(f.requests[0].options.body).review.benefitIds, []);
  f.state.view = 'inbox';
  f.requests[0].reject(new Error('stale failure'));
  await pending;
  assert.equal(f.errors.length, 0);
});
