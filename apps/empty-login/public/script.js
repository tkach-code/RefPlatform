'use strict';

const FIT_FONT_SIZE = '--fit-font-size';
const HEIGHT_FILL = 0.85;
const PASSWORD_GLYPH = '•';

const measureContext = document.createElement('canvas').getContext('2d');

function fittedFontSize(control, text, shrinkWithLength) {
  const style = window.getComputedStyle(control);
  const paddingLeft = Number.parseFloat(style.paddingLeft) || 0;
  const paddingRight = Number.parseFloat(style.paddingRight) || 0;
  const availableWidth = control.clientWidth - paddingLeft - paddingRight;
  const characterCount = [...text].length;
  const characterScale = shrinkWithLength ? Math.sqrt(characterCount) : 1;

  measureContext.font = `${style.fontStyle} ${style.fontWeight} 1px ${style.fontFamily}`;

  const textWidthAtOnePixel = measureContext.measureText(text).width;
  if (textWidthAtOnePixel <= 0) {
    return 1;
  }

  const heightLimit = control.clientHeight * HEIGHT_FILL / characterScale;
  const widthLimit = availableWidth / textWidthAtOnePixel;
  return Math.max(1, Math.min(heightLimit, widthLimit));
}

function fitControl(control, text, { shrinkWithLength = false } = {}) {
  if (!measureContext) {
    return;
  }

  if (!text) {
    control.style.removeProperty(FIT_FONT_SIZE);
    return;
  }

  const fontSize = `${fittedFontSize(control, text, shrinkWithLength)}px`;
  if (control.style.getPropertyValue(FIT_FONT_SIZE) !== fontSize) {
    control.style.setProperty(FIT_FONT_SIZE, fontSize);
  }
}

function visibleInputText(input) {
  if (input.type === 'password') {
    return PASSWORD_GLYPH.repeat(input.value.length);
  }

  return input.value;
}

function observeSize(element, render) {
  if (typeof ResizeObserver !== 'function') {
    window.addEventListener('resize', render);
    return;
  }

  const observer = new ResizeObserver(render);
  observer.observe(element);
}

function initLoginForm(form) {
  const usernameInput = form.querySelector('.username-input');
  const passwordInput = form.querySelector('.password-input');
  const loginButton = form.querySelector('.login-button');

  if (!usernameInput || !passwordInput || !loginButton) {
    return;
  }

  const inputs = [usernameInput, passwordInput];
  const loginLabel = loginButton.getAttribute('aria-label') || 'Login';

  const render = () => {
    inputs.forEach((input) => {
      fitControl(input, visibleInputText(input), { shrinkWithLength: true });
    });

    const hasCredentials = usernameInput.value && passwordInput.value;
    loginButton.textContent = hasCredentials ? loginLabel : '';
    fitControl(loginButton, loginButton.textContent);
  };

  form.addEventListener('input', render);
  observeSize(form, render);
  render();
}

function initHome(home) {
  const username = new URLSearchParams(window.location.search).get('username');
  home.textContent = username ? `Hello ${username}` : 'Hello';

  const render = () => fitControl(home, home.textContent.trim());
  observeSize(home.closest('main') ?? home, render);
  render();
}

function start() {
  const loginForm = document.querySelector('.login-form');
  if (loginForm) {
    initLoginForm(loginForm);
  }

  const home = document.querySelector('.home');
  if (home) {
    initHome(home);
  }
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', start);
} else {
  start();
}
