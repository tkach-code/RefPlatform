document.addEventListener('DOMContentLoaded', () => {
  const year = document.getElementById('year');
  if (year) {
    year.textContent = new Date().getFullYear();
  }

  const button = document.getElementById('hello-btn');
  const output = document.getElementById('output');
  if (button && output) {
    button.addEventListener('click', () => {
      output.textContent = `Hello! The time is ${new Date().toLocaleTimeString()}.`;
    });
  }
});
