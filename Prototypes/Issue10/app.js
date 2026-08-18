const fixtureStorageKey = 'cherrypicker-issue-10-offset-fixture';
const offsetInputs = Array.from(document.querySelectorAll('.cp-offset-input'));
const form = document.querySelector('#settings-form');
const toast = document.querySelector('#toast');
let toastTimer;

function parseWonAmount(value) {
  const compact = value.replaceAll(',', '').trim();
  if (!/^-?\d+$/.test(compact)) return null;
  const amount = Number(compact);
  return Number.isSafeInteger(amount) ? amount : null;
}

function errorElementFor(input) {
  return document.querySelector(`#${input.id}-error`);
}

function setInputError(input, hasError) {
  input.setAttribute('aria-invalid', String(hasError));
  errorElementFor(input).hidden = !hasError;
}

function validateOffset(input) {
  const amount = parseWonAmount(input.value);
  setInputError(input, amount === null);
  return amount;
}

function showToast(message) {
  window.clearTimeout(toastTimer);
  toast.textContent = message;
  toast.hidden = false;
  toastTimer = window.setTimeout(() => { toast.hidden = true; }, 1800);
}

function restoreSavedFixture() {
  let saved;
  try {
    saved = JSON.parse(window.sessionStorage.getItem(fixtureStorageKey));
  } catch {
    saved = null;
  }
  if (!saved) return;

  for (const input of offsetInputs) {
    if (Number.isSafeInteger(saved[input.name])) input.value = String(saved[input.name]);
  }
}

offsetInputs.forEach(input => {
  input.addEventListener('input', () => {
    if (input.getAttribute('aria-invalid') === 'true') validateOffset(input);
  });
  input.addEventListener('blur', () => validateOffset(input));
});

form.addEventListener('submit', event => {
  event.preventDefault();

  if (!form.checkValidity()) {
    form.reportValidity();
    return;
  }

  const values = {};
  let firstInvalidInput;
  for (const input of offsetInputs) {
    const value = validateOffset(input);
    if (value === null) {
      firstInvalidInput ??= input;
    } else {
      values[input.name] = value;
    }
  }

  if (firstInvalidInput) {
    firstInvalidInput.focus();
    showToast('입력값을 확인해주세요');
    return;
  }

  for (const input of offsetInputs) input.value = String(values[input.name]);
  window.sessionStorage.setItem(fixtureStorageKey, JSON.stringify(values));
  showToast('카드 설정을 저장했습니다');
});

restoreSavedFixture();
