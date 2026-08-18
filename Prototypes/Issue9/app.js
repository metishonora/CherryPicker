const views = {
  dashboard: document.querySelector('#dashboard-view'),
  review: document.querySelector('#review-view')
};

function setView(name) {
  Object.entries(views).forEach(([key, element]) => { element.hidden = key !== name; });
  document.querySelectorAll('[data-show]').forEach(button => {
    button.setAttribute('aria-pressed', String(button.dataset.show === name));
  });
  document.querySelectorAll('.product-nav [data-view]').forEach(button => {
    if (button.dataset.view === name) button.setAttribute('aria-current', 'page');
    else button.removeAttribute('aria-current');
  });
  window.scrollTo({ top: 0, behavior: 'smooth' });
}

document.querySelectorAll('[data-show], [data-view]').forEach(button => {
  button.addEventListener('click', () => {
    if (views[button.dataset.show || button.dataset.view]) {
      setView(button.dataset.show || button.dataset.view);
    }
  });
});

const transactionAmount = 12_500;
const monthlyLimit = 6_000;

document.querySelectorAll('.benefit-choice').forEach(choice => {
  const checkbox = choice.querySelector('input');
  const preview = choice.querySelector('.choice-preview');
  const amount = Math.trunc(transactionAmount * 0.2);
  const base = Number(choice.dataset.base);
  const total = Math.min(monthlyLimit, base + amount);
  preview.innerHTML = `이번 거래 ${amount.toLocaleString('ko-KR')}원 · 월 누적 <strong>${total.toLocaleString('ko-KR')}원 / ${monthlyLimit.toLocaleString('ko-KR')}원</strong>`;
  checkbox.addEventListener('change', () => { preview.hidden = !checkbox.checked; });
});

const excludeToggle = document.querySelector('#exclude-toggle');
const reviewForm = document.querySelector('#review-form');
excludeToggle.addEventListener('change', () => {
  reviewForm.classList.toggle('is-disabled', excludeToggle.checked);
  reviewForm.querySelectorAll('input, textarea, button').forEach(control => {
    control.disabled = excludeToggle.checked;
  });
});

document.querySelector('#save-review').addEventListener('click', () => {
  const toast = document.querySelector('#toast');
  toast.hidden = false;
  window.setTimeout(() => { toast.hidden = true; setView('dashboard'); }, 1300);
});
