const earliestMonth = '2026-08';
const prototypeCurrentMonth = '2027-08';
let selectedMonth = earliestMonth;
let visibleYear = 2026;

const trigger = document.querySelector('#month-picker-trigger');
const picker = document.querySelector('#month-picker');
const periodLabel = document.querySelector('#period-label');
const pickerYear = document.querySelector('#picker-year');
const monthGrid = document.querySelector('#month-grid');
const previousYear = document.querySelector('#previous-year');
const nextYear = document.querySelector('#next-year');
const toast = document.querySelector('#toast');

function monthKey(year, month) {
  return `${year}-${String(month).padStart(2, '0')}`;
}

function shiftedMonth(value, offset) {
  const [year, month] = value.split('-').map(Number);
  const shifted = new Date(Date.UTC(year, month - 1 + offset, 1));
  return monthKey(shifted.getUTCFullYear(), shifted.getUTCMonth() + 1);
}

function labelForMonth(value) {
  const [year, month] = value.split('-').map(Number);
  return `${year}년 ${month}월`;
}

function syncPeriod() {
  periodLabel.textContent = labelForMonth(selectedMonth);
  document.querySelector('[data-month-step="-1"]').disabled = selectedMonth <= earliestMonth;
  document.querySelector('[data-month-step="1"]').disabled = selectedMonth >= prototypeCurrentMonth;
}

function renderPicker() {
  pickerYear.textContent = `${visibleYear}년`;
  previousYear.disabled = visibleYear <= 2026;
  nextYear.disabled = visibleYear >= 2027;
  monthGrid.replaceChildren(...Array.from({ length: 12 }, (_, index) => {
    const month = index + 1;
    const key = monthKey(visibleYear, month);
    const button = document.createElement('button');
    button.type = 'button';
    button.textContent = `${month}월`;
    button.dataset.month = key;
    button.disabled = key < earliestMonth || key > prototypeCurrentMonth;
    button.setAttribute('aria-pressed', String(key === selectedMonth));
    button.addEventListener('click', () => selectMonth(key));
    return button;
  }));
}

function openPicker() {
  visibleYear = Number(selectedMonth.slice(0, 4));
  renderPicker();
  picker.hidden = false;
  trigger.setAttribute('aria-expanded', 'true');
  monthGrid.querySelector('[aria-pressed="true"]:not(:disabled)')?.focus();
}

function closePicker({ restoreFocus = false } = {}) {
  picker.hidden = true;
  trigger.setAttribute('aria-expanded', 'false');
  if (restoreFocus) trigger.focus();
}

function selectMonth(value) {
  selectedMonth = value;
  syncPeriod();
  closePicker({ restoreFocus: true });
  toast.textContent = `${labelForMonth(value)}로 이동했어요`;
  toast.hidden = false;
  window.setTimeout(() => { toast.hidden = true; }, 1400);
}

trigger.addEventListener('click', () => {
  if (picker.hidden) openPicker();
  else closePicker();
});

previousYear.addEventListener('click', () => { visibleYear -= 1; renderPicker(); });
nextYear.addEventListener('click', () => { visibleYear += 1; renderPicker(); });

document.querySelectorAll('[data-month-step]').forEach(button => {
  button.addEventListener('click', () => {
    const next = shiftedMonth(selectedMonth, Number(button.dataset.monthStep));
    if (next >= earliestMonth && next <= prototypeCurrentMonth) selectMonth(next);
  });
});

document.addEventListener('click', event => {
  if (!picker.hidden && !event.target.closest('.cp-period-wrap')) closePicker();
});

document.addEventListener('keydown', event => {
  if (event.key === 'Escape' && !picker.hidden) closePicker({ restoreFocus: true });
});

syncPeriod();
